package live

import (
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/tropia/backend/internal/httpx"
)

// HLS proxy — threat 1+2 mitigation
//
// Vanilla SRS routes streams by URL path, so an HLS playlist URL embeds
// the stream_key directly (e.g. /live/<stream_key>.m3u8). Any viewer
// looking in DevTools Network can copy that key and try to push to it
// over RTMP, hijacking the stream. The token signer in token.go closes
// that gap when infra confirms the format; until then, the proxy here
// removes the leak at the source by fronting SRS through Tropia.
//
// Viewer-visible URLs become:
//
//   GET /api/live/streams/<session_id>/hls/playlist.m3u8
//   GET /api/live/streams/<session_id>/hls/s/<seq>.ts
//
// Neither path contains the stream_key. Backend looks up the session,
// rewrites SRS's manifest to point at the opaque /s/<seq>.ts paths, and
// streams .ts segments through from SRS on demand.
//
// Tradeoffs:
//   - Bandwidth cost: every viewer's .ts segment now flows through
//     Tropia in addition to SRS. Fine at MVP scale; consider a managed
//     CDN at >1k concurrent viewers.
//   - Latency: ~50-100ms extra per segment (one extra hop). HLS already
//     has ~6-10s glass-to-glass latency, so this is in the noise.
//   - No caching: each request fetches fresh from SRS. Acceptable for
//     a single-bitrate live stream; revisit if a viewer fleet starts
//     hammering SRS.

// segmentRefRegex matches an HLS .ts line: stream_key + dash + sequence
// number + .ts, optionally followed by SRS's hls_ctx query. We use the
// session's stream_key as a literal prefix so unrelated lines (URI=...
// in EXT-X-MAP, comments, etc.) stay untouched. The capture group is
// the sequence number we'll surface in the rewritten URL.
func segmentRefRegexFor(streamKey string) *regexp.Regexp {
	pattern := regexp.QuoteMeta(streamKey) + `-(\d+)\.ts(\?[^"\s]*)?`
	return regexp.MustCompile(pattern)
}

// variantRefRegex matches a self-reference to the stream's variant
// playlist that SRS embeds in its master m3u8: `live_<key>.m3u8` or
// `/live/<key>.m3u8` (with optional ?hls_ctx). SRS returns a master
// playlist with this variant pointer whenever the stream hasn't
// actually started yet (publisher hasn't pushed RTMP), AND sometimes
// after the stream IS publishing in a few SRS modes. Without
// rewriting, hls.js follows the variant URL out to the bare SRS path
// — which our backend doesn't serve, surfacing as 404.
//
// Replacement target is the path-relative `playlist.m3u8` so hls.js
// resolves it against the current manifest URL and ends up calling
// our proxy again. If SRS has flipped to publishing by then, the
// next fetch returns the real variant content (with .ts refs) and
// the segmentRefRegex below rewrites those.
func variantRefRegexFor(streamKey string) *regexp.Regexp {
	pattern := `(?:/?live/)?` + regexp.QuoteMeta(streamKey) + `\.m3u8(\?[^"\s]*)?`
	return regexp.MustCompile(pattern)
}

// proxyHTTPClient is a long-lived HTTP/1.1 keep-alive client used for
// all upstream fetches. The default transport pools connections to the
// SRS host so we're not paying TCP setup on every segment.
var proxyHTTPClient = &http.Client{
	Timeout: 30 * time.Second,
}

