package node

import (
	"crypto/tls"
	"crypto/x509"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestPairingDisplayRequest(t *testing.T) {
	calls := 0
	n := &Node{RequestPairing: func() bool { calls++; return true }}
	request := func(method string, valid bool) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, "https://computer/pairing/request", nil)
		if valid {
			r.TLS = &tls.ConnectionState{PeerCertificates: []*x509.Certificate{{NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour)}}}
		}
		w := httptest.NewRecorder()
		n.Handler().ServeHTTP(w, r)
		return w
	}
	if w := request("GET", true); w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("GET: %d", w.Code)
	}
	if w := request("POST", false); w.Code != http.StatusUnauthorized {
		t.Fatalf("missing identity: %d", w.Code)
	}
	if w := request("POST", true); w.Code != http.StatusAccepted || w.Body.Len() != 0 {
		t.Fatalf("request leaked data or failed: %d %s", w.Code, w.Body.String())
	}
	if calls != 1 {
		t.Fatalf("display callback calls: %d", calls)
	}
	if w := request("POST", true); w.Code != http.StatusTooManyRequests {
		t.Fatalf("not limited: %d", w.Code)
	}
	if calls != 1 {
		t.Fatal("duplicate display callback")
	}
}

func TestPairingDisplayUnavailable(t *testing.T) {
	n := &Node{}
	w := httptest.NewRecorder()
	n.Handler().ServeHTTP(w, httptest.NewRequest("POST", "https://computer/pairing/request", nil))
	if w.Code != http.StatusNotFound {
		t.Fatalf("headless pairing request enabled: %d", w.Code)
	}
}

func TestPairingDisplayRejectsExpiredAndBackpressure(t *testing.T) {
	n := &Node{RequestPairing: func() bool { return false }}
	r := httptest.NewRequest("POST", "https://computer/pairing/request", nil)
	r.TLS = &tls.ConnectionState{PeerCertificates: []*x509.Certificate{{NotBefore: time.Now().Add(-2 * time.Hour), NotAfter: time.Now().Add(-time.Hour)}}}
	w := httptest.NewRecorder()
	n.Handler().ServeHTTP(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expired identity: %d", w.Code)
	}
	r.TLS.PeerCertificates[0].NotAfter = time.Now().Add(time.Hour)
	w = httptest.NewRecorder()
	n.Handler().ServeHTTP(w, r)
	if w.Code != http.StatusServiceUnavailable {
		t.Fatalf("full request queue: %d", w.Code)
	}
}
