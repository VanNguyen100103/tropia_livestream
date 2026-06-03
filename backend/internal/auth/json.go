package auth

import (
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
)

func jsonUnmarshal(s string, v any) error {
	return json.Unmarshal([]byte(s), v)
}

func jsonMarshal(v any) ([]byte, error) {
	return json.Marshal(v)
}

func base64URLEncodeNoPad(b []byte) string {
	return base64.RawURLEncoding.EncodeToString(b)
}

func constantTimeStringEq(a, b string) bool {
	if len(a) != len(b) {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(a), []byte(b)) == 1
}
