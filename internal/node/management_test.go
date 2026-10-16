package node

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"example.org/linkpad/internal/plugins"
	"example.org/linkpad/internal/protocol"
	"github.com/gorilla/websocket"
)

func TestRevokeAndShutdownReleaseDragSynchronously(t *testing.T) {
	for _, revoke := range []bool{true, false} {
		t.Run(map[bool]string{true: "revoke", false: "shutdown"}[revoke], func(t *testing.T) {
			var accepted *websocket.Conn
			ready := make(chan struct{})
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				conn, err := (&websocket.Upgrader{}).Upgrade(w, r, nil)
				if err != nil {
					return
				}
				accepted = conn
				close(ready)
			}))
			defer server.Close()
			client, _, err := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(server.URL, "http"), nil)
			if err != nil {
				t.Fatal(err)
			}
			defer client.Close()
			<-ready
			defer accepted.Close()
			trust, err := OpenTrust(t.TempDir())
			if err != nil {
				t.Fatal(err)
			}
			if err := trust.Add("phone"); err != nil {
				t.Fatal(err)
			}
			backend := &fakeDrag{released: make(chan struct{}, 1)}
			n := &Node{Trust: trust, Plugins: plugins.Registry{protocol.Drag: backend}, sessions: map[*websocket.Conn]string{accepted: "phone"}}
			if err := n.input(accepted, protocol.Drag, dragInput("start")); err != nil {
				t.Fatal(err)
			}
			if revoke {
				if err := n.Revoke("phone"); err != nil {
					t.Fatal(err)
				}
			} else {
				n.DisconnectAll()
			}
			if n.dragOwner != nil {
				t.Fatal("held drag survived management action")
			}
			select {
			case <-backend.released:
			default:
				t.Fatal("mouse release was deferred until after shutdown")
			}
			client.SetReadDeadline(time.Now().Add(time.Second))
			if _, _, err := client.ReadMessage(); err == nil {
				t.Fatal("connection remained open")
			}
		})
	}
}