// hlsManifest is the public handler for the m3u8 endpoint. It does no
// auth — the playlist itself contains no sensitive data; access control
// happens at the HTTP layer (CORS, rate limits) and via the underlying
// session's status (we 404 if the stream isn't live).
func (h *Handler) hlsManifest(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	sess, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.Error(httpx.NewNotFound("session not found"))
		return
	}
	if sess.Status != string(StatusLive) {
		c.Error(httpx.NewNotFound("stream not live"))
		return
	}
	upstream := fmt.Sprintf("%s/live/%s.m3u8", h.svc.hlsHost, sess.StreamKey)

	// Cold-start bridge. on_publish flips status to 'live' the instant the
	// host's RTMP/WHIP connects, but SRS needs another ~4-6s to accumulate
	// the first HLS segments. A buyer who opens the room in that window
	// would otherwise get a 404 / placeholder master on their first
	// playlist fetch and have to retry client-side — which is exactly the
	// run of red "(failed)" playlist.m3u8 requests in DevTools before the
	// stream finally comes up. Instead, poll SRS here until a real variant
	// playlist appears (or the budget runs out) and hand the buyer a
	// successful first manifest → instant playback, no client retry churn.
	const (
		coldStartAttempts = 12                     // ~6s total
		coldStartDelay    = 500 * time.Millisecond
	)
	var manifest string
	for attempt := 0; ; attempt++ {
		resp, err := proxyHTTPClient.Get(upstream)
		if err != nil {
			slog.Default().Warn("hls proxy: upstream fetch failed", "url", upstream, "err", err)
			c.Error(httpx.NewInternal("upstream fetch", err))
			return
		}
		ready := false
		if resp.StatusCode == http.StatusOK {
			raw, rerr := io.ReadAll(resp.Body)
			resp.Body.Close()
			if rerr != nil {
				c.Error(httpx.NewInternal("read upstream", rerr))
				return
			}
			m := string(raw)
			// SRS's "stream not publishing yet" placeholder is a master
			// playlist with a single BANDWIDTH=1 variant pointing back at
			// the same key — useless for playback (the variant returns the
			// same placeholder, looping hls.js). Treat it as not-ready and
			// keep polling rather than serving it.
			if !isSRSPlaceholderMaster(m, sess.StreamKey) {
				manifest = m
				ready = true
			}
		} else {
			// Non-200 (typically 404 during warmup) — drain + close so the
			// keep-alive connection is reusable on the next poll.
			_, _ = io.Copy(io.Discard, resp.Body)
			resp.Body.Close()
		}
		if ready {
			break
		}
		if attempt >= coldStartAttempts {
			// Still warming up after the budget. Fall back to 404 so the
			// client's own retry path (manifestLoadError) keeps the
			// "Đang kết nối live..." spinner up — covers a host who's slow
			// to actually push after the session flipped to 'live'.
			c.Status(http.StatusNotFound)
			return
		}
		// Bail out promptly if the buyer navigated away mid-poll instead of
		// spinning a goroutine against SRS for nothing.
		select {
		case <-c.Request.Context().Done():
			return
		case <-time.After(coldStartDelay):
		}
	}
	rewritten := rewriteHLSManifest(manifest, sess.StreamKey)
	c.Header("Content-Type", "application/vnd.apple.mpegurl")
	// Manifests change every TARGETDURATION (~2s) so disable caches —
	// players that re-fetch the playlist must see fresh segment lists.
	c.Header("Cache-Control", "no-store")
	c.Header("Access-Control-Allow-Origin", "*")
	_, _ = c.Writer.Write([]byte(rewritten))
}

// isSRSPlaceholderMaster recognises the "no stream yet" master
// playlist SRS returns when a session_key has been allocated but the
// publisher hasn't pushed RTMP. Shape:
//
//   #EXTM3U
//   #EXT-X-STREAM-INF:BANDWIDTH=1,AVERAGE-BANDWIDTH=1
//   /live/<key>.m3u8
//
// Three signals together (a master playlist marker, BANDWIDTH=1
// sentinel, and a variant pointing at the same key) — any one alone
// might be a legitimate manifest we shouldn't reject. The conjunction
// is specific to SRS's pre-publish placeholder.
func isSRSPlaceholderMaster(manifest, streamKey string) bool {
	if !strings.Contains(manifest, "#EXT-X-STREAM-INF") {
		return false
	}
	// BANDWIDTH=1 is SRS's sentinel — real variants always advertise
	// real bitrates (hundreds of kbps to single-digit Mbps).
	if !strings.Contains(manifest, "BANDWIDTH=1,") &&
		!strings.Contains(manifest, "BANDWIDTH=1\n") {
		return false
	}
	// And the variant points at our own stream — not some master
	// playlist with multiple bitrates that happens to mention our key.
	return strings.Contains(manifest, streamKey+".m3u8")
}

