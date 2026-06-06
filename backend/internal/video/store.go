package video

import (
	"context"
	"os"
	"path"
	"path/filepath"
	"strings"

	"github.com/tropia/backend/internal/storage"
)

// MediaStore abstracts where uploaded video/cover bytes land. In production
// that's Cloudflare R2 (same bucket as images); in local dev — where R2 is
// usually unconfigured — we fall back to the local disk and let the API serve
// the files statically. Returns the URL clients should fetch: an absolute R2
// URL, or a path-relative "/uploads/..." that the Flutter client resolves
// against the backend host (same trick the HLS proxy uses).
type MediaStore interface {
	Save(ctx context.Context, key, contentType string, data []byte) (url string, err error)
	// Owns reports whether url points into this store's namespace. The create
	// endpoint uses it to reject client-supplied video_url/thumbnail_url that
	// don't belong to an upload we issued (arbitrary-URL injection / SSRF on
	// the viewer's client).
	Owns(url string) bool
}

// NewMediaStore picks R2 when available, else the local-disk fallback rooted
// at dir (default "uploads"). dir is also the public URL mount, so the API
// must register router.Static("/"+dir, "./"+dir) for the disk fallback.
func NewMediaStore(r2 *storage.R2, dir string) MediaStore {
	if r2 != nil {
		return &r2Store{r2: r2}
	}
	if dir == "" {
		dir = "uploads"
	}
	return &diskStore{root: dir}
}

type r2Store struct{ r2 *storage.R2 }

func (s *r2Store) Save(ctx context.Context, key, contentType string, data []byte) (string, error) {
	return s.r2.Upload(ctx, key, contentType, data)
}

func (s *r2Store) Owns(url string) bool {
	base := s.r2.PublicBaseURL()
	// Must live under our videos/ prefix in our bucket — not just any object.
	return base != "" && strings.HasPrefix(url, base+"/videos/")
}

// diskStore writes to <root>/<key> on disk and returns "/<root>/<key>" — a
// path-relative URL the static route serves and the Flutter client resolves
// against the backend host (AppConfig.resolveBackendUrl, same as HLS).
// key uses forward slashes (e.g. "videos/clips/<id>/source.mp4").
type diskStore struct{ root string }

func (s *diskStore) Save(_ context.Context, key, _ string, data []byte) (string, error) {
	full := filepath.Join(s.root, filepath.FromSlash(key))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		return "", err
	}
	if err := os.WriteFile(full, data, 0o644); err != nil {
		return "", err
	}
	return "/" + path.Join(s.root, key), nil
}

func (s *diskStore) Owns(url string) bool {
	return strings.HasPrefix(url, "/"+s.root+"/videos/")
}
