package safefetch

import (
	"net"
	"testing"
)

func TestBlockedIP(t *testing.T) {
	cases := []struct {
		ip      string
		blocked bool
	}{
		// Must be blocked — internal / metadata / non-routable.
		{"127.0.0.1", true},        // loopback v4
		{"::1", true},              // loopback v6
		{"169.254.169.254", true},  // cloud metadata (link-local)
		{"10.0.0.5", true},         // RFC1918
		{"172.16.4.9", true},       // RFC1918
		{"192.168.1.1", true},      // RFC1918
		{"100.64.1.1", true},       // CGNAT
		{"fc00::1", true},          // ULA (private v6)
		{"fe80::1", true},          // link-local v6
		{"0.0.0.0", true},          // unspecified
		{"224.0.0.1", true},        // multicast
		{"::ffff:127.0.0.1", true}, // v4-mapped loopback

		// Must be allowed — public addresses (R2 / CDN / Google etc).
		{"1.1.1.1", false},
		{"8.8.8.8", false},
		{"104.16.0.1", false}, // Cloudflare range
		{"2606:4700::1", false},
	}
	for _, c := range cases {
		ip := net.ParseIP(c.ip)
		if ip == nil {
			t.Fatalf("bad test IP %q", c.ip)
		}
		if got := blockedIP(ip); got != c.blocked {
			t.Errorf("blockedIP(%s) = %v, want %v", c.ip, got, c.blocked)
		}
	}
	// A nil IP (unparseable host) must be blocked, not allowed through.
	if !blockedIP(nil) {
		t.Errorf("blockedIP(nil) = false, want true")
	}
}

func TestControlBlocksInternal(t *testing.T) {
	if err := controlBlockInternal("tcp", "169.254.169.254:80", nil); err == nil {
		t.Errorf("controlBlockInternal allowed metadata IP, want block")
	}
	if err := controlBlockInternal("tcp", "1.1.1.1:443", nil); err != nil {
		t.Errorf("controlBlockInternal blocked public IP: %v", err)
	}
}
