package live

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrNotFound = errors.New("stream not found")

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) Create(ctx context.Context, sellerID uuid.UUID, title, description, coverURL, category, streamKey string) (*Stream, error) {
	const q = `
		INSERT INTO live_streams (seller_id, title, description, cover_image_url, category, stream_key, status)
		VALUES ($1, $2, $3, $4, $5, $6, 'scheduled')
		RETURNING id, seller_id, title, description, cover_image_url, category, stream_key, status,
		          viewer_count, like_count, started_at, ended_at, vod_hls_url, vod_mp4_url, created_at
	`
	var s Stream
	row := r.pool.QueryRow(ctx, q, sellerID, title, description, coverURL, category, streamKey)
	if err := scanStream(row, &s); err != nil {
		return nil, err
	}
	return &s, nil
}

func (r *Repository) GetByID(ctx context.Context, id uuid.UUID) (*Stream, error) {
	const q = `
		SELECT id, seller_id, title, description, cover_image_url, category, stream_key, status,
		       viewer_count, like_count, started_at, ended_at, vod_hls_url, vod_mp4_url, created_at
		FROM live_streams WHERE id = $1
	`
	var s Stream
	row := r.pool.QueryRow(ctx, q, id)
	if err := scanStream(row, &s); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &s, nil
}

func (r *Repository) GetByStreamKey(ctx context.Context, streamKey string) (*Stream, error) {
	const q = `
		SELECT id, seller_id, title, description, cover_image_url, category, stream_key, status,
		       viewer_count, like_count, started_at, ended_at, vod_hls_url, vod_mp4_url, created_at
		FROM live_streams WHERE stream_key = $1
	`
	var s Stream
	row := r.pool.QueryRow(ctx, q, streamKey)
	if err := scanStream(row, &s); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &s, nil
}

func (r *Repository) ListLive(ctx context.Context, limit int) ([]Stream, error) {
	const q = `
		SELECT id, seller_id, title, description, cover_image_url, category, '' as stream_key, status,
		       viewer_count, like_count, started_at, ended_at, vod_hls_url, vod_mp4_url, created_at
		FROM live_streams
		WHERE status = 'live'
		ORDER BY started_at DESC
		LIMIT $1
	`
	rows, err := r.pool.Query(ctx, q, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []Stream
	for rows.Next() {
		var s Stream
		if err := scanStream(rows, &s); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

func (r *Repository) MarkLive(ctx context.Context, streamKey string) error {
	const q = `
		UPDATE live_streams SET status = 'live', started_at = NOW()
		WHERE stream_key = $1 AND status != 'live'
	`
	_, err := r.pool.Exec(ctx, q, streamKey)
	return err
}

func (r *Repository) MarkEnded(ctx context.Context, streamKey string) error {
	const q = `
		UPDATE live_streams SET status = 'ended', ended_at = NOW()
		WHERE stream_key = $1 AND status = 'live'
	`
	_, err := r.pool.Exec(ctx, q, streamKey)
	return err
}

func (r *Repository) IncrViewer(ctx context.Context, streamKey string, delta int) error {
	const q = `UPDATE live_streams SET viewer_count = GREATEST(0, viewer_count + $2) WHERE stream_key = $1`
	_, err := r.pool.Exec(ctx, q, streamKey, delta)
	return err
}

// rowScanner is satisfied by both pgx.Row and pgx.Rows
type rowScanner interface {
	Scan(dest ...any) error
}

func scanStream(row rowScanner, s *Stream) error {
	var description, coverURL, category, streamKey, vodHls, vodMp4 *string
	var startedAt, endedAt *time.Time
	err := row.Scan(
		&s.ID, &s.SellerID, &s.Title, &description, &coverURL, &category, &streamKey, &s.Status,
		&s.ViewerCount, &s.LikeCount, &startedAt, &endedAt, &vodHls, &vodMp4, &s.CreatedAt,
	)
	if err != nil {
		return err
	}
	if description != nil {
		s.Description = *description
	}
	if coverURL != nil {
		s.CoverImageURL = *coverURL
	}
	if category != nil {
		s.Category = *category
	}
	if streamKey != nil {
		s.StreamKey = *streamKey
	}
	if vodHls != nil {
		s.VodHlsURL = *vodHls
	}
	if vodMp4 != nil {
		s.VodMp4URL = *vodMp4
	}
	s.StartedAt = startedAt
	s.EndedAt = endedAt
	return nil
}
