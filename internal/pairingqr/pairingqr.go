// Package pairingqr encodes local, short-lived enrollment invitations.
package pairingqr

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/url"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"

	qrcode "github.com/skip2/go-qrcode"
)

type Invitation struct {
	Type        string    `json:"type"`
	Version     int       `json:"version"`
	Address     string    `json:"address"`
	Fingerprint string    `json:"fingerprint"`
	Secret      string    `json:"secret"`
	ExpiresAt   time.Time `json:"expiresAt"`
}

func ValidateAddress(address string) error {
	if strings.ContainsAny(address, "?#") {
		return fmt.Errorf("advertised address must not contain a query or fragment")
	}
	u, err := url.Parse(address)
	if err != nil || u.Scheme != "wss" || u.Hostname() == "" || u.Path != "/ws" || u.RawPath != "" ||
		u.User != nil || u.RawQuery != "" || u.ForceQuery || u.Fragment != "" || u.Opaque != "" {
		return fmt.Errorf("use wss://HOST:4747/ws for the advertised address")
	}
	if u.Port() != "" {
		port, err := strconv.Atoi(u.Port())
		if err != nil || port < 1 || port > 65535 {
			return fmt.Errorf("invalid advertised port")
		}
	}
	return nil
}

func New(address, fingerprint, secret string, expiresAt time.Time) (Invitation, error) {
	if err := ValidateAddress(address); err != nil {
		return Invitation{}, err
	}
	for _, value := range []string{fingerprint, secret} {
		decoded, err := hex.DecodeString(value)
		if err != nil || len(decoded) != 32 {
			return Invitation{}, fmt.Errorf("invalid pairing credentials")
		}
	}
	if !expiresAt.After(time.Now()) {
		return Invitation{}, fmt.Errorf("pairing window expired")
	}
	return Invitation{"linkpad-pairing", 1, address, strings.ToLower(fingerprint), secret, expiresAt.UTC()}, nil
}

func (i Invitation) code() (*qrcode.QRCode, error) {
	data, err := json.Marshal(i)
	if err != nil {
		return nil, err
	}
	return qrcode.New(string(data), qrcode.Medium)
}

// Render uses two pixels per terminal row, with a white quiet zone independent
// of the terminal theme. No ANSI cursor movement or external service is used.
func (i Invitation) Render(w io.Writer) error {
	qr, err := i.code()
	if err != nil {
		return err
	}
	pixels := qr.Bitmap()
	var output strings.Builder
	for y := 0; y < len(pixels); y += 2 {
		output.WriteString("\x1b[30;47m")
		for x := range pixels[y] {
			top := pixels[y][x]
			bottom := y+1 < len(pixels) && pixels[y+1][x]
			switch {
			case top && bottom:
				output.WriteRune('█')
			case top:
				output.WriteRune('▀')
			case bottom:
				output.WriteRune('▄')
			default:
				output.WriteByte(' ')
			}
		}
		output.WriteString("\x1b[0m\n")
	}
	_, err = io.WriteString(w, output.String())
	return err
}

// WritePNG refuses to overwrite an existing file, including symlinks. Pairing
// credentials are only written to a user-private local file, never HTTP.
func (i Invitation) WritePNG(path string) error {
	qr, err := i.code()
	if err != nil {
		return err
	}
	png, err := qr.PNG(768)
	if err != nil {
		return err
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	if _, err := f.Write(png); err != nil {
		f.Close()
		os.Remove(path)
		return err
	}
	return f.Close()
}

// Address returns an explicit bound address, or a preferred non-loopback LAN
// address for wildcard listeners. -advertise can override multi-interface choice.
func Address(listen, override string) (string, error) {
	if override != "" {
		return override, ValidateAddress(override)
	}
	host, port, err := net.SplitHostPort(listen)
	if err != nil {
		return "", err
	}
	ip := net.ParseIP(host)
	if host != "" && (ip == nil || !ip.IsUnspecified()) {
		address := "wss://" + net.JoinHostPort(host, port) + "/ws"
		return address, ValidateAddress(address)
	}
	type candidate struct {
		host  string
		score int
	}
	var candidates []candidate
	interfaces, err := net.Interfaces()
	if err != nil {
		return "", err
	}
	for _, iface := range interfaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addresses, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, address := range addresses {
			ip, _, err := net.ParseCIDR(address.String())
			if err != nil || !ip.IsGlobalUnicast() || ip.IsLoopback() {
				continue
			}
			// Match the listener's IP family (0.0.0.0 cannot accept IPv6).
			if host == "0.0.0.0" && ip.To4() == nil {
				continue
			}
			score := 10
			if ip.IsPrivate() {
				score = 0
			}
			if ip.To4() == nil {
				score += 20
			}
			for _, prefix := range []string{"utun", "tun", "tap", "docker", "br-", "veth", "vmnet", "vbox", "tailscale", "wg"} {
				if strings.HasPrefix(iface.Name, prefix) {
					score += 100
					break
				}
			}
			candidates = append(candidates, candidate{ip.String(), score})
		}
	}
	if len(candidates) == 0 {
		return "", fmt.Errorf("no LAN address found; use -advertise wss://LAN-IP:PORT/ws")
	}
	sort.SliceStable(candidates, func(i, j int) bool { return candidates[i].score < candidates[j].score })
	address := "wss://" + net.JoinHostPort(candidates[0].host, port) + "/ws"
	return address, ValidateAddress(address)
}
