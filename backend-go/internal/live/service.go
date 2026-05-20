package live

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net/url"
	"strings"

	"github.com/google/uuid"
)

type Service struct {
	repo *Repository

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

func NewService(repo *Repository, cfg ServiceConfig) *Service {
	srtPort := cfg.SRTPort
	if srtPort == 0 {
		srtPort = 10080
	}
	return &Service{
		repo:     repo,
		rtmpHost: strings.TrimRight(cfg.RTMPHost, "/"),
		hlsHost:  strings.TrimRight(cfg.HLSHost, "/"),
		whipHost: strings.TrimRight(cfg.WHIPHost, "/"),
		srtPort:  srtPort,
	}
}

func (s *Service) CreateStream(ctx context.Context, sellerID uuid.UUID, title, description, coverURL, category string) (*Stream, error) {
	key, err := generateStreamKey()
	if err != nil {
		return nil, fmt.Errorf("gen stream key: %w", err)
	}
	return s.repo.Create(ctx, sellerID, title, description, coverURL, category, key)
}

func (s *Service) GetStream(ctx context.Context, id uuid.UUID) (*Stream, error) {
	return s.repo.GetByID(ctx, id)
}

func (s *Service) ListLive(ctx context.Context, limit int) ([]Stream, error) {
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	return s.repo.ListLive(ctx, limit)
}

// BuildPlaybackURLs - URLs cho viewer (không cần stream_key bí mật, chỉ cần stream ID public)
// SRS dùng stream_key trong path → trong MVP ta dùng cùng stream_key cho cả publish & playback.
// Production: dùng playback_key riêng (HMAC) để không lộ stream_key.
func (s *Service) BuildPlaybackURLs(stream *Stream) PlaybackURLs {
	key := stream.StreamKey
	return PlaybackURLs{
		HLS:  fmt.Sprintf("%s/live/%s.m3u8", s.hlsHost, key),
		FLV:  fmt.Sprintf("%s/live/%s.flv", s.hlsHost, key),
		WHEP: fmt.Sprintf("%s/rtc/v1/whep/?app=live&stream=%s", s.whipHost, key),
	}
}

// BuildPublishURLs - URLs cho host (chỉ owner mới được lấy)
func (s *Service) BuildPublishURLs(stream *Stream) PublishURLs {
	key := stream.StreamKey

	// SRT format: srt://host:port?streamid=#!::r=live/{key},m=publish
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

// extractHost - lấy hostname từ URL như "rtmp://localhost:1935" → "localhost"
func extractHost(u string) (string, error) {
	parsed, err := url.Parse(u)
	if err != nil {
		return "", err
	}
	return parsed.Hostname(), nil
}
