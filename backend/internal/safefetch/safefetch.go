// Package safefetch provides an HTTP client hardened against SSRF for
// fetching user-controlled or user-influenced URLs — e.g. a seller's
// product image URL (stored verbatim from quickCreate) that the overlay
// worker downloads, or an uploaded clip's media URL.
//
// The guard rejects any connection whose RESOLVED destination IP is
// loopback, private, link-local (incl. the 169.254.169.254 cloud-metadata
// endpoint), CGNAT, unspecified, or multicast. The check runs in the
// dialer's Control hook — i.e. on the actual IP about to be connected,
// AFTER DNS resolution — so a hostname that resolves to an internal
// address (DNS-rebinding) is blocked at connect time, not just at parse
// time. Redirects re-dial through the same hook, so a 302 to an internal
// host is blocked too.
package safefetch

import (
	"context"
	"errors"
	"net"
	"net/http"
	"syscall"
	"time"
)

// ErrBlockedAddress is returned (wrapped) when a fetch targets a
// non-public address. Callers that fetch best-effort (image overlays)
// usually just treat any error as "skip".
var ErrBlockedAddress = errors.New("safefetch: destination address is not allowed")

// blockedIP reports whether ip is one an outbound fetch of an untrusted
// URL must never reach.
func blockedIP(ip net.IP) bool {
	if ip == nil {
		return true
	}
	if ip4 := ip.To4(); ip4 != nil {
		// Carrier-grade NAT 100.64.0.0/10 — used for internal infra.
		if ip4[0] == 100 && ip4[1] >= 64 && ip4[1] <= 127 {
			return true
		}
		ip = ip4
	}
	return ip.IsLoopback() ||
		ip.IsPrivate() || // RFC1918 + ULA (fc00::/7)
		ip.IsLinkLocalUnicast() || // 169.254.0.0/16 (cloud metadata) + fe80::/10
		ip.IsLinkLocalMulticast() ||
		ip.IsInterfaceLocalMulticast() ||
		ip.IsMulticast() ||
		ip.IsUnspecified()
}

// controlBlockInternal is the net.Dialer.Control hook: address is the
// already-resolved "ip:port", so this is the DNS-rebinding-safe checkpoint.
func controlBlockInternal(_, address string, _ syscall.RawConn) error {
	host, _, err := net.SplitHostPort(address)
	if err != nil {
		return err
	}
	if blockedIP(net.ParseIP(host)) {
		return ErrBlockedAddress
	}
	return nil
}

// Client returns an *http.Client that refuses to connect to internal /
// metadata addresses. timeout bounds the whole request (incl. body read
// up to the client's own deadline). Reuse the returned client; it is
// safe for concurrent use.
func Client(timeout time.Duration) *http.Client {
	dialer := &net.Dialer{
		Timeout:   10 * time.Second,
		KeepAlive: 30 * time.Second,
		Control:   controlBlockInternal,
	}
	return &http.Client{
		Timeout: timeout,
		Transport: &http.Transport{
			DialContext:           dialer.DialContext,
			ForceAttemptHTTP2:     true,
			MaxIdleConns:          10,
			IdleConnTimeout:       30 * time.Second,
			TLSHandshakeTimeout:   10 * time.Second,
			ResponseHeaderTimeout: 15 * time.Second,
			ExpectContinueTimeout: 1 * time.Second,
		},
	}
}

// Default is a ready-made guarded client (30s budget) for the common
// case of pulling an image or a media file.
var Default = Client(30 * time.Second)

// Get is a convenience GET through the guarded Default client that also
// carries the caller's context (so a worker shutdown cancels in flight).
func Get(ctx context.Context, url string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	return Default.Do(req)
}
