// Package discovery advertises public server identity, never pairing credentials.
package discovery

import (
	"context"
	"fmt"
	"net"
	"sort"
	"strings"
	"sync"
	"time"

	zeroconf "github.com/libp2p/zeroconf/v2"
)

const Service = "_linkpad._tcp."

type serviceRecord struct {
	Instance, Service, HostName string
	Port                        int
	IPs                         []net.IP
	TXT                         []string
}
type registration interface{ Shutdown() error }
type shutdownFunc func() error

func (f shutdownFunc) Shutdown() error { return f() }

func serviceFor(addr net.Addr, fp string, ips []net.IP) (*serviceRecord, error) {
	tcp, ok := addr.(*net.TCPAddr)
	if !ok || tcp.Port < 1 || tcp.Port > 65535 {
		return nil, fmt.Errorf("invalid discovery listener")
	}
	if len(fp) != 64 || strings.Trim(fp, "0123456789abcdef") != "" {
		return nil, fmt.Errorf("invalid discovery fingerprint")
	}
	id := "linkpad-" + fp[:20]
	return &serviceRecord{Instance: id, Service: Service, HostName: id, Port: tcp.Port, IPs: ips, TXT: []string{"v=1", "fp=" + fp}}, nil
}

// Start observes interface changes and withdraws stale registrations. Discovery
// errors never stop the TLS listener. The returned stop waits for withdrawal.
func Start(ctx context.Context, listener net.Listener, fingerprint string, report func(error)) (func(), error) {
	return start(ctx, listener, fingerprint, report, 5*time.Second, interfaceAddresses, func(s *serviceRecord) (registration, error) {
		ips := make([]string, len(s.IPs))
		for i, ip := range s.IPs {
			ips[i] = ip.String()
		}
		server, err := zeroconf.RegisterProxy(s.Instance, s.Service, "local.", s.Port, s.HostName, ips, s.TXT, nil, zeroconf.TTL(30))
		if err != nil {
			return nil, err
		}
		return shutdownFunc(func() error { server.Shutdown(); return nil }), nil
	})
}

func start(parent context.Context, listener net.Listener, fp string, report func(error), interval time.Duration, addresses func(net.Addr) ([]net.IP, error), announce func(*serviceRecord) (registration, error)) (func(), error) {
	if listener == nil {
		return nil, fmt.Errorf("missing discovery listener")
	}
	if _, err := serviceFor(listener.Addr(), fp, nil); err != nil {
		return nil, err
	}
	if listener.Addr().(*net.TCPAddr).IP.IsLoopback() {
		return func() {}, nil
	}
	ctx, cancel := context.WithCancel(parent)
	done := make(chan struct{})
	var once sync.Once
	go func() {
		defer close(done)
		var active registration
		var previous string
		defer func() {
			if active != nil {
				_ = active.Shutdown()
			}
		}()
		update := func() {
			ips, err := addresses(listener.Addr())
			if err != nil {
				if report != nil {
					report(err)
				}
				return
			}
			names := make([]string, len(ips))
			for i, ip := range ips {
				names[i] = ip.String()
			}
			sort.Strings(names)
			key := strings.Join(names, ",")
			if active != nil && key == previous {
				return
			}
			if active != nil {
				_ = active.Shutdown()
				active = nil
			}
			previous = ""
			if len(ips) == 0 {
				return
			}
			record, _ := serviceFor(listener.Addr(), fp, ips)
			active, err = announce(record)
			if err != nil {
				active = nil
				if report != nil {
					report(fmt.Errorf("local discovery: %w", err))
				}
				return
			}
			previous = key
		}
		update()
		ticker := time.NewTicker(interval)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				update()
			}
		}
	}()
	return func() { once.Do(cancel); <-done }, nil
}

func interfaceAddresses(addr net.Addr) ([]net.IP, error) {
	bound := addr.(*net.TCPAddr).IP
	interfaces, err := net.Interfaces()
	if err != nil {
		return nil, err
	}
	var ips []net.IP
	seen := map[string]bool{}
	for _, iface := range interfaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 || iface.Flags&net.FlagMulticast == 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, a := range addrs {
			ip, _, err := net.ParseCIDR(a.String())
			if err != nil || ip.IsLoopback() || ip.IsUnspecified() || ip.IsMulticast() {
				continue
			}
			if bound.To4() != nil && ip.To4() == nil {
				continue
			}
			if bound != nil && !bound.IsUnspecified() && !bound.Equal(ip) {
				continue
			}
			if !seen[ip.String()] {
				seen[ip.String()] = true
				ips = append(ips, ip)
			}
		}
	}
	return ips, nil
}
