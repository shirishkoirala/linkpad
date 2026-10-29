package protocol

import "fmt"

func (m Message) ValidateVolume() error {
	if m.Type != "volume" || m.DX != 0 || m.DY != 0 || m.Button != "" || m.Key != "" || m.Text != "" || len(m.Modifiers) != 0 {
		return fmt.Errorf("invalid volume message")
	}
	switch m.Action {
	case "up", "down", "mute":
		return nil
	}
	return fmt.Errorf("unsupported volume action")
}
