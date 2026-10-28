package discovery

import (
	"context"
	"net"
	"strings"
	"sync"
	"testing"
	"time"
)

type testListener struct {
	net.Listener
	addr net.Addr
}

func (l testListener) Addr() net.Addr { return l.addr }

type fakeRegistration struct {
	once   sync.Once
	closed chan struct{}
}

func (r *fakeRegistration) Shutdown() error { r.once.Do(func() { close(r.closed) }); return nil }

func TestServiceIdentityAndPort(t *testing.T) {
	fp := strings.Repeat("a", 64)
	service, err := serviceFor(&net.TCPAddr{Port: 4748}, fp, []net.IP{net.ParseIP("192.168.1.203")})
	if err != nil {
		t.Fatal(err)
	}
	if service.HostName != service.Instance {
		t.Fatalf("proxy hostname must be unqualified: %s", service.HostName)
	}
	if service.Service != "_linkpad._tcp." || service.Port != 4748 || len(service.TXT) != 2 || service.TXT[0] != "v=1" || service.TXT[1] != "fp="+fp {
		t.Fatalf("unexpected advertisement: %#v", service)
	}
	if _, err = serviceFor(&net.TCPAddr{Port: 4747}, "bad", service.IPs); err == nil {
		t.Fatal("accepted invalid fingerprint")
	}
}

func TestRefreshWithdrawsOldRegistrationAndStops(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var mu sync.Mutex
	ip := "192.168.1.202"
	registrations := make(chan *fakeRegistration, 4)
	source := func(net.Addr) ([]net.IP, error) { mu.Lock(); defer mu.Unlock(); return []net.IP{net.ParseIP(ip)}, nil }
	announce := func(*serviceRecord) (registration, error) {
		r := &fakeRegistration{closed: make(chan struct{})}
		registrations <- r
		return r, nil
	}
	stop, err := start(ctx, testListener{addr: &net.TCPAddr{Port: 4747}}, strings.Repeat("b", 64), nil, 5*time.Millisecond, source, announce)
	if err != nil {
		t.Fatal(err)
	}
	defer stop()
	var first *fakeRegistration
	select {
	case first = <-registrations:
	case <-time.After(time.Second):
		t.Fatal("not advertised")
	}
	mu.Lock()
	ip = "192.168.1.203"
	mu.Unlock()
	var second *fakeRegistration
	select {
	case second = <-registrations:
	case <-time.After(time.Second):
		t.Fatal("address not refreshed")
	}
	select {
	case <-first.closed:
	default:
		t.Fatal("old address not withdrawn")
	}
	stop()
	stop()
	select {
	case <-second.closed:
	case <-time.After(time.Second):
		t.Fatal("registration leaked")
	}
}

func TestRegistrationFailureRetries(t *testing.T) {
	attempts := make(chan struct{}, 4)
	count := 0
	announce := func(*serviceRecord) (registration, error) {
		count++
		attempts <- struct{}{}
		if count == 1 {
			return nil, context.DeadlineExceeded
		}
		return &fakeRegistration{closed: make(chan struct{})}, nil
	}
	stop, err := start(context.Background(), testListener{addr: &net.TCPAddr{Port: 4747}}, strings.Repeat("c", 64), func(error) {}, 5*time.Millisecond, func(net.Addr) ([]net.IP, error) { return []net.IP{net.ParseIP("192.168.1.203")}, nil }, announce)
	if err != nil {
		t.Fatal(err)
	}
	defer stop()
	for i := 0; i < 2; i++ {
		select {
		case <-attempts:
		case <-time.After(time.Second):
			t.Fatal("registration not retried")
		}
	}
}

func TestLoopbackDoesNotAdvertise(t *testing.T) {
	stop, err := Start(context.Background(), testListener{addr: &net.TCPAddr{IP: net.ParseIP("127.0.0.1"), Port: 4747}}, strings.Repeat("a", 64), nil)
	if err != nil {
		t.Fatal(err)
	}
	stop()
}
