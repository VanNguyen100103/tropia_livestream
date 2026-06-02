package live

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net/url"
	"strings"
)

type Service struct {
	rtmpHost string // e.g. rtmp://localhost:1935
	hlsHost  string // e.g. http://localhost:8080
	whipHost string // e.g. http://localhost:1985
	srtPort  int    // 10080
	// signer adds ?expire=&sign= to publish / playback URLs when
	// SRS_TOKEN_SECRET is set. Disabled by default — see token.go for
	// the exact placeholder format. Once infra confirms their scheme,
	// update token.go to match and set the env var on backend + SRS.
	signer *TokenSigner
}

type ServiceConfig struct {
	RTMPHost string
	HLSHost  string
	WHIPHost string
	SRTPort  int
}

// NewService - first arg accepted for API stability with main.go (was *Repository, now unused).
func NewService(_ any, cfg ServiceConfig) *Service {
	srtPort := cfg.SRTPort
	if srtPort == 0 {
		srtPort = 10080
	}
	return &Service{
		rtmpHost: strings.TrimRight(cfg.RTMPHost, "/"),
		hlsHost:  strings.TrimRight(cfg.HLSHost, "/"),
		whipHost: strings.TrimRight(cfg.WHIPHost, "/"),
		srtPort:  srtPort,
		signer:   NewTokenSigner(nil, "", 0), // disabled until WithTokenSigner is called
	}
}

// WithTokenSigner enables HMAC-signed publish/playback URLs. When
// enabled, every generated URL gets ?expire=&sign= appended so that a
// leaked URL becomes useless after the TTL. The infra-side SRS must be
// configured with the same secret + matching verification logic; see
// the format notes in token.go.
func (s *Service) WithTokenSigner(t *TokenSigner) *Service {
	if t != nil {
		s.signer = t
	}
	return s
}

// BuildPlaybackURLs - URLs cho viewer.
// HLS goes through Tropia's backend proxy (path-only — the client
// resolves it relative to its configured backend host) so the SRS
// stream_key never appears in any URL a viewer can copy from DevTools.
// Threats 1 (stream hijack via leaked key) and 2 (leeching) mitigated
// at the path level. FLV and WHEP still embed the stream_key for now;
// both are rarely used by the Tropia client (HLS is the default) and
// proxying them would require an HTTP-FLV / WebRTC pump in the backend.
//
// When a token signer is also enabled, FLV / WHEP get ?expire=&sign=
// appended so a leaked URL stops working after the TTL. The HLS path
// itself carries no stream-key material so signing it adds nothing.
func (s *Service) BuildPlaybackURLs(stream *Stream) PlaybackURLs {
	key := stream.StreamKey
	flvPath := fmt.Sprintf("/live/%s.flv", key)
	whepPath := fmt.Sprintf("/rtc/v1/whep/?app=live&stream=%s", key)
	return PlaybackURLs{
		HLS:  proxiedPlaybackPath(stream.ID),
		FLV:  s.signer.AppendTo(s.hlsHost+flvPath, flvPath, "play"),
		WHEP: s.signer.AppendTo(s.whipHost+whepPath, whepPath, "play"),
	}
}

// BuildPublishURLs - URLs cho host (chỉ owner mới được lấy).
// Token "publish" action is bound into the HMAC so an attacker with a
// playback token can't replay it against the RTMP ingest path — SRS will
// see the wrong action in the signed payload and reject.
func (s *Service) BuildPublishURLs(stream *Stream) PublishURLs {
	key := stream.StreamKey
	srtHost, _ := extractHost(s.rtmpHost)
	srtURL := fmt.Sprintf("srt://%s:%d?streamid=%s",
		srtHost, s.srtPort,
		url.QueryEscape(fmt.Sprintf("#!::r=live/%s,m=publish", key)),
	)
	rtmpPath := fmt.Sprintf("/live/%s", key)
	whipPath := fmt.Sprintf("/rtc/v1/whip/?app=live&stream=%s", key)
	return PublishURLs{
		RTMP: s.signer.AppendTo(s.rtmpHost+rtmpPath, rtmpPath, "publish"),
		WHIP: s.signer.AppendTo(s.whipHost+whipPath, whipPath, "publish"),
		SRT:  srtURL, // SRT carries auth in `streamid` already — signing TBD with infra
	}
}

func generateStreamKey() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return "tropia_" + hex.EncodeToString(b), nil
}

var _ = generateStreamKey // kept for future use

func extractHost(u string) (string, error) {
	parsed, err := url.Parse(u)
	if err != nil {
		return "", err
	}
	return parsed.Hostname(), nil
}
