package main

import (
	"context"
	"example.org/linkpad/internal/discovery"
	"example.org/linkpad/internal/identity"
	"example.org/linkpad/internal/node"
	"example.org/linkpad/internal/pairingqr"
	"example.org/linkpad/internal/plugins"
	"example.org/linkpad/internal/pointer"
	"example.org/linkpad/internal/protocol"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"
)

func main() {
	if err := run(); err != nil {
		log.Fatal(err)
	}
}
func run() error {
	home, err := os.UserConfigDir()
	if err != nil {
		return err
	}
	state := flag.String("state", filepath.Join(home, "linkpad"), "private identity/trust directory")
	listen := flag.String("listen", "127.0.0.1:4747", "listen address; use LAN IP for mobile")
	pair := flag.Bool("pair", false, "open single-use 2-minute pairing window")
	advertise := flag.String("advertise", "", "address encoded in pairing QR (wss://LAN-IP:4747/ws); inferred from listen address by default")
	pairPNG := flag.String("pair-qr", "", "optional private pairing QR PNG path (must not already exist)")
	allow := flag.Bool("allow-pointer", false, "allow trusted peers to control pointer")
	connect := flag.String("connect", "", "explicit peer wss://HOST:4747/ws")
	pin := flag.String("pin", "", "server SHA-256 certificate fingerprint")
	dx := flag.Int("dx", 0, "relative pointer X movement")
	dy := flag.Int("dy", 0, "relative pointer Y movement")
	click := flag.String("click", "", "left or right click")
	key := flag.String("key", "", "arrow key: up, down, left or right")
	desktop := flag.Bool("desktop", false, "private JSON desktop control over stdin/stdout")
	flag.Parse()
	if *desktop {
		return runDesktop(*state, *listen, *advertise, *allow)
	}
	if (*pairPNG != "" || *advertise != "") && !*pair {
		return fmt.Errorf("-pair-qr and -advertise require -pair")
	}
	cert, err := identity.Load(*state)
	if err != nil {
		return err
	}
	fmt.Println("Device fingerprint:", identity.Fingerprint(cert.Certificate[0]))
	if *connect != "" {
		token := os.Getenv("LINKPAD_PAIR_TOKEN")
		conn, caps, err := node.Connect(cert, *connect, *pin, token, []string{protocol.Pointer, protocol.Key})
		if err != nil {
			return err
		}
		defer conn.Close()
		fmt.Println("Negotiated capabilities:", caps)
		if *dx != 0 || *dy != 0 || *click != "" {
			if !protocol.Has(caps, protocol.Pointer) {
				return fmt.Errorf("peer does not offer pointer control")
			}
			m := protocol.Message{Version: 1, Type: "pointer", DX: *dx, DY: *dy, Button: *click}
			if err = m.ValidatePointer(); err != nil {
				return err
			}
			conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
			if err = conn.WriteJSON(m); err != nil {
				return err
			}
			conn.SetReadDeadline(time.Now().Add(5 * time.Second))
			_, b, err := conn.ReadMessage()
			if err != nil {
				return err
			}
			reply, err := protocol.Decode(b)
			if err != nil {
				return err
			}
			if reply.Type != "ack" {
				return fmt.Errorf("pointer rejected: %s", reply.Error)
			}
		}
		if *key != "" {
			if !protocol.Has(caps, protocol.Key) {
				return fmt.Errorf("peer does not offer key control")
			}
			m := protocol.Message{Version: 1, Type: "key", Key: *key}
			if err = m.ValidateKey(); err != nil {
				return err
			}
			conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
			if err = conn.WriteJSON(m); err != nil {
				return err
			}
			conn.SetReadDeadline(time.Now().Add(5 * time.Second))
			_, b, err := conn.ReadMessage()
			if err != nil {
				return err
			}
			reply, err := protocol.Decode(b)
			if err != nil {
				return err
			}
			if reply.Type != "ack" {
				return fmt.Errorf("key rejected: %s", reply.Error)
			}
		}
		return nil
	}
	trust, err := node.OpenTrust(*state)
	if err != nil {
		return err
	}
	registry := plugins.Registry{}
	if *allow {
		if pointer.Available() {
			registry[protocol.Pointer] = pointer.Backend{}
			registry[protocol.Scroll] = pointer.ScrollBackend{}
			registry[protocol.Key] = pointer.KeyBackend{}
			registry[protocol.Keyboard] = pointer.KeyboardBackend{}
			registry[protocol.SuperKey] = pointer.SuperKeyBackend{}
			registry[protocol.Volume] = pointer.VolumeBackend{}
			registry[protocol.Drag] = pointer.DragBackend{}
		} else {
			log.Printf("Desktop input unavailable: %v", pointer.AvailabilityError())
		}
	}
	n := &node.Node{Trust: trust, Plugins: registry}
	defer n.DisconnectAll()
	listener, err := net.Listen("tcp", *listen)
	if err != nil {
		return err
	}
	defer listener.Close()
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	stopDiscovery, discoveryErr := discovery.Start(ctx, listener, identity.Fingerprint(cert.Certificate[0]), func(err error) { log.Printf("Discovery: %v", err) })
	if discoveryErr != nil {
		log.Printf("Discovery unavailable: %v", discoveryErr)
	} else {
		defer stopDiscovery()
	}
	if *pair {
		n.Pairing, err = node.NewPairing(2 * time.Minute)
		if err != nil {
			return err
		}
		fmt.Println("Single-use pairing secret (expires in 2 minutes):", n.Pairing.Secret())
		address, qrErr := pairingqr.Address(listener.Addr().String(), *advertise)
		if qrErr != nil {
			return fmt.Errorf("pairing QR address: %w", qrErr)
		}
		invitation, qrErr := pairingqr.New(address, identity.Fingerprint(cert.Certificate[0]), n.Pairing.Secret(), n.Pairing.ExpiresAt())
		if qrErr != nil {
			return qrErr
		}
		fmt.Println("On your phone, tap Scan QR and scan this code to pair with", address)
		fmt.Println("The QR contains the one-use pairing secret and expires in two minutes.")
		if qrErr = invitation.Render(os.Stdout); qrErr != nil {
			return qrErr
		}
		if *pairPNG != "" {
			if qrErr = invitation.WritePNG(*pairPNG); qrErr != nil {
				return fmt.Errorf("save pairing QR: %w", qrErr)
			}
			fmt.Println("Pairing QR image:", *pairPNG)
		}
	}
	server := &http.Server{Addr: *listen, Handler: n.Handler(), TLSConfig: n.TLS(cert), ReadHeaderTimeout: 5 * time.Second, IdleTimeout: 30 * time.Second, MaxHeaderBytes: 8192}
	fmt.Println("Listening on", listener.Addr())
	go func() {
		<-ctx.Done()
		shutdown, done := context.WithTimeout(context.Background(), time.Second)
		defer done()
		_ = server.Shutdown(shutdown)
	}()
	err = server.ServeTLS(listener, "", "")
	if err == http.ErrServerClosed {
		return nil
	}
	return err
}
