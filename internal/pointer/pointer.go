package pointer

import "example.org/linkpad/internal/protocol"

type Backend struct{}
type ScrollBackend struct{}
type KeyBackend struct{}
type KeyboardBackend struct{}
type DragBackend struct{}

func (DragBackend) Capability() string { return protocol.Drag }
func (DragBackend) Handle(m protocol.Message) error {
	if err := m.ValidateDrag(); err != nil {
		return err
	}
	return nativeDrag(m.Action, m.DX, m.DY)
}

func (KeyboardBackend) Capability() string { return protocol.Keyboard }
func (KeyboardBackend) Handle(m protocol.Message) error {
	if err := m.ValidateKeyboard(); err != nil {
		return err
	}
	return nativeKeyboard(m.Key, m.Text, m.Modifiers)
}

func (KeyBackend) Capability() string { return protocol.Key }
func (KeyBackend) Handle(m protocol.Message) error {
	if err := m.ValidateKey(); err != nil {
		return err
	}
	return nativeKey(m.Key)
}

func (ScrollBackend) Capability() string { return protocol.Scroll }
func (ScrollBackend) Handle(m protocol.Message) error {
	if err := m.ValidateScroll(); err != nil {
		return err
	}
	return nativeScroll(m.DX, m.DY)
}

func (Backend) Capability() string { return protocol.Pointer }
func (Backend) Handle(m protocol.Message) error {
	if err := m.ValidatePointer(); err != nil {
		return err
	}
	return native(m.DX, m.DY, m.Button)
}

// SuperKeyBackend advertises standalone Super/Command separately for old clients.
type SuperKeyBackend struct{ KeyboardBackend }

func (SuperKeyBackend) Capability() string { return protocol.SuperKey }
