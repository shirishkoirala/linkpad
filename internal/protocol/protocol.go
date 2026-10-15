package protocol

import (
	"encoding/json"
	"fmt"
)

const Version = 1
const Pointer = "pointer.v1"
const Scroll = "scroll.v1"
const Key = "key.v1"
const Keyboard = "keyboard.v1"

type Message struct {
	Version      int      `json:"version"`
	Type         string   `json:"type"`
	Token        string   `json:"token,omitempty"`
	Capabilities []string `json:"capabilities,omitempty"`
	DX           int      `json:"dx,omitempty"`
	DY           int      `json:"dy,omitempty"`
	Button       string   `json:"button,omitempty"`
	Key          string   `json:"key,omitempty"`
	Text         string   `json:"text,omitempty"`
	Modifiers    []string `json:"modifiers,omitempty"`
	Error        string   `json:"error,omitempty"`
}

func Decode(raw []byte) (Message, error) {
	var m Message
	if err := json.Unmarshal(raw, &m); err != nil {
		return m, err
	}
	if m.Version != Version {
		return m, fmt.Errorf("unsupported protocol version")
	}
	switch m.Type {
	case "hello", "pair", "ready", "pointer", "scroll", "key", "keyboard", "ack", "error":
	default:
		return m, fmt.Errorf("unknown message type")
	}
	return m, nil
}
func (m Message) ValidatePointer() error {
	if m.Type != "pointer" {
		return fmt.Errorf("expected pointer")
	}
	if m.DX < -500 || m.DX > 500 || m.DY < -500 || m.DY > 500 {
		return fmt.Errorf("movement outside [-500,500]")
	}
	if m.Button != "" && m.Button != "left" && m.Button != "right" {
		return fmt.Errorf("unsupported button")
	}
	return nil
}
func (m Message) ValidateScroll() error {
	if m.Type != "scroll" {
		return fmt.Errorf("expected scroll")
	}
	if m.DX < -500 || m.DX > 500 || m.DY < -500 || m.DY > 500 {
		return fmt.Errorf("scroll outside [-500,500]")
	}
	if m.Button != "" {
		return fmt.Errorf("scroll cannot include a button")
	}
	return nil
}
func (m Message) ValidateKey() error {
	if m.Type != "key" {
		return fmt.Errorf("expected key")
	}
	switch m.Key {
	case "up", "down", "left", "right":
	default:
		return fmt.Errorf("unsupported key")
	}
	if m.DX != 0 || m.DY != 0 || m.Button != "" {
		return fmt.Errorf("key cannot include movement or a button")
	}
	return nil
}

func Has(caps []string, cap string) bool {
	for _, c := range caps {
		if c == cap {
			return true
		}
	}
	return false
}
