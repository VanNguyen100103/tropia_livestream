package auth

import (
	"crypto/sha256"
	"encoding/base64"
	"strings"
	"testing"
)

func TestVerifyPKCE(t *testing.T) {
	// Build a valid verifier/challenge pair the way a mobile client would.
	verifier := strings.Repeat("a", 64) // 64 chars, in [A-Za-z0-9-._~]
	sum := sha256.Sum256([]byte(verifier))
	challenge := base64.RawURLEncoding.EncodeToString(sum[:])

	cases := []struct {
		name      string
		verifier  string
		challenge string
		want      bool
	}{
		{"matching pair", verifier, challenge, true},
		{"wrong verifier", strings.Repeat("b", 64), challenge, false},
		{"tampered challenge", verifier, strings.Repeat("Z", len(challenge)), false},
		{"empty verifier", "", challenge, false},
		{"too short", "short", challenge, false},
		{"too long", strings.Repeat("a", 129), challenge, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := verifyPKCE(tc.verifier, tc.challenge); got != tc.want {
				t.Fatalf("verifyPKCE(%q, %q) = %v want %v", tc.verifier, tc.challenge, got, tc.want)
			}
		})
	}
}

func TestIsBase64URL(t *testing.T) {
	cases := []struct {
		s    string
		want bool
	}{
		{"abc-_DEF123", true},
		{"", true}, // empty is technically valid base64url (vacuously); start() guards length separately
		{"abc=", false},
		{"abc/def", false},
		{"abc+def", false},
		{"hello world", false},
	}
	for _, tc := range cases {
		if got := isBase64URL(tc.s); got != tc.want {
			t.Errorf("isBase64URL(%q) = %v want %v", tc.s, got, tc.want)
		}
	}
}
