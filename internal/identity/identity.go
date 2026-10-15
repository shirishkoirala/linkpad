package identity

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/pem"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"time"
)

func Fingerprint(cert []byte) string { h := sha256.Sum256(cert); return hex.EncodeToString(h[:]) }

// Load creates a persistent self-signed identity. The certificate fingerprint is the device ID.
func Load(dir string) (tls.Certificate, error) {
	if err := os.MkdirAll(dir, 0700); err != nil {
		return tls.Certificate{}, err
	}
	path := filepath.Join(dir, "identity.pem")
	data, err := os.ReadFile(path)
	if err == nil {
		return tls.X509KeyPair(data, data)
	}
	if !os.IsNotExist(err) {
		return tls.Certificate{}, err
	}
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return tls.Certificate{}, err
	}
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return tls.Certificate{}, err
	}
	template := &x509.Certificate{SerialNumber: serial, Subject: pkix.Name{CommonName: "Linkpad peer"}, NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().AddDate(10, 0, 0), KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth, x509.ExtKeyUsageServerAuth}}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		return tls.Certificate{}, err
	}
	raw, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		return tls.Certificate{}, err
	}
	data = append(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: raw})...)
	// Exclusive creation prevents concurrent first starts from replacing an identity.
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return tls.Certificate{}, err
	}
	if _, err = f.Write(data); err != nil {
		f.Close()
		os.Remove(path)
		return tls.Certificate{}, err
	}
	if err = f.Close(); err != nil {
		return tls.Certificate{}, err
	}
	return tls.X509KeyPair(data, data)
}

func PinnedTLS(cert tls.Certificate, pin string) (*tls.Config, error) {
	decoded, err := hex.DecodeString(pin)
	if err != nil || len(decoded) != 32 {
		return nil, fmt.Errorf("fingerprint must be 64 hexadecimal characters")
	}
	normalized := hex.EncodeToString(decoded)
	return &tls.Config{MinVersion: tls.VersionTLS13, Certificates: []tls.Certificate{cert}, InsecureSkipVerify: true, // Replaced by exact certificate pin validation below.
		VerifyConnection: func(cs tls.ConnectionState) error {
			if len(cs.PeerCertificates) != 1 || Fingerprint(cs.PeerCertificates[0].Raw) != normalized {
				return fmt.Errorf("server fingerprint mismatch")
			}
			now := time.Now()
			c := cs.PeerCertificates[0]
			if now.Before(c.NotBefore) || now.After(c.NotAfter) {
				return fmt.Errorf("expired or not yet valid identity")
			}
			return nil
		}}, nil
}
