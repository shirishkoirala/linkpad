package main

import (
	"context"
	"encoding/json"
	"github.com/shirishkoirala/linkpad/internal/identity"
	"github.com/shirishkoirala/linkpad/internal/node"
	"github.com/shirishkoirala/linkpad/internal/pairingqr"
	"flag"
	"image/png"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"github.com/liyue201/goqr"
)

func TestQRPairingServerHelper(t *testing.T) {
	if os.Getenv("LINKPAD_QR_TEST_SERVER") != "1" {
		return
	}
	for i, arg := range os.Args {
		if arg == "--" {
			os.Args = append([]string{"linkpad"}, os.Args[i+1:]...)
			break
		}
	}
	flag.CommandLine = flag.NewFlagSet("linkpad", flag.ExitOnError)
	if err := run(); err != nil {
		os.Exit(1)
	}
}

// Decode the PNG emitted by the real CLI, then use only its contents for a
// mutually authenticated enrollment and verify that the code is single-use.
func TestQRPairingCLIEnrollment(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	address := listener.Addr().String()
	listener.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	imagePath := filepath.Join(t.TempDir(), "pairing.png")
	process := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestQRPairingServerHelper$", "--",
		"-state", t.TempDir(), "-listen", address, "-pair", "-pair-qr", imagePath)
	process.Env = append(os.Environ(), "LINKPAD_QR_TEST_SERVER=1")
	process.Stdout, process.Stderr = io.Discard, io.Discard
	if err = process.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { process.Process.Kill(); process.Wait() }()
	var invitation pairingqr.Invitation
	for {
		file, openErr := os.Open(imagePath)
		if openErr == nil {
			img, decodeErr := png.Decode(file)
			file.Close()
			if decodeErr == nil {
				codes, scanErr := goqr.Recognize(img)
				if scanErr != nil || len(codes) != 1 {
					t.Fatal("CLI emitted an unreadable QR")
				}
				if err = json.Unmarshal(codes[0].Payload, &invitation); err != nil {
					t.Fatal(err)
				}
				break
			}
		}
		select {
		case <-ctx.Done():
			t.Fatal("CLI did not emit its QR PNG")
		case <-time.After(20 * time.Millisecond):
		}
	}
	if invitation.Address != "wss://"+address+"/ws" {
		t.Fatalf("QR endpoint mismatch: got %q, want %q", invitation.Address, "wss://"+address+"/ws")
	}
	client, err := identity.Load(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	conn, _, err := node.Connect(client, invitation.Address, invitation.Fingerprint, invitation.Secret, nil)
	if err != nil {
		t.Fatalf("QR enrollment failed: %v", err)
	}
	conn.Close()
	other, err := identity.Load(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if reused, _, reuseErr := node.Connect(other, invitation.Address, invitation.Fingerprint, invitation.Secret, nil); reuseErr == nil {
		reused.Close()
		t.Fatal("QR pairing secret was reusable")
	}
	conn, _, err = node.Connect(client, invitation.Address, invitation.Fingerprint, "", nil)
	if err != nil {
		t.Fatalf("enrolled device could not reconnect: %v", err)
	}
	conn.Close()
}
