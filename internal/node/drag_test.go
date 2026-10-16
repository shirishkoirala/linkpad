package node

import (
	"errors"
	"example.org/linkpad/internal/plugins"
	"example.org/linkpad/internal/protocol"
	"github.com/gorilla/websocket"
	"sync"
	"testing"
	"time"
)

type fakeDrag struct {
	mu       sync.Mutex
	actions  []string
	released chan struct{}
	fail     bool
}

func (f *fakeDrag) Capability() string { return protocol.Drag }
func (f *fakeDrag) Handle(m protocol.Message) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.actions = append(f.actions, m.Action)
	if m.Action == "end" && f.released != nil {
		select {
		case f.released <- struct{}{}:
		default:
		}
	}
	if f.fail && m.Action == "start" {
		return errors.New("press failed")
	}
	return nil
}
func dragInput(action string) protocol.Message {
	return protocol.Message{Version: 1, Type: "drag", Action: action}
}

func TestDragOwnershipAndDisconnectCleanup(t *testing.T) {
	backend := &fakeDrag{}
	n := &Node{Plugins: plugins.Registry{protocol.Drag: backend}}
	owner, other := &websocket.Conn{}, &websocket.Conn{}
	defer n.releaseDrag(owner)
	if err := n.input(owner, protocol.Drag, dragInput("start")); err != nil {
		t.Fatal(err)
	}
	if err := n.input(other, protocol.Drag, dragInput("start")); err == nil {
		t.Fatal("another session acquired held button")
	}
	if err := n.input(other, protocol.Drag, dragInput("end")); err != nil {
		t.Fatal(err)
	}
	n.releaseDrag(other)
	if err := n.input(other, protocol.Pointer, protocol.Message{Version: 1, Type: "pointer", DX: 30}); err != nil {
		t.Fatal("another phone should remain connected while its pointer input is paused", err)
	}
	if err := n.input(owner, protocol.Drag, dragInput("move")); err != nil {
		t.Fatal(err)
	}
	n.releaseDrag(owner)
	backend.mu.Lock()
	defer backend.mu.Unlock()
	if len(backend.actions) != 3 || backend.actions[0] != "start" || backend.actions[1] != "move" || backend.actions[2] != "end" {
		t.Fatalf("wrong lifecycle: %v", backend.actions)
	}
}

func TestDragLeaseReleasesWithoutClient(t *testing.T) {
	backend := &fakeDrag{released: make(chan struct{}, 1)}
	n := &Node{Plugins: plugins.Registry{protocol.Drag: backend}, DragTimeout: 50 * time.Millisecond}
	owner := &websocket.Conn{}
	if err := n.input(owner, protocol.Drag, dragInput("start")); err != nil {
		t.Fatal(err)
	}
	select {
	case <-backend.released:
	case <-time.After(time.Second):
		t.Fatal("lease did not release button")
	}
	if err := n.input(owner, protocol.Drag, dragInput("move")); err == nil {
		t.Fatal("expired drag continued without a new press")
	}
}

func TestDragFailureStillAttemptsRelease(t *testing.T) {
	backend := &fakeDrag{fail: true, released: make(chan struct{}, 1)}
	n := &Node{Plugins: plugins.Registry{protocol.Drag: backend}}
	if n.input(&websocket.Conn{}, protocol.Drag, dragInput("start")) == nil {
		t.Fatal("press failure ignored")
	}
	select {
	case <-backend.released:
	default:
		t.Fatal("failed press did not attempt release")
	}
}
