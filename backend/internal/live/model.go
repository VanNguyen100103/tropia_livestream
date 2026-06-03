package live

import (
	"time"

	"github.com/google/uuid"
)

type Status string

const (
	StatusScheduled Status = "scheduled"
	StatusLive      Status = "live"
	StatusEnded     Status = "ended"
)

type Stream struct {
	ID            uuid.UUID  `json:"id"`
	SellerID      uuid.UUID  `json:"seller_id"`
	Title         string     `json:"title"`
	Description   string     `json:"description,omitempty"`
	CoverImageURL string     `json:"cover_image_url,omitempty"`
	Category      string     `json:"category,omitempty"`
	StreamKey     string     `json:"stream_key,omitempty"`   // returned only to owner
	Status        Status     `json:"status"`
	ViewerCount   int        `json:"viewer_count"`
	LikeCount     int        `json:"like_count"`
	StartedAt     *time.Time `json:"started_at,omitempty"`
	EndedAt       *time.Time `json:"ended_at,omitempty"`
	VodHlsURL     string     `json:"vod_hls_url,omitempty"`
	VodMp4URL     string     `json:"vod_mp4_url,omitempty"`
	CreatedAt     time.Time  `json:"created_at"`
}

// PlaybackURLs - URLs cho viewer xem stream
type PlaybackURLs struct {
	HLS  string `json:"hls"`  // http://host/live/{key}.m3u8
	FLV  string `json:"flv"`  // http://host/live/{key}.flv
	WHEP string `json:"whep"` // http://host/rtc/v1/whep/?app=live&stream={key}
}

// PublishURLs - URLs cho host push stream
type PublishURLs struct {
	RTMP string `json:"rtmp"` // rtmp://host/live/{key}
	WHIP string `json:"whip"` // http://host/rtc/v1/whip/?app=live&stream={key}
	SRT  string `json:"srt"`  // srt://host:10080?streamid=#!::r=live/{key},m=publish
}
