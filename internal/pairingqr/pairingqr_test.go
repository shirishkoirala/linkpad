package pairingqr

import (
	"bytes"
	"encoding/json"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/liyue201/goqr"
)

func fixture(t *testing.T) Invitation {
	t.Helper()
	data, err := os.ReadFile("../../protocol/testdata/pairing.json")
	if err != nil {
		t.Fatal(err)
	}
	var invitation Invitation
	if err = json.Unmarshal(data, &invitation); err != nil {
		t.Fatal(err)
	}
	return invitation
}

func verifyCode(t *testing.T, img image.Image, invitation Invitation) {
	t.Helper()
	codes, err := goqr.Recognize(img)
	if err != nil || len(codes) != 1 {
		t.Fatalf("unreadable QR: count=%d error=%v", len(codes), err)
	}
	var decoded Invitation
	if err = json.Unmarshal(codes[0].Payload, &decoded); err != nil {
		t.Fatal(err)
	}
	if decoded != invitation {
		t.Fatalf("QR payload differs from invitation")
	}
}

func TestPNGPairingRoundTrip(t *testing.T) {
	i := fixture(t)
	path := filepath.Join(t.TempDir(), "pairing.png")
	if err := i.WritePNG(path); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil || info.Mode().Perm() != 0600 {
		t.Fatalf("private PNG permissions: %v %v", info, err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	img, err := png.Decode(bytes.NewReader(data))
	if err != nil {
		t.Fatal(err)
	}
	verifyCode(t, img, i)
	if err = i.WritePNG(path); err == nil {
		t.Fatal("overwrote an existing pairing file")
	}
}

func TestTerminalPairingRoundTrip(t *testing.T) {
	i := fixture(t)
	var output bytes.Buffer
	if err := i.Render(&output); err != nil {
		t.Fatal(err)
	}
	plain := regexp.MustCompile("\x1b\\[[0-9;]*m").ReplaceAllString(output.String(), "")
	lines := strings.Split(strings.TrimSuffix(plain, "\n"), "\n")
	width := len([]rune(lines[0]))
	const scale = 8
	img := image.NewGray(image.Rect(0, 0, width*scale, len(lines)*2*scale))
	for y, line := range lines {
		for x, pixel := range []rune(line) {
			for half := 0; half < 2; half++ {
				black := pixel == '█' || (half == 0 && pixel == '▀') || (half == 1 && pixel == '▄')
				value := color.Gray{Y: 255}
				if black {
					value.Y = 0
				}
				for dy := 0; dy < scale; dy++ {
					for dx := 0; dx < scale; dx++ {
						img.SetGray(x*scale+dx, (2*y+half)*scale+dy, value)
					}
				}
			}
		}
	}
	verifyCode(t, img, i)
}

func TestInvitationValidation(t *testing.T) {
	i := fixture(t)
	if _, err := New(i.Address, i.Fingerprint, i.Secret, i.ExpiresAt); err != nil {
		t.Fatal(err)
	}
	for _, address := range []string{"http://host/ws", "wss://host/", "wss://user@host/ws", "wss://host/ws?token=x", "wss://host/ws#fragment", "wss://host:0/ws", "wss://host:65536/ws"} {
		if _, err := New(address, i.Fingerprint, i.Secret, i.ExpiresAt); err == nil {
			t.Fatalf("accepted %s", address)
		}
	}
	if _, err := New(i.Address, "bad", i.Secret, i.ExpiresAt); err == nil {
		t.Fatal("invalid fingerprint accepted")
	}
	if _, err := New(i.Address, i.Fingerprint, "bad", i.ExpiresAt); err == nil {
		t.Fatal("invalid secret accepted")
	}
	if _, err := New(i.Address, i.Fingerprint, i.Secret, time.Now().Add(-time.Second)); err == nil {
		t.Fatal("expired invitation accepted")
	}
}

func TestAddressSelection(t *testing.T) {
	for _, test := range []struct{ listen, override, want string }{
		{"192.0.2.10:4747", "", "wss://192.0.2.10:4747/ws"},
		{"[2001:db8::1]:4747", "", "wss://[2001:db8::1]:4747/ws"},
		{"0.0.0.0:4747", "wss://desktop.local:4747/ws", "wss://desktop.local:4747/ws"},
	} {
		got, err := Address(test.listen, test.override)
		if err != nil || got != test.want {
			t.Fatalf("address: %s %v", got, err)
		}
	}
}
