package plugins

import "github.com/shirishkoirala/linkpad/internal/protocol"

// Plugin is an in-process capability boundary. No downloaded code is executed.
type Plugin interface {
	Capability() string
	Handle(protocol.Message) error
}
type Registry map[string]Plugin

func (r Registry) Negotiate(requested []string) []string {
	result := []string{}
	seen := map[string]bool{}
	for _, c := range requested {
		if _, ok := r[c]; ok && !seen[c] {
			result = append(result, c)
			seen[c] = true
		}
	}
	return result
}
