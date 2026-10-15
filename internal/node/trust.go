package node

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
)

type Trust struct {
	mu    sync.Mutex
	path  string
	peers map[string]bool
}

func OpenTrust(dir string) (*Trust, error) {
	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, err
	}
	t := &Trust{path: filepath.Join(dir, "peers.json"), peers: map[string]bool{}}
	b, err := os.ReadFile(t.path)
	if os.IsNotExist(err) {
		return t, nil
	}
	if err != nil {
		return nil, err
	}
	err = json.Unmarshal(b, &t.peers)
	if t.peers == nil {
		t.peers = map[string]bool{}
	}
	return t, err
}
func (t *Trust) Contains(id string) bool { t.mu.Lock(); defer t.mu.Unlock(); return t.peers[id] }
func (t *Trust) Add(id string) error {
	t.mu.Lock()
	defer t.mu.Unlock()
	next := map[string]bool{}
	for k, v := range t.peers {
		next[k] = v
	}
	next[id] = true
	b, err := json.MarshalIndent(next, "", "  ")
	if err != nil {
		return err
	}
	if err = os.WriteFile(t.path+".tmp", b, 0600); err != nil {
		return err
	}
	if err = os.Rename(t.path+".tmp", t.path); err != nil {
		return err
	}
	t.peers = next
	return nil
}
