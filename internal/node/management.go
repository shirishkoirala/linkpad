package node

import "time"

// These controls are exposed only over the desktop child's private stdio pipe.
func (n *Node) SetPairing(p *Pairing) {
	n.management.Lock()
	defer n.management.Unlock()
	n.Pairing = p
}

func (n *Node) Connected() map[string]int {
	n.management.Lock()
	defer n.management.Unlock()
	result := map[string]int{}
	for _, id := range n.sessions {
		result[id]++
	}
	return result
}

func (n *Node) DisconnectAll() {
	n.management.Lock()
	defer n.management.Unlock()
	for conn := range n.sessions {
		_ = conn.Close()
		n.releaseDrag(conn)
	}
}

func (n *Node) Revoke(id string) error {
	n.management.Lock()
	defer n.management.Unlock()
	if err := n.Trust.Remove(id); err != nil {
		return err
	}
	for conn, peer := range n.sessions {
		if peer == id {
			_ = conn.Close()
			n.releaseDrag(conn)
		}
	}
	return nil
}

func (p *Pairing) Active() bool {
	if p == nil {
		return false
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.secret != "" && time.Now().Before(p.expires)
}
