package protocol

import "fmt"

func (m Message) ValidateDrag() error {
	if m.Type != "drag" || m.Button != "" || m.Key != "" || m.Text != "" || len(m.Modifiers) != 0 {
		return fmt.Errorf("invalid drag message")
	}
	if m.DX < -500 || m.DX > 500 || m.DY < -500 || m.DY > 500 {
		return fmt.Errorf("invalid drag bounds")
	}
	switch m.Action {
	case "move":
	case "start", "hold", "end":
		if m.DX != 0 || m.DY != 0 {
			return fmt.Errorf("only drag movement may include deltas")
		}
	default:
		return fmt.Errorf("unsupported drag action")
	}
	return nil
}
