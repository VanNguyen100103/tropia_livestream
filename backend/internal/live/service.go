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
	}
}

// BuildPlaybackURLs - URLs cho viewer.
// MVP: dùng cùng stream_key cho publish & playback. Production nên dùng playback_key riêng (HMAC).
func (s *Service) BuildPlaybackURLs(stream *Stream) PlaybackURLs {
	key := stream.StreamKey
	return PlaybackURLs{
		HLS:  fmt.Sprintf("%s/live/%s.m3u8", s.hlsHost, key),
		FLV:  fmt.Sprintf("%s/live/%s.flv", s.hlsHost, key),
		WHEP: fmt.Sprintf("%s/rtc/v1/whep/?app=live&stream=%s", s.whipHost, key),
	}
}

// BuildPublishURLs - URLs cho host (chỉ owner mới được lấy).
func (s *Service) BuildPublishURLs(stream *Stream) PublishURLs {
	key := stream.StreamKey
	srtHost, _ := extractHost(s.rtmpHost)
	srtURL := fmt.Sprintf("srt://%s:%d?streamid=%s",
		srtHost, s.srtPort,
		url.QueryEscape(fmt.Sprintf("#!::r=live/%s,m=publish", key)),
	)
	return PublishURLs{
		RTMP: fmt.Sprintf("%s/live/%s", s.rtmpHost, key),
		WHIP: fmt.Sprintf("%s/rtc/v1/whip/?app=live&stream=%s", s.whipHost, key),
		SRT:  srtURL,
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
