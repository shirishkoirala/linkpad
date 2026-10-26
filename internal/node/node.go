package node

import (
	"crypto/rand"
	"crypto/subtle"
	"crypto/tls"
	"encoding/hex"
	"example.org/linkpad/internal/identity"
	"example.org/linkpad/internal/plugins"
	"example.org/linkpad/internal/protocol"
	"fmt"
	"github.com/gorilla/websocket"
	"net/http"
	"sync"
	"sync/atomic"
	"time"
)

type Pairing struct {
	mu      sync.Mutex
	secret  string
	expires time.Time
}

func NewPairing(ttl time.Duration) (*Pairing, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return nil, err
	}
	return &Pairing{secret: hex.EncodeToString(b), expires: time.Now().Add(ttl)}, nil
}
func (p *Pairing) Secret() string       { return p.secret }
func (p *Pairing) ExpiresAt() time.Time { return p.expires }

// authorize serializes token consumption with durable trust persistence.
func (p *Pairing) authorize(token string, save func() error) error {
	if p == nil {
		return fmt.Errorf("pairing closed")
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.secret == "" || time.Now().After(p.expires) || subtle.ConstantTimeCompare([]byte(token), []byte(p.secret)) != 1 {
		return fmt.Errorf("pairing rejected")
	}
	if err := save(); err != nil {
		return err
	}
	p.secret = ""
	return nil
}

type Node struct {
	inputCount     atomic.Uint64
	Trust          *Trust
	Pairing        *Pairing
	Plugins        plugins.Registry
	execution      sync.Mutex
	dragOwner      *websocket.Conn
	dragTimer      *time.Timer
	dragGeneration uint64
	DragTimeout    time.Duration
	management     sync.Mutex
	sessions       map[*websocket.Conn]string
}

// InputCount counts successful remote actions without retaining their contents.
func (n *Node) InputCount() uint64 { return n.inputCount.Load() }

func (n *Node) TLS(cert tls.Certificate) *tls.Config {
	return &tls.Config{MinVersion: tls.VersionTLS13, Certificates: []tls.Certificate{cert}, ClientAuth: tls.RequireAnyClientCert}
}
func (n *Node) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/ws", n.handle)
	return mux
}
func (n *Node) handle(w http.ResponseWriter, r *http.Request) {
	if r.TLS == nil || len(r.TLS.PeerCertificates) != 1 {
		http.Error(w, "client identity required", 401)
		return
	}
	cert := r.TLS.PeerCertificates[0]
	now := time.Now()
	if now.Before(cert.NotBefore) || now.After(cert.NotAfter) {
		http.Error(w, "invalid identity dates", 401)
		return
	}
	id := identity.Fingerprint(cert.Raw)
	// Browser origins are denied; this endpoint serves native peers only.
	if r.Header.Get("Origin") != "" {
		http.Error(w, "native peers only", 403)
		return
	}
	conn, err := (&websocket.Upgrader{HandshakeTimeout: 5 * time.Second}).Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer conn.Close()
	defer n.releaseDrag(conn)
	conn.SetReadLimit(4096)
	conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	send := func(m protocol.Message) error {
		conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
		return conn.WriteJSON(m)
	}
	reject := func(reason string) { _ = send(protocol.Message{Version: 1, Type: "error", Error: reason}) }
	read := func() (protocol.Message, error) {
		kind, b, e := conn.ReadMessage()
		if e != nil {
			return protocol.Message{}, e
		}
		if kind != websocket.TextMessage {
			return protocol.Message{}, fmt.Errorf("text required")
		}
		return protocol.Decode(b)
	}
	first, err := read()
	if err != nil {
		reject("invalid handshake")
		return
	}
	switch first.Type {
	case "pair":
		n.management.Lock()
		err = n.Pairing.authorize(first.Token, func() error { return n.Trust.Add(id) })
		n.management.Unlock()
		if err != nil {
			reject("pairing rejected")
			return
		}
	case "hello":
		if !n.Trust.Contains(id) {
			reject("unpaired device")
			return
		}
	default:
		reject("expected hello or pair")
		return
	}
	negotiated := n.Plugins.Negotiate(first.Capabilities)
	n.management.Lock()
	if !n.Trust.Contains(id) {
		n.management.Unlock()
		reject("device access revoked")
		return
	}
	if n.sessions == nil {
		n.sessions = make(map[*websocket.Conn]string)
	}
	n.sessions[conn] = id
	n.management.Unlock()
	defer func() { n.management.Lock(); delete(n.sessions, conn); n.management.Unlock() }()
	if err = send(protocol.Message{Version: 1, Type: "ready", Capabilities: negotiated}); err != nil {
		return
	}
	for {
		conn.SetReadDeadline(time.Now().Add(90 * time.Second))
		m, err := read()
		if err != nil {
			return
		}
		if m.Type == "hello" {
			if err = send(protocol.Message{Version: 1, Type: "ack"}); err != nil {
				return
			}
			continue
		}
		capability := ""
		switch m.Type {
		case "pointer":
			capability = protocol.Pointer
			err = m.ValidatePointer()
		case "scroll":
			capability = protocol.Scroll
			err = m.ValidateScroll()
		case "key":
			capability = protocol.Key
			err = m.ValidateKey()
		case "keyboard":
			capability = protocol.Keyboard
			if m.Key == "super" {
				capability = protocol.SuperKey
			}
			err = m.ValidateKeyboard()
		case "drag":
			capability = protocol.Drag
			err = m.ValidateDrag()
		}
		if capability == "" || !protocol.Has(negotiated, capability) {
			reject("capability not negotiated")
			return
		}
		// Bound injection to 100 events/sec per connection, and serialize native backend calls.
		if err != nil {
			reject(err.Error())
			return
		}
		processingStarted := time.Now()
		n.management.Lock()
		if n.Trust.Contains(id) {
			err = n.input(conn, capability, m)
		} else {
			err = fmt.Errorf("device access revoked")
		}
		n.management.Unlock()
		if err != nil {
			reject(err.Error())
			return
		}
		n.inputCount.Add(1)
		processingUS := time.Since(processingStarted).Microseconds()
		if err = send(protocol.Message{Version: 1, Type: "ack", ServerProcessingUS: &processingUS}); err != nil {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func Connect(cert tls.Certificate, url, pin, token string, caps []string) (*websocket.Conn, []string, error) {
	config, err := identity.PinnedTLS(cert, pin)
	if err != nil {
		return nil, nil, err
	}
	if len(url) < 6 || url[:6] != "wss://" {
		return nil, nil, fmt.Errorf("wss:// required")
	}
	conn, _, err := (&websocket.Dialer{TLSClientConfig: config, HandshakeTimeout: 5 * time.Second}).Dial(url, nil)
	if err != nil {
		return nil, nil, err
	}
	fail := func(err error) (*websocket.Conn, []string, error) { conn.Close(); return nil, nil, err }
	conn.SetReadLimit(4096)
	conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
	typ := "hello"
	if token != "" {
		typ = "pair"
	}
	if err = conn.WriteJSON(protocol.Message{Version: 1, Type: typ, Token: token, Capabilities: caps}); err != nil {
		return fail(err)
	}
	_, b, err := conn.ReadMessage()
	if err != nil {
		return fail(err)
	}
	m, err := protocol.Decode(b)
	if err != nil {
		return fail(err)
	}
	if m.Type != "ready" {
		return fail(fmt.Errorf("connection rejected: %s", m.Error))
	}
	conn.SetReadDeadline(time.Time{})
	conn.SetWriteDeadline(time.Time{})
	return conn, m.Capabilities, nil
}