// rewriteHLSManifest rewrites every stream_key reference SRS embeds in
// the manifest so hls.js stays on Tropia's proxy paths:
//
//   - `<key>-<seq>.ts(?...)` → `s/<seq>.ts`             (segments)
//   - `(/?live/)?<key>.m3u8(?...)` → `playlist.m3u8`   (variant pointer)
//
// Order matters: the segment rewrite runs FIRST because its match is
// narrower (requires the `-<digits>` suffix). The variant rewrite is
// broader and would otherwise greedily consume segment lines that
// happen to share the `<key>` prefix.
func rewriteHLSManifest(manifest, streamKey string) string {
	segments := segmentRefRegexFor(streamKey)
	manifest = segments.ReplaceAllString(manifest, "s/$1.ts")
	variant := variantRefRegexFor(streamKey)
	manifest = variant.ReplaceAllString(manifest, "playlist.m3u8")
	// NOTE: the per-segment #EXT-X-DISCONTINUITY tags SRS emits (the
	// apivideo RTMP encoder ships irregular GOP/timestamps so SRS marks
	// nearly every segment discontinuous) are deliberately LEFT IN. They
	// reflect real PTS jumps in the source; hls.js is configured to ride
	// through them via nudgeOffset / nudgeMaxRetry / stretchShortVideoTrack
	// / appendErrorMaxRetry (see hls_viewer_web.dart). Stripping the
	// markers made playback stutter — hls.js played straight across a jump
	// it was no longer told about. The real fix is a regular keyframe
	// interval at the publisher, not rewriting the manifest here.
	return manifest
}

// hlsSegment serves a single .ts segment. The URL contains only the
// session id and an opaque sequence number; we reconstruct the real
// SRS path internally.
func (h *Handler) hlsSegment(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	// Param comes from a wildcard route ("*name" → "/3.ts") so strip
	// the leading slash and the .ts suffix before validating. Anything
	// off the expected shape gets a 400 — the player should never
	// request a non-numeric segment if our manifest is correct.
	name := strings.TrimPrefix(c.Param("name"), "/")
	if !strings.HasSuffix(name, ".ts") {
		c.Error(httpx.NewValidation("invalid segment", nil))
		return
	}
	seqStr := strings.TrimSuffix(name, ".ts")
	if seqStr == "" || !isAllDigits(seqStr) {
		c.Error(httpx.NewValidation("invalid segment", nil))
		return
	}
	if _, err := strconv.Atoi(seqStr); err != nil {
		c.Error(httpx.NewValidation("invalid segment", nil))
		return
	}
	sess, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.Error(httpx.NewNotFound("session not found"))
		return
	}
	// We allow segment fetches for sessions in `ended` state too —
	// players that paused mid-stream often resume just after the host
	// ends the live, and serving the trailing segments lets them play
	// out cleanly instead of erroring on the very last few seconds.
	upstreamPath := fmt.Sprintf("/live/%s-%s.ts", sess.StreamKey, seqStr)
	upstream := h.svc.hlsHost + upstreamPath
	req, _ := http.NewRequestWithContext(c.Request.Context(), http.MethodGet, upstream, nil)
	// Pass through Range requests so seekable HLS works if SRS supports
	// it. Other client headers are deliberately not forwarded — we
	// don't want User-Agent / referer pollution upstream.
	if r := c.GetHeader("Range"); r != "" {
		req.Header.Set("Range", r)
	}
	resp, err := proxyHTTPClient.Do(req)
	if err != nil {
		slog.Default().Warn("hls proxy: upstream segment fetch failed", "url", upstream, "err", err)
		c.Error(httpx.NewInternal("upstream fetch", err))
		return
	}
	defer resp.Body.Close()
	c.Header("Content-Type", "video/MP2T")
	// HLS segments are immutable once published — let intermediaries
	// (and the browser disk cache) hold them. SRS drops segments after
	// hls_window seconds, so a long max-age is safe.
	c.Header("Cache-Control", "public, max-age=60")
	c.Header("Access-Control-Allow-Origin", "*")
	if cl := resp.Header.Get("Content-Length"); cl != "" {
		c.Header("Content-Length", cl)
	}
	if cr := resp.Header.Get("Content-Range"); cr != "" {
		c.Header("Content-Range", cr)
	}
	c.Status(resp.StatusCode)
	_, _ = io.Copy(c.Writer, resp.Body)
}

func isAllDigits(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

// proxiedPlaybackPath returns the path-only HLS URL the Flutter client
// should resolve relative to the backend's public URL. We return a path
// (not absolute URL) so the same playback response works for web /
// emulator / phone / desktop without the backend caring about which
// hostname each is hitting.
func proxiedPlaybackPath(sessionID uuid.UUID) string {
	return "/api/live/streams/" + url.PathEscape(sessionID.String()) + "/hls/playlist.m3u8"
}

// ensureNoTrailingSlash defensive utility — strings.TrimRight is
// equivalent but the helper makes intent obvious at call sites.
func ensureNoTrailingSlash(s string) string { return strings.TrimRight(s, "/") }

var _ = ensureNoTrailingSlash // reserved for future hostname normalisation
