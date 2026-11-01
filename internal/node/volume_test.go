package node

import (
	"github.com/shirishkoirala/linkpad/internal/identity"
	"github.com/shirishkoirala/linkpad/internal/plugins"
	"github.com/shirishkoirala/linkpad/internal/protocol"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

type fakeVolume struct{ actions chan string }

func (f *fakeVolume) Capability() string { return protocol.Volume }
func (f *fakeVolume) Handle(m protocol.Message) error {
	if err := m.ValidateVolume(); err != nil {
		return err
	}
	f.actions <- m.Action
	return nil
}
func TestVolumeNegotiationAndDispatch(t *testing.T) {
	for _, test := range []struct {
		name      string
		negotiate bool
		action    string
		reply     string
	}{
		{"up", true, "up", "ack"}, {"down", true, "down", "ack"}, {"mute", true, "mute", "ack"},
		{"unnegotiated", false, "up", "error"}, {"invalid action", true, "set", "error"},
	} {
		t.Run(test.name, func(t *testing.T) {
			serverCert, client := cert(t), cert(t)
			trust, err := OpenTrust(t.TempDir())
			if err != nil {
				t.Fatal(err)
			}
			pairing, err := NewPairing(time.Minute)
			if err != nil {
				t.Fatal(err)
			}
			backend := &fakeVolume{actions: make(chan string, 1)}
			n := &Node{Trust: trust, Pairing: pairing, Plugins: plugins.Registry{protocol.Volume: backend}}
			server := httptest.NewUnstartedServer(n.Handler())
			server.TLS = n.TLS(serverCert)
			server.StartTLS()
			defer server.Close()
			defer n.DisconnectAll()
			var caps []string
			if test.negotiate {
				caps = []string{protocol.Volume}
			}
			conn, negotiated, err := Connect(client, "wss"+strings.TrimPrefix(server.URL, "https")+"/ws", identity.Fingerprint(serverCert.Certificate[0]), pairing.Secret(), caps)
			if err != nil {
				t.Fatal(err)
			}
			defer conn.Close()
			if protocol.Has(negotiated, protocol.Volume) != test.negotiate {
				t.Fatalf("wrong negotiation: %v", negotiated)
			}
			conn.SetReadDeadline(time.Now().Add(time.Second))
			if err := conn.WriteJSON(protocol.Message{Version: 1, Type: "volume", Action: test.action}); err != nil {
				t.Fatal(err)
			}
			var reply protocol.Message
			if err := conn.ReadJSON(&reply); err != nil || reply.Type != test.reply {
				t.Fatalf("response %+v, %v", reply, err)
			}
			if test.reply == "ack" {
				select {
				case action := <-backend.actions:
					if action != test.action {
						t.Fatal(action)
					}
				default:
					t.Fatal("volume was not dispatched")
				}
			} else {
				select {
				case <-backend.actions:
					t.Fatal("invalid input dispatched")
				default:
				}
			}
		})
	}
}
