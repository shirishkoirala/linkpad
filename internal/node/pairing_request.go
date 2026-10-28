package node

import (
	"net/http"
	"time"
)

func (n *Node) handlePairingRequest(w http.ResponseWriter, r *http.Request) {
	if n.RequestPairing == nil {
		http.NotFound(w, r)
		return
	}
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		http.Error(w, "POST required", http.StatusMethodNotAllowed)
		return
	}
	if r.TLS == nil || len(r.TLS.PeerCertificates) != 1 {
		http.Error(w, "client identity required", http.StatusUnauthorized)
		return
	}
	cert := r.TLS.PeerCertificates[0]
	now := time.Now()
	if now.Before(cert.NotBefore) || now.After(cert.NotAfter) {
		http.Error(w, "invalid identity dates", http.StatusUnauthorized)
		return
	}
	n.pairingRequestMu.Lock()
	defer n.pairingRequestMu.Unlock()
	if now.Sub(n.lastPairingRequest) < 10*time.Second {
		w.Header().Set("Retry-After", "10")
		w.WriteHeader(http.StatusTooManyRequests)
		return
	}
	if !n.RequestPairing() {
		w.WriteHeader(http.StatusServiceUnavailable)
		return
	}
	n.lastPairingRequest = now
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(http.StatusAccepted)
}
