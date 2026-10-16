package node

import (
	"example.org/linkpad/internal/protocol"
	"fmt"
	"github.com/gorilla/websocket"
	"time"
)

// All input and lease cleanup share the same lock as native backend execution.
func (n *Node) input(conn *websocket.Conn, capability string, m protocol.Message) error {
	n.execution.Lock()
	defer n.execution.Unlock()
	if capability != protocol.Drag {
		if n.dragOwner != nil && n.dragOwner != conn && (capability == protocol.Pointer || capability == protocol.Scroll) {
			// Keep other phones connected, but do not let them move a held pointer.
			return nil
		}
		return n.Plugins[capability].Handle(m)
	}
	if m.Action == "end" {
		if n.dragOwner != conn {
			return nil
		}
		return n.releaseDragLocked()
	}
	if m.Action == "start" {
		if n.dragOwner != nil && n.dragOwner != conn {
			return fmt.Errorf("another device is dragging")
		}
		if n.dragOwner == nil {
			// Record ownership before pressing, so a failed press still gets a release.
			n.dragOwner = conn
			if err := n.Plugins[protocol.Drag].Handle(m); err != nil {
				_ = n.releaseDragLocked()
				return err
			}
		}
	} else {
		if n.dragOwner != conn {
			return fmt.Errorf("drag expired; release and try again")
		}
		if m.Action == "move" {
			if err := n.Plugins[protocol.Drag].Handle(m); err != nil {
				_ = n.releaseDragLocked()
				return err
			}
		}
	}
	if n.dragTimer != nil {
		n.dragTimer.Stop()
	}
	n.dragGeneration++
	generation := n.dragGeneration
	timeout := n.DragTimeout
	if timeout <= 0 {
		timeout = 2 * time.Second
	}
	n.dragTimer = time.AfterFunc(timeout, func() {
		n.execution.Lock()
		defer n.execution.Unlock()
		if n.dragOwner == conn && n.dragGeneration == generation {
			_ = n.releaseDragLocked()
		}
	})
	return nil
}

func (n *Node) releaseDrag(conn *websocket.Conn) {
	n.execution.Lock()
	defer n.execution.Unlock()
	if n.dragOwner == conn {
		_ = n.releaseDragLocked()
	}
}

func (n *Node) releaseDragLocked() error {
	if n.dragTimer != nil {
		n.dragTimer.Stop()
		n.dragTimer = nil
	}
	n.dragGeneration++
	n.dragOwner = nil
	return n.Plugins[protocol.Drag].Handle(protocol.Message{Version: protocol.Version, Type: "drag", Action: "end"})
}
