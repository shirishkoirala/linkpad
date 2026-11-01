package node

import (
	"github.com/shirishkoirala/linkpad/internal/identity"
	"github.com/shirishkoirala/linkpad/internal/plugins"
	"github.com/shirishkoirala/linkpad/internal/protocol"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

type fakeScroll struct{ calls atomic.Int32 }

func (f *fakeScroll) Capability() string { return protocol.Scroll }
func (f *fakeScroll) Handle(m protocol.Message) error {
	if err := m.ValidateScroll(); err != nil {
		return err
	}
	f.calls.Add(1)
	return nil
}

func TestScrollNegotiationAndBounds(t *testing.T) {
	serverCert, client := cert(t), cert(t)
	trust, err := OpenTrust(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	pairing, err := NewPairing(time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	fake := &fakeScroll{}
	n := &Node{Trust: trust, Pairing: pairing, Plugins: plugins.Registry{protocol.Scroll: fake}}
	s := httptest.NewUnstartedServer(n.Handler())
	s.TLS = n.TLS(serverCert)
	s.StartTLS()
	defer s.Close()
	url := "wss" + strings.TrimPrefix(s.URL, "https") + "/ws"
	pin := identity.Fingerprint(serverCert.Certificate[0])
	conn, caps, err := Connect(client, url, pin, pairing.Secret(), []string{protocol.Pointer, protocol.Scroll})
	if err != nil {
		t.Fatal(err)
	}
	if !protocol.Has(caps, protocol.Scroll) || protocol.Has(caps, protocol.Pointer) {
		t.Fatalf("bad capabilities: %v", caps)
	}
	conn.SetReadDeadline(time.Now().Add(time.Second))
	if err = conn.WriteJSON(protocol.Message{Version: 1, Type: "scroll", DX: 10, DY: -20}); err != nil {
		t.Fatal(err)
	}
	var reply protocol.Message
	if err = conn.ReadJSON(&reply); err != nil || reply.Type != "ack" {
		t.Fatalf("scroll response: %v %v", reply, err)
	}
	conn.Close()
	if fake.calls.Load() != 1 {
		t.Fatal("scroll not dispatched")
	}
	for _, test := range []struct {
		name string
		caps []string
		msg  protocol.Message
	}{
		{"not negotiated", nil, protocol.Message{Version: 1, Type: "scroll", DY: 1}},
		{"out of bounds", []string{protocol.Scroll}, protocol.Message{Version: 1, Type: "scroll", DY: 501}},
		{"button on scroll", []string{protocol.Scroll}, protocol.Message{Version: 1, Type: "scroll", Button: "left"}},
	} {
		t.Run(test.name, func(t *testing.T) {
			conn, _, err := Connect(client, url, pin, "", test.caps)
			if err != nil {
				t.Fatal(err)
			}
			defer conn.Close()
			conn.SetReadDeadline(time.Now().Add(time.Second))
			if err = conn.WriteJSON(test.msg); err != nil {
				t.Fatal(err)
			}
			if err = conn.ReadJSON(&reply); err != nil || reply.Type != "error" {
				t.Fatalf("accepted invalid scroll: %v %v", reply, err)
			}
		})
	}
	if fake.calls.Load() != 1 {
		t.Fatal("invalid scroll reached backend")
	}
}
