package main

import (
	"bufio"
	"encoding/json"
	"io"
	"os"
	"os/exec"
	"testing"
	"time"

	"example.org/linkpad/internal/identity"
	"example.org/linkpad/internal/node"
	"example.org/linkpad/internal/pairingqr"
)

func TestDesktopChild(t *testing.T) {
	if os.Getenv("LINKPAD_TEST_DESKTOP_CHILD") != "1" {
		return
	}
	if err := runDesktop(os.Getenv("LINKPAD_TEST_STATE"), "127.0.0.1:0", "", false); err != nil {
		os.Exit(2)
	}
	os.Exit(0)
}

type desktopTestStatus struct {
	Type        string                `json:"type"`
	ID          int                   `json:"id"`
	Running     bool                  `json:"running"`
	Address     string                `json:"address"`
	Fingerprint string                `json:"fingerprint"`
	Pairing     *pairingqr.Invitation `json:"pairing"`
	Peers       []desktopPeer         `json:"peers"`
	Error       string                `json:"error"`
}

func desktopTestStart(t *testing.T, state string) (io.WriteCloser, <-chan desktopTestStatus, <-chan error) {
	t.Helper()
	cmd := exec.Command(os.Args[0], "-test.run=^TestDesktopChild$")
	cmd.Env = append(os.Environ(), "LINKPAD_TEST_DESKTOP_CHILD=1", "LINKPAD_TEST_STATE="+state)
	in, err := cmd.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	out, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	cmd.Stderr = os.Stderr
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = cmd.Process.Kill() })
	statuses := make(chan desktopTestStatus, 32)
	done := make(chan error, 1)
	go func() {
		scanner := bufio.NewScanner(out)
		for scanner.Scan() {
			var status desktopTestStatus
			if json.Unmarshal(scanner.Bytes(), &status) == nil {
				statuses <- status
			}
		}
		done <- cmd.Wait()
	}()
	return in, statuses, done
}

func desktopTestRead(t *testing.T, statuses <-chan desktopTestStatus, id int) desktopTestStatus {
	t.Helper()
	deadline := time.After(6 * time.Second)
	for {
		select {
		case status := <-statuses:
			if status.ID == id {
				return status
			}
		case <-deadline:
			t.Fatal("desktop status timed out")
			return desktopTestStatus{}
		}
	}
}

func TestDesktopPairRevokeAndEOF(t *testing.T) {
	state := t.TempDir()
	in, statuses, done := desktopTestStart(t, state)
	status := desktopTestRead(t, statuses, 0)
	if !status.Running || status.Pairing != nil {
		t.Fatal("server must start with enrollment closed")
	}
	write := func(id int, command, peer, address string) {
		t.Helper()
		if err := json.NewEncoder(in).Encode(desktopCommand{ID: id, Command: command, Peer: peer, Address: address}); err != nil {
			t.Fatal(err)
		}
	}
	write(1, "pair", "", "http://bad")
	if s := desktopTestRead(t, statuses, 1); s.Error == "" || s.Pairing != nil {
		t.Fatal("invalid address accepted")
	}
	write(2, "pair", "", "")
	invite := desktopTestRead(t, statuses, 2).Pairing
	if invite == nil {
		t.Fatal("missing invitation")
	}
	cert, err := identity.Load(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	conn, _, err := node.Connect(cert, invite.Address, invite.Fingerprint, invite.Secret, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	write(3, "status", "", "")
	status = desktopTestRead(t, statuses, 3)
	if status.Pairing != nil || len(status.Peers) != 1 || !status.Peers[0].Connected {
		t.Fatal("pairing not consumed or phone not connected")
	}
	id := identity.Fingerprint(cert.Certificate[0])
	write(4, "revoke", id, "")
	if s := desktopTestRead(t, statuses, 4); s.Error != "" || len(s.Peers) != 0 {
		t.Fatal("revocation did not persist")
	}
	conn.SetReadDeadline(time.Now().Add(time.Second))
	if _, _, err := conn.ReadMessage(); err == nil {
		t.Fatal("revoked session stayed open")
	}
	if other, _, err := node.Connect(cert, invite.Address, invite.Fingerprint, "", nil); err == nil {
		other.Close()
		t.Fatal("revoked phone reconnected")
	}
	if err := in.Close(); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("server survived parent EOF")
	}
	trust, err := node.OpenTrust(state)
	if err != nil {
		t.Fatal(err)
	}
	if trust.Contains(id) {
		t.Fatal("revoked identity remained on disk")
	}
}

func TestDesktopCancelAndRenewPairing(t *testing.T) {
	in, statuses, done := desktopTestStart(t, t.TempDir())
	_ = desktopTestRead(t, statuses, 0)
	write := func(id int, command string) {
		t.Helper()
		if err := json.NewEncoder(in).Encode(desktopCommand{ID: id, Command: command}); err != nil {
			t.Fatal(err)
		}
	}
	write(1, "pair")
	first := desktopTestRead(t, statuses, 1).Pairing
	write(2, "pair")
	second := desktopTestRead(t, statuses, 2).Pairing
	if first == nil || second == nil || first.Secret == second.Secret {
		t.Fatal("pairing code did not rotate")
	}
	cert, err := identity.Load(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if c, _, err := node.Connect(cert, first.Address, first.Fingerprint, first.Secret, nil); err == nil {
		c.Close()
		t.Fatal("old invitation accepted")
	}
	write(3, "cancelPairing")
	if desktopTestRead(t, statuses, 3).Pairing != nil {
		t.Fatal("cancel did not clear code")
	}
	if c, _, err := node.Connect(cert, second.Address, second.Fingerprint, second.Secret, nil); err == nil {
		c.Close()
		t.Fatal("cancelled invitation accepted")
	}
	write(4, "stop")
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("stop timed out")
	}
}
