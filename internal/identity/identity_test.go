package identity

import (
	"os"
	"path/filepath"
	"testing"
)

func TestPersistentPrivateIdentity(t *testing.T) {
	dir := t.TempDir()
	a, e := Load(dir)
	if e != nil {
		t.Fatal(e)
	}
	b, e := Load(dir)
	if e != nil {
		t.Fatal(e)
	}
	if Fingerprint(a.Certificate[0]) != Fingerprint(b.Certificate[0]) {
		t.Fatal("identity changed")
	}
	info, e := os.Stat(filepath.Join(dir, "identity.pem"))
	if e != nil {
		t.Fatal(e)
	}
	if info.Mode().Perm() != 0600 {
		t.Fatal("key permissions")
	}
}
func TestPinValidation(t *testing.T) {
	c, e := Load(t.TempDir())
	if e != nil {
		t.Fatal(e)
	}
	for _, p := range []string{"", "zz", "abcd"} {
		if _, e = PinnedTLS(c, p); e == nil {
			t.Fatal("invalid pin accepted")
		}
	}
}
