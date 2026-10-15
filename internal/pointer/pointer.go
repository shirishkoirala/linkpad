package pointer

import "example.org/linkpad/internal/protocol"

type Backend struct{}
type ScrollBackend struct{}
type KeyBackend struct{}

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
