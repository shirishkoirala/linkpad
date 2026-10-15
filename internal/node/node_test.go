package node

import (
	"crypto/tls"
	"example.org/linkpad/internal/identity"
	"example.org/linkpad/internal/plugins"
	"example.org/linkpad/internal/protocol"
	"fmt"
	"github.com/gorilla/websocket"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

type fakePointer struct {
	mu    sync.Mutex
	calls int
}

func (f *fakePointer) Capability() string { return protocol.Pointer }
func (f *fakePointer) Handle(m protocol.Message) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	return m.ValidatePointer()
}

type fakeKey struct {
	mu    sync.Mutex
	calls int
}

func (f *fakeKey) Capability() string { return protocol.Key }
func (f *fakeKey) Handle(m protocol.Message) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	return m.ValidateKey()
}
func cert(t *testing.T) tls.Certificate {
	t.Helper()
	c, e := identity.Load(t.TempDir())
	if e != nil {
		t.Fatal(e)
	}
	return c
}
func TestSecureLifecycle(t *testing.T) {
	serverCert, client, other := cert(t), cert(t), cert(t)
	dir := t.TempDir()
	trust, e := OpenTrust(dir)
	if e != nil {
		t.Fatal(e)
	}
	pairing, e := NewPairing(time.Minute)
	if e != nil {
		t.Fatal(e)
	}
	token := pairing.Secret()
	fake := &fakePointer{}
	n := &Node{Trust: trust, Pairing: pairing, Plugins: plugins.Registry{protocol.Pointer: fake}}
	s := httptest.NewUnstartedServer(n.Handler())
	s.TLS = n.TLS(serverCert)
	s.StartTLS()
	defer s.Close()
	url := "wss" + strings.TrimPrefix(s.URL, "https") + "/ws"
	pin := identity.Fingerprint(serverCert.Certificate[0])
	if _, _, e := Connect(client, url, strings.Repeat("0", 64), token, nil); e == nil {
		t.Fatal("accepted wrong pin")
	}
	if _, _, e := Connect(client, url, pin, "", nil); e == nil {
		t.Fatal("accepted unpaired identity")
	}
	if _, _, e := Connect(client, url, pin, "bad", nil); e == nil {
		t.Fatal("accepted bad token")
	}
	conn, caps, e := Connect(client, url, pin, token, []string{protocol.Pointer, "unknown", protocol.Pointer})
	if e != nil {
		t.Fatal(e)
	}
	if len(caps) != 1 || caps[0] != protocol.Pointer {
		t.Fatalf("bad negotiation: %v", caps)
	}
	conn.SetReadDeadline(time.Now().Add(time.Second))
	if e = conn.WriteJSON(protocol.Message{Version: 1, Type: "pointer", DX: 4, DY: -2}); e != nil {
		t.Fatal(e)
	}
	var reply protocol.Message
	if e = conn.ReadJSON(&reply); e != nil || reply.Type != "ack" {
		t.Fatalf("pointer: %v %v", reply, e)
	}
	conn.Close()
	fake.mu.Lock()
	calls := fake.calls
	fake.mu.Unlock()
	if calls != 1 {
		t.Fatal("backend not invoked")
	}
	if _, _, e := Connect(other, url, pin, token, nil); e == nil {
		t.Fatal("reused pairing secret")
	}
	persisted, e := OpenTrust(dir)
	if e != nil || !persisted.Contains(identity.Fingerprint(client.Certificate[0])) {
		t.Fatalf("trust not persisted: %v", e)
	}
	conn, _, e = Connect(client, url, pin, "", nil)
	if e != nil {
		t.Fatal(e)
	}
	defer conn.Close()
	conn.SetReadDeadline(time.Now().Add(time.Second))
	conn.WriteJSON(protocol.Message{Version: 1, Type: "pointer", DX: 1})
	if e = conn.ReadJSON(&reply); e != nil || reply.Type != "error" {
		t.Fatal("unnegotiated capability accepted")
	}
}
func TestKeyNegotiationAndDispatch(t *testing.T) {
	serverCert, client := cert(t), cert(t)
	trust, err := OpenTrust(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	pairing, err := NewPairing(time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	fake := &fakeKey{}
	n := &Node{Trust: trust, Pairing: pairing, Plugins: plugins.Registry{protocol.Key: fake}}
	s := httptest.NewUnstartedServer(n.Handler())
	s.TLS = n.TLS(serverCert)
	s.StartTLS()
	defer s.Close()
	url := "wss" + strings.TrimPrefix(s.URL, "https") + "/ws"
	pin := identity.Fingerprint(serverCert.Certificate[0])
	conn, caps, err := Connect(client, url, pin, pairing.Secret(), []string{protocol.Pointer, protocol.Key})
	if err != nil {
		t.Fatal(err)
	}
	if !protocol.Has(caps, protocol.Key) || protocol.Has(caps, protocol.Pointer) {
		t.Fatalf("bad capabilities: %v", caps)
	}
	conn.SetReadDeadline(time.Now().Add(time.Second))
	if err = conn.WriteJSON(protocol.Message{Version: 1, Type: "key", Key: "left"}); err != nil {
		t.Fatal(err)
	}
	var reply protocol.Message
	if err = conn.ReadJSON(&reply); err != nil || reply.Type != "ack" {
		t.Fatalf("key response: %v %v", reply, err)
	}
	conn.Close()
	fake.mu.Lock()
	calls := fake.calls
	fake.mu.Unlock()
	if calls != 1 {
		t.Fatal("key backend not invoked")
	}
	conn, _, err = Connect(client, url, pin, "", []string{protocol.Pointer})
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	conn.SetReadDeadline(time.Now().Add(time.Second))
	if err = conn.WriteJSON(protocol.Message{Version: 1, Type: "key", Key: "up"}); err != nil {
		t.Fatal(err)
	}
	if err = conn.ReadJSON(&reply); err != nil || reply.Type != "error" {
		t.Fatalf("unnegotiated key accepted: %v %v", reply, err)
	}
}
func TestPairingExpiryAndConcurrency(t *testing.T) {	expired, _ := NewPairing(-time.Second)
	if expired.authorize(expired.Secret(), func() error { return nil }) == nil {
		t.Fatal("expired secret accepted")
	}
	p, _ := NewPairing(time.Minute)
	secret := p.Secret()
	var wg sync.WaitGroup
	count := 0
	var mu sync.Mutex
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if p.authorize(secret, func() error { return nil }) == nil {
				mu.Lock()
				count++
				mu.Unlock()
			}
		}()
	}
	wg.Wait()
	if count != 1 {
		t.Fatalf("accepted %d times", count)
	}
}
func TestMissingClientCertificate(t *testing.T) {
	c := cert(t)
	trust, _ := OpenTrust(t.TempDir())
	n := &Node{Trust: trust, Plugins: plugins.Registry{}}
	s := httptest.NewUnstartedServer(n.Handler())
	s.TLS = n.TLS(c)
	s.StartTLS()
	defer s.Close()
	config, e := identity.PinnedTLS(tls.Certificate{}, identity.Fingerprint(c.Certificate[0]))
	if e != nil {
		t.Fatal(e)
	}
	config.Certificates = nil
	conn, _, e := (&websocket.Dialer{TLSClientConfig: config}).Dial("wss"+strings.TrimPrefix(s.URL, "https")+"/ws", nil)
	if e == nil {
		conn.Close()
		t.Fatal("missing client identity accepted")
	}
}
func TestMalformedAndInvalidMovement(t *testing.T) {
	c, peer := cert(t), cert(t)
	trust, _ := OpenTrust(t.TempDir())
	trust.Add(identity.Fingerprint(peer.Certificate[0]))
	fake := &fakePointer{}
	n := &Node{Trust: trust, Plugins: plugins.Registry{protocol.Pointer: fake}}
	s := httptest.NewUnstartedServer(n.Handler())
	s.TLS = n.TLS(c)
	s.StartTLS()
	defer s.Close()
	url := "wss" + strings.TrimPrefix(s.URL, "https") + "/ws"
	pin := identity.Fingerprint(c.Certificate[0])
	for _, raw := range []string{`{"version":1,"type":"pointer","dx":501}`, `{"version":99,"type":"pointer"}`, `garbage`} {
		conn, _, e := Connect(peer, url, pin, "", []string{protocol.Pointer})
		if e != nil {
			t.Fatal(e)
		}
		conn.SetReadDeadline(time.Now().Add(time.Second))
		conn.WriteMessage(websocket.TextMessage, []byte(raw))
		var m protocol.Message
		e = conn.ReadJSON(&m)
		conn.Close()
		if e == nil && m.Type != "error" {
			t.Fatal("invalid input accepted")
		}
	}
	fake.mu.Lock()
	defer fake.mu.Unlock()
	if fake.calls != 0 {
		t.Fatal("invalid input reached backend")
	}
}

