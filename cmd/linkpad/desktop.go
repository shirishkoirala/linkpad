package main

import (
	"bufio"
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"time"

	"example.org/linkpad/internal/identity"
	"example.org/linkpad/internal/node"
	"example.org/linkpad/internal/pairingqr"
	"example.org/linkpad/internal/plugins"
	"example.org/linkpad/internal/pointer"
	"example.org/linkpad/internal/protocol"
)

type desktopCommand struct {
	ID      int    `json:"id"`
	Command string `json:"command"`
	Peer    string `json:"peer"`
	Address string `json:"address"`
}

type desktopPeer struct {
	ID        string `json:"id"`
	Connected bool   `json:"connected"`
}

// runDesktop is a child process protocol, never a network management endpoint.
// EOF from the owning application shuts down the listener and all sessions.
func runDesktop(state, listen, advertise string, allow bool) error {
	cert, err := identity.Load(state)
	if err != nil {
		return err
	}
	trust, err := node.OpenTrust(state)
	if err != nil {
		return err
	}
	registry := plugins.Registry{}
	inputError := ""
	if allow && pointer.Available() {
		registry[protocol.Pointer] = pointer.Backend{}
		registry[protocol.Scroll] = pointer.ScrollBackend{}
		registry[protocol.Key] = pointer.KeyBackend{}
		registry[protocol.Keyboard] = pointer.KeyboardBackend{}
		registry[protocol.Drag] = pointer.DragBackend{}
	} else if allow {
		inputError = fmt.Sprint(pointer.AvailabilityError())
	} else {
		inputError = "Desktop input is disabled"
	}
	n := &node.Node{Trust: trust, Plugins: registry}
	listener, err := net.Listen("tcp", listen)
	if err != nil {
		return fmt.Errorf("start server: %w", err)
	}
	defer listener.Close()
	defer n.DisconnectAll()
	server := &http.Server{Handler: n.Handler(), TLSConfig: n.TLS(cert), ReadHeaderTimeout: 5 * time.Second, IdleTimeout: 30 * time.Second, MaxHeaderBytes: 8192}
	serverErrors := make(chan error, 1)
	go func() { serverErrors <- server.Serve(tls.NewListener(listener, server.TLSConfig)) }()
	defer func() {
		ctx, cancel := context.WithTimeout(context.Background(), time.Second)
		defer cancel()
		_ = server.Shutdown(ctx)
	}()
	commands := make(chan desktopCommand)
	readErrors := make(chan error, 1)
	go func() {
		scanner := bufio.NewScanner(os.Stdin)
		scanner.Buffer(make([]byte, 4096), 16384)
		for scanner.Scan() {
			var command desktopCommand
			if err := json.Unmarshal(scanner.Bytes(), &command); err != nil {
				readErrors <- fmt.Errorf("invalid desktop command")
				return
			}
			commands <- command
		}
		readErrors <- scanner.Err()
	}()
	address, addressErr := pairingqr.Address(listener.Addr().String(), advertise)
	var invitation *pairingqr.Invitation
	var pairing *node.Pairing
	encoder := json.NewEncoder(os.Stdout)
	emit := func(request int, commandError string) error {
		if !pairing.Active() {
			invitation = nil
		}
		connected := n.Connected()
		peers := []desktopPeer{}
		for _, id := range trust.List() {
			peers = append(peers, desktopPeer{ID: id, Connected: connected[id] > 0})
		}
		addressError := ""
		if addressErr != nil {
			addressError = addressErr.Error()
		}
		trusted := allow && pointer.Available()
		currentInputError := inputError
		if allow && !trusted {
			currentInputError = fmt.Sprint(pointer.AvailabilityError())
		}
		return encoder.Encode(map[string]any{"type": "status", "id": request, "running": true, "listen": listener.Addr().String(), "address": address, "addressError": addressError, "fingerprint": identity.Fingerprint(cert.Certificate[0]), "inputAvailable": len(registry) > 0 && trusted, "inputPermissionGranted": trusted, "inputCount": n.InputCount(), "inputError": currentInputError, "peers": peers, "pairing": invitation, "error": commandError})
	}
	if err := emit(0, ""); err != nil {
		return err
	}
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		select {
		case err := <-readErrors:
			return err
		case err := <-serverErrors:
			if errors.Is(err, http.ErrServerClosed) {
				return nil
			}
			return err
		case <-ticker.C:
			if err := emit(0, ""); err != nil {
				return err
			}
		case command := <-commands:
			var commandErr error
			switch command.Command {
			case "status":
			case "requestInputPermission":
				pointer.RequestPermission()
			case "pair":
				chosen := address
				if command.Address != "" {
					chosen = command.Address
				}
				commandErr = pairingqr.ValidateAddress(chosen)
				if commandErr == nil {
					var next *node.Pairing
					next, commandErr = node.NewPairing(2 * time.Minute)
					if commandErr == nil {
						var invite pairingqr.Invitation
						invite, commandErr = pairingqr.New(chosen, identity.Fingerprint(cert.Certificate[0]), next.Secret(), next.ExpiresAt())
						if commandErr == nil {
							n.SetPairing(next)
							pairing = next
							invitation = &invite
						}
					}
				}
			case "cancelPairing":
				n.SetPairing(nil)
				pairing = nil
				invitation = nil
			case "revoke":
				if command.Peer == "" {
					commandErr = fmt.Errorf("choose a device")
				} else {
					commandErr = n.Revoke(command.Peer)
				}
			case "stop":
				return nil
			default:
				commandErr = fmt.Errorf("unknown desktop command")
			}
			message := ""
			if commandErr != nil {
				message = commandErr.Error()
			}
			if err := emit(command.ID, message); err != nil {
				return err
			}
		}
	}
}
