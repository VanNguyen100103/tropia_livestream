package vod

import (
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strconv"
)

// ProbeVideoSize runs ffprobe on a local video file and returns its DISPLAY
// width and height in pixels — i.e. after applying any rotation metadata, so
// it matches the frame dimensions FFmpeg's decoder (autorotate is on by
// default) feeds into the bake filter graph.
//
// Use this to render the overlay PNG at the clip's true aspect ratio rather
// than trusting client-reported dimensions: clients — notably Flutter web,
// where VideoPlayerController can't read a file:// preview — POST
// width=height=0, which would otherwise default the overlay to 1080×1920 and
// let scale2ref stretch it onto a clip with a different aspect.
//
// ffprobe ships with ffmpeg (already required by the bake), so no extra
// dependency. On any failure the caller should fall back to whatever the
// client reported.
func ProbeVideoSize(ctx context.Context, path string) (w, h int, err error) {
	out, err := exec.CommandContext(ctx, "ffprobe",
		"-v", "error",
		"-select_streams", "v:0",
		"-show_streams",
		"-of", "json",
		path,
	).Output()
	if err != nil {
		return 0, 0, fmt.Errorf("ffprobe: %w", err)
	}

	var probe struct {
		Streams []struct {
			Width  int `json:"width"`
			Height int `json:"height"`
			Tags   struct {
				Rotate string `json:"rotate"`
			} `json:"tags"`
			SideDataList []struct {
				Rotation int `json:"rotation"`
			} `json:"side_data_list"`
		} `json:"streams"`
	}
	if err := json.Unmarshal(out, &probe); err != nil {
		return 0, 0, fmt.Errorf("ffprobe json: %w", err)
	}
	if len(probe.Streams) == 0 {
		return 0, 0, fmt.Errorf("ffprobe: no video stream")
	}
	s := probe.Streams[0]
	w, h = s.Width, s.Height
	if w <= 0 || h <= 0 {
		return 0, 0, fmt.Errorf("ffprobe: bad dimensions %dx%d", w, h)
	}

	// Account for rotation so we return DISPLAY (post-rotate) dims. The
	// Display Matrix side-data rotation (newer ffmpeg) takes precedence over
	// the legacy `rotate` tag; either ±90/270 swaps width and height.
	rot := 0
	if s.Tags.Rotate != "" {
		rot, _ = strconv.Atoi(s.Tags.Rotate)
	}
	for _, sd := range s.SideDataList {
		if sd.Rotation != 0 {
			rot = sd.Rotation
		}
	}
	if rot < 0 {
		rot = -rot
	}
	if rot%180 == 90 {
		w, h = h, w
	}
	return w, h, nil
}