func TestFailedPersistenceDoesNotConsumePairing(t *testing.T) {
	p, err := NewPairing(time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	secret := p.Secret()
	if err = p.authorize(secret, func() error { return fmt.Errorf("disk failure") }); err == nil {
		t.Fatal("accepted failed persistence")
	}
	if err = p.authorize(secret, func() error { return nil }); err != nil {
		t.Fatal("failed write consumed secret")
	}
}

func TestOriginAndOversizedFrame(t *testing.T) {
	c, peer := cert(t), cert(t)
	trust, _ := OpenTrust(t.TempDir())
	trust.Add(identity.Fingerprint(peer.Certificate[0]))
	n := &Node{Trust: trust, Plugins: plugins.Registry{}}
	s := httptest.NewUnstartedServer(n.Handler())
	s.TLS = n.TLS(c)
	s.StartTLS()
	defer s.Close()
	url := "wss" + strings.TrimPrefix(s.URL, "https") + "/ws"
	pin := identity.Fingerprint(c.Certificate[0])
	config, _ := identity.PinnedTLS(peer, pin)
	h := http.Header{}
	h.Set("Origin", "https://example.org")
	conn, response, err := (&websocket.Dialer{TLSClientConfig: config}).Dial(url, h)
	if err == nil {
		conn.Close()
		t.Fatal("browser origin accepted")
	}
	if response == nil || response.StatusCode != 403 {
		t.Fatal("expected forbidden origin")
	}
	response.Body.Close()
	conn, _, err = Connect(peer, url, pin, "", nil)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	conn.SetReadDeadline(time.Now().Add(time.Second))
	if err = conn.WriteMessage(websocket.TextMessage, []byte(strings.Repeat("x", 4097))); err != nil {
		t.Fatal(err)
	}
	if _, _, err = conn.ReadMessage(); err == nil {
		t.Fatal("oversized frame accepted")
	}
}
