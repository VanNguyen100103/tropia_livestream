package live

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrNotFound signals that a session-scoped resource (product, pin
// target, etc.) doesn't exist. Handlers translate this into 404 to
// avoid leaking whether the id is just unknown vs. owned by someone
// else (BOLA defense — same shape as the upload handler's owner check).
var ErrNotFound = errors.New("live: not found")

type Session struct {
	ID              uuid.UUID  `json:"id"`
	SellerID        uuid.UUID  `json:"seller_id"`
	Title           string     `json:"title"`
	Description     *string    `json:"description,omitempty"`
	CoverImageURL   *string    `json:"cover_image_url,omitempty"`
	Category        *string    `json:"category,omitempty"`
	StreamKey    string     `json:"stream_key"`           // SRS stream key
	Status          string     `json:"status"`
	StartedAt       time.Time  `json:"started_at"`
	EndedAt         *time.Time `json:"ended_at,omitempty"`
	ViewerCount     int        `json:"viewer_count"`
	LikeCount       int        `json:"like_count"`
	OrderCount      int        `json:"order_count"`
	Revenue         int        `json:"revenue"`
	CartAddCount    int        `json:"cart_add_count"`
	FollowCount     int        `json:"follow_count"`
	VodHlsURL       *string    `json:"vod_hls_url,omitempty"`
	VodMp4URL       *string    `json:"vod_mp4_url,omitempty"`
	AiBotEnabled    bool       `json:"ai_bot_enabled"`
	// PinnedProductID is the live_session_products.id currently highlighted
	// by the host ("đang giới thiệu"). nil = no pin. Cleared automatically
	// via ON DELETE SET NULL if the underlying session_products row goes.
	PinnedProductID *uuid.UUID `json:"pinned_product_id,omitempty"`
	CreatedAt       time.Time  `json:"created_at"`

	// Joined from shops + profiles (LEFT JOIN — nullable until the seller
	// has both a profile row and an active shop).
	SellerName   *string    `json:"seller_name,omitempty"`
	SellerAvatar *string    `json:"seller_avatar,omitempty"`
	ShopID       *uuid.UUID `json:"shop_id,omitempty"`
	ShopName     *string    `json:"shop_name,omitempty"`
	ShopLogoURL  *string    `json:"shop_logo_url,omitempty"`
}

type SessionProduct struct {
	ID            uuid.UUID  `json:"id"`
	SessionID     uuid.UUID  `json:"session_id"`
	ProductID     *uuid.UUID `json:"product_id,omitempty"`
	ProductName   string     `json:"product_name"`
	ImageURL      *string    `json:"image_url,omitempty"`
	OriginalPrice float64    `json:"original_price"`
	SalePrice     float64    `json:"sale_price"`
	DiscountPct   float64    `json:"discount_pct"`
	StockLeft     int        `json:"stock_left"`
	SoldCount     int        `json:"sold_count"`
	Unit          string     `json:"unit"`
	Category      *string    `json:"category,omitempty"`
	SortOrder     int        `json:"sort_order"`
	IsPinned      bool       `json:"is_pinned"`
}

var ErrSessionNotFound = errors.New("session not found")

type SessionRepository struct{ pool *pgxpool.Pool }

func NewSessionRepository(pool *pgxpool.Pool) *SessionRepository {
	return &SessionRepository{pool: pool}
}

func (r *SessionRepository) Create(ctx context.Context, sellerID uuid.UUID, title, description, coverURL, category, streamKey string) (*Session, error) {
	// Insert returns the bare session row (no JOIN). The caller typically
	// has its own context for the seller/shop fields, and we re-fetch via
	// GetByID elsewhere when those are needed.
	const q = `
		INSERT INTO live_sessions (seller_id, title, description, cover_image_url, category, stream_key)
		VALUES ($1, $2, NULLIF($3, ''), NULLIF($4, ''), NULLIF($5, ''), $6)
		RETURNING id, seller_id, title, description, cover_image_url, category, stream_key, status,
		          started_at, ended_at, viewer_count, like_count, order_count, revenue,
		          cart_add_count, follow_count, vod_hls_url, vod_mp4_url, ai_bot_enabled, pinned_product_id, created_at
	`
	var s Session
	if err := r.pool.QueryRow(ctx, q, sellerID, title, description, coverURL, category, streamKey).Scan(
		&s.ID, &s.SellerID, &s.Title, &s.Description, &s.CoverImageURL, &s.Category,
		&s.StreamKey, &s.Status, &s.StartedAt, &s.EndedAt,
		&s.ViewerCount, &s.LikeCount, &s.OrderCount, &s.Revenue,
		&s.CartAddCount, &s.FollowCount, &s.VodHlsURL, &s.VodMp4URL, &s.AiBotEnabled, &s.PinnedProductID, &s.CreatedAt,
	); err != nil {
		return nil, err
	}
	return &s, nil
}

func (r *SessionRepository) GetByID(ctx context.Context, id uuid.UUID) (*Session, error) {
	const q = `
		SELECT ls.id, ls.seller_id, ls.title, ls.description, ls.cover_image_url, ls.category, ls.stream_key, ls.status,
		       ls.started_at, ls.ended_at, ls.viewer_count, ls.like_count, ls.order_count, ls.revenue,
		       ls.cart_add_count, ls.follow_count, ls.vod_hls_url, ls.vod_mp4_url, ls.ai_bot_enabled, ls.pinned_product_id, ls.created_at,
		       p.name, p.avatar_url, s.id, s.name, s.logo_url
		FROM live_sessions ls
		LEFT JOIN profiles p ON p.id = ls.seller_id
		LEFT JOIN shops s    ON s.seller_id = ls.seller_id
		WHERE ls.id = $1
	`
	var s Session
	if err := scanSession(r.pool.QueryRow(ctx, q, id), &s); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrSessionNotFound
		}
		return nil, err
	}
	return &s, nil
}

func (r *SessionRepository) GetByChannel(ctx context.Context, channel string) (*Session, error) {
	const q = `
		SELECT ls.id, ls.seller_id, ls.title, ls.description, ls.cover_image_url, ls.category, ls.stream_key, ls.status,
		       ls.started_at, ls.ended_at, ls.viewer_count, ls.like_count, ls.order_count, ls.revenue,
		       ls.cart_add_count, ls.follow_count, ls.vod_hls_url, ls.vod_mp4_url, ls.ai_bot_enabled, ls.pinned_product_id, ls.created_at,
		       p.name, p.avatar_url, s.id, s.name, s.logo_url
		FROM live_sessions ls
		LEFT JOIN profiles p ON p.id = ls.seller_id
		LEFT JOIN shops s    ON s.seller_id = ls.seller_id
		WHERE ls.stream_key = $1
	`
	var s Session
	if err := scanSession(r.pool.QueryRow(ctx, q, channel), &s); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrSessionNotFound
		}
		return nil, err
	}
	return &s, nil
}

func (r *SessionRepository) ListActive(ctx context.Context, limit int) ([]Session, error) {
	return r.ListActiveCursor(ctx, limit, time.Time{}, uuid.Nil)
}

// ListActiveCursor is the cursor-paginated variant — preferred for
// any caller that might walk past the first page (threat 7 — DB
// scraping). The cursor is the (started_at, id) of the last row
// returned in the previous page; rows strictly past that point in
// the (started_at DESC, id DESC) order come back.
//
// Why cursor over OFFSET: a bot that knows how to ?offset=50&offset=100…
// can enumerate the entire table. Cursors require knowing the last
// row's primary keys, which an attacker can only learn by walking
// through the natural pagination — and the rate limiter already
// gates that walk. Equally important, cursors are stable under
// concurrent inserts (offset shifts every time a new session goes
// live).
//
// Passing cursorTime.IsZero() / cursorID == uuid.Nil returns the
// first page — same behaviour as the old offset-less call.
func (r *SessionRepository) ListActiveCursor(ctx context.Context, limit int, cursorTime time.Time, cursorID uuid.UUID) ([]Session, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	// The cursor condition is a tuple comparison: (started_at, id) <
	// (cursorTime, cursorID). PostgreSQL natively supports row
	// constructor comparison, but pgx's parameter binding is fussier
	// — express it as ORs for portability.
	var rows pgx.Rows
	var err error
	const base = `
		SELECT ls.id, ls.seller_id, ls.title, ls.description, ls.cover_image_url, ls.category, ls.stream_key, ls.status,
		       ls.started_at, ls.ended_at,
		       COALESCE(vc.cnt, 0) AS viewer_count,
		       ls.like_count, ls.order_count, ls.revenue,
		       ls.cart_add_count, ls.follow_count, ls.vod_hls_url, ls.vod_mp4_url, ls.ai_bot_enabled, ls.pinned_product_id, ls.created_at,
		       p.name, p.avatar_url, s.id, s.name, s.logo_url
		FROM live_sessions ls
		LEFT JOIN profiles p ON p.id = ls.seller_id
		LEFT JOIN shops s    ON s.seller_id = ls.seller_id
		LEFT JOIN (
		    SELECT session_id, COUNT(*) AS cnt
		    FROM live_viewers
		    GROUP BY session_id
		) vc ON vc.session_id = ls.id
		WHERE ls.status = 'live'
	`
	if cursorTime.IsZero() {
		rows, err = r.pool.Query(ctx, base+
			` ORDER BY ls.started_at DESC, ls.id DESC LIMIT $1`, limit)
	} else {
		rows, err = r.pool.Query(ctx, base+
			` AND (ls.started_at < $1 OR (ls.started_at = $1 AND ls.id < $2))
			  ORDER BY ls.started_at DESC, ls.id DESC LIMIT $3`,
			cursorTime, cursorID, limit)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]Session, 0)
	for rows.Next() {
		var s Session
		if err := scanSession(rows, &s); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

func (r *SessionRepository) MarkLive(ctx context.Context, channel string) error {
	// Promote any non-ended row back to live. Covers two flows:
	//   1. First publish after startLive() — session was 'scheduled',
	//      becomes 'live' as expected.
	//   2. RTMP blip → SRS fires on_unpublish (we'd marked ended_at) →
	//      RTMP reconnects → on_publish fires this — we need to flip the
	//      row back so viewers don't get kicked. Only refusing 'ended'
	//      sessions (host explicitly pressed "Kết thúc") would be too
	//      strict; instead we trust the explicit End() call below to be
	//      the only authoritative end.
	// The ended-by-host case is protected by End() also nulling ended_at
	// implicitly — once End() runs, EndByChannel won't be hit again until
	// a brand-new session starts.
	_, err := r.pool.Exec(ctx,
		`UPDATE live_sessions
		    SET status = 'live', ended_at = NULL
		  WHERE stream_key = $1
		    AND status != 'ended'`, channel)
	return err
}

func (r *SessionRepository) End(ctx context.Context, id uuid.UUID) error {
	// Authoritative end — called from the API handler when the host taps
	// "Kết thúc Live". Sets status='ended' permanently; even a follow-up
	// SRS on_publish webhook can't resurrect it (MarkLive's WHERE clause
	// excludes ended rows).
	_, err := r.pool.Exec(ctx, `UPDATE live_sessions SET status = 'ended', ended_at = NOW() WHERE id = $1`, id)
	return err
}

func (r *SessionRepository) EndByChannel(ctx context.Context, channel string) error {
	// SRS on_unpublish fires on ANY RTMP disconnect — intentional end,
	// network blip, host app backgrounded, etc. We only stamp ended_at
	// (so the host's "Tổng kết" screen has the duration) WITHOUT flipping
	// status, because the apivideo reconnect might bring the stream back
	// within a few seconds. Status only flips to 'ended' through the
	// explicit End() call wired to the user-facing "Kết thúc Live" button.
	_, err := r.pool.Exec(ctx, `UPDATE live_sessions SET ended_at = NOW() WHERE stream_key = $1 AND status != 'ended'`, channel)
	return err
}

// EndStaleSessions force-ends any ready/live session whose started_at is
// older than maxAge — the platform's max live-duration cap. Sets
// status='offline', stamps ended_at, and revokes the publish token so a
// reconnecting encoder can't resurrect it. Returns the stream_keys ended
// (for logging / stats push). Run periodically by the worker.
func (r *SessionRepository) EndStaleSessions(ctx context.Context, maxAge time.Duration) ([]string, error) {
	cutoff := time.Now().Add(-maxAge)
	rows, err := r.pool.Query(ctx,
		`UPDATE live_sessions
		    SET status = 'offline', ended_at = NOW(), publish_token = NULL
		  WHERE status IN ('ready', 'live') AND started_at < $1
		  RETURNING stream_key`, cutoff)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var keys []string
	for rows.Next() {
		var k string
		if err := rows.Scan(&k); err != nil {
			return nil, err
		}
		keys = append(keys, k)
	}
	return keys, rows.Err()
}

// ExpiredRecording is a recording past its R2 retention window, returned by
// ExpiredRecordings for the retention sweeper to delete from R2.
type ExpiredRecording struct {
	ID        uuid.UUID
	SessionID uuid.UUID
	R2Key     string
}

// ExpiredRecordings lists uploaded recordings older than olderThan whose R2
// object should be deleted (VOD retention = 30 days by default).
func (r *SessionRepository) ExpiredRecordings(ctx context.Context, olderThan time.Duration, limit int) ([]ExpiredRecording, error) {
	if limit <= 0 || limit > 500 {
		limit = 200
	}
	cutoff := time.Now().Add(-olderThan)
	rows, err := r.pool.Query(ctx,
		`SELECT id, session_id, r2_key
		   FROM recordings
		  WHERE status = 'uploaded' AND r2_key IS NOT NULL
		    AND COALESCE(completed_at, created_at) < $1
		  ORDER BY COALESCE(completed_at, created_at)
		  LIMIT $2`, cutoff, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]ExpiredRecording, 0)
	for rows.Next() {
		var e ExpiredRecording
		if err := rows.Scan(&e.ID, &e.SessionID, &e.R2Key); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// MarkRecordingExpired flags a recording 'expired' + clears its r2_key after
// the R2 object is deleted, and nulls the session's VOD URLs so the app
// stops surfacing a dead playback link.
func (r *SessionRepository) MarkRecordingExpired(ctx context.Context, recID, sessionID uuid.UUID) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx,
		`UPDATE recordings SET status = 'expired', r2_key = NULL WHERE id = $1`, recID); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx,
		`UPDATE live_sessions SET vod_mp4_url = NULL, vod_hls_url = NULL WHERE id = $1`, sessionID); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// SetVodURLs records the public URLs of the uploaded VOD after worker
// finishes FFmpeg remux + R2 upload.
func (r *SessionRepository) SetVodURLs(ctx context.Context, sessionID uuid.UUID, mp4URL, hlsURL string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE live_sessions
		    SET vod_mp4_url = NULLIF($2, ''),
		        vod_hls_url = NULLIF($3, '')
		  WHERE id = $1`,
		sessionID, mp4URL, hlsURL)
	return err
}

// InsertRecording logs each recording attempt in the recordings table.
func (r *SessionRepository) InsertRecording(ctx context.Context, sessionID uuid.UUID, srsFilePath string, durationSec int) (uuid.UUID, error) {
	var id uuid.UUID
	err := r.pool.QueryRow(ctx,
		`INSERT INTO recordings (session_id, srs_file_path, duration_sec, status)
		 VALUES ($1, $2, NULLIF($3, 0), 'processing')
		 RETURNING id`,
		sessionID, srsFilePath, durationSec).Scan(&id)
	return id, err
}

func (r *SessionRepository) MarkRecordingUploaded(ctx context.Context, recID uuid.UUID, r2Key string, sizeBytes int64) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE recordings
		    SET r2_key = $2,
		        file_size_bytes = $3,
		        status = 'uploaded',
		        completed_at = NOW()
		  WHERE id = $1`,
		recID, r2Key, sizeBytes)
	return err
}

func (r *SessionRepository) MarkRecordingFailed(ctx context.Context, recID uuid.UUID, errMsg string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE recordings SET status = 'failed', error_message = $2 WHERE id = $1`,
		recID, errMsg)
	return err
}

func (r *SessionRepository) UpsertViewer(ctx context.Context, sessionID, userID uuid.UUID) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO live_viewers (session_id, user_id) VALUES ($1, $2)
		 ON CONFLICT DO NOTHING`,
		sessionID, userID)
	return err
}

func (r *SessionRepository) RemoveViewer(ctx context.Context, sessionID, userID uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM live_viewers WHERE session_id = $1 AND user_id = $2`, sessionID, userID)
	return err
}

// CountViewers returns the live row count from live_viewers — used by
// getStats so the host overlay shows the actual number of currently-
// connected viewers, not the cached counter on live_sessions which can
// drift (see comment in getStats).
func (r *SessionRepository) CountViewers(ctx context.Context, sessionID uuid.UUID) (int, error) {
	var n int
	err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM live_viewers WHERE session_id = $1`,
		sessionID).Scan(&n)
	return n, err
}

// CountFollows returns the number of distinct viewers who tapped the
// follow pill during this session. Read off live_session_follows so the
// stat survives a cached-counter drift the same way CountViewers does.
func (r *SessionRepository) CountFollows(ctx context.Context, sessionID uuid.UUID) (int, error) {
	var n int
	err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM live_session_follows WHERE session_id = $1`,
		sessionID).Scan(&n)
	return n, err
}

func (r *SessionRepository) IncrementLikes(ctx context.Context, sessionID uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `SELECT increment_likes($1)`, sessionID)
	return err
}

func (r *SessionRepository) IncrementCartAdd(ctx context.Context, sessionID uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `SELECT increment_cart_add($1)`, sessionID)
	return err
}

// UpsertFollow records that `userID` tapped the "+ Theo dõi" pill during
// `sessionID`. The composite PK + ON CONFLICT DO NOTHING dedupe — the
// counter trigger only fires on a genuine new row, so a buyer who toggles
// follow on/off 7 times in one stream is still counted as one follow.
// Replaces the old IncrementFollow that blindly incremented the column.
func (r *SessionRepository) UpsertFollow(ctx context.Context, sessionID, userID uuid.UUID) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO live_session_follows (session_id, user_id) VALUES ($1, $2)
		 ON CONFLICT DO NOTHING`,
		sessionID, userID)
	return err
}

// SetBotEnabled toggles the DeepSeek auto-reply bot for a session. Returns
// the new value so the handler can reply with it.
func (r *SessionRepository) SetBotEnabled(ctx context.Context, sessionID uuid.UUID, enabled bool) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE live_sessions SET ai_bot_enabled = $2 WHERE id = $1`,
		sessionID, enabled)
	return err
}

// ---------- Session Products ----------

func (r *SessionRepository) AddProducts(ctx context.Context, sessionID uuid.UUID, items []SessionProduct) error {
	if len(items) == 0 {
		return nil
	}
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	for i, it := range items {
		var imgURL string
		if it.ImageURL != nil {
			imgURL = *it.ImageURL
		}
		var category string
		if it.Category != nil {
			category = *it.Category
		}
		_, err := tx.Exec(ctx, `
			INSERT INTO live_session_products (session_id, product_id, product_name, image_url,
			  original_price, sale_price, discount_pct, stock_left, sold_count, unit, category, sort_order, is_pinned)
			VALUES ($1, $2, $3, NULLIF($4, ''), $5, $6, $7, $8, 0, COALESCE(NULLIF($9, ''), 'cái'), NULLIF($10, ''), $11, $12)`,
			sessionID, it.ProductID, it.ProductName, imgURL,
			it.OriginalPrice, it.SalePrice, it.DiscountPct, it.StockLeft, it.Unit, category, i, it.IsPinned)
		if err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// ReplaceProducts swaps the entire pinned list for the session in one
// transaction. Used when the host returns from the picker — we wipe the
// existing rows and re-insert from `items`, so deletes + additions land
// atomically.
func (r *SessionRepository) ReplaceProducts(ctx context.Context, sessionID uuid.UUID, items []SessionProduct) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `DELETE FROM live_session_products WHERE session_id = $1`, sessionID); err != nil {
		return err
	}
	for i, it := range items {
		var imgURL string
		if it.ImageURL != nil {
			imgURL = *it.ImageURL
		}
		var category string
		if it.Category != nil {
			category = *it.Category
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO live_session_products (session_id, product_id, product_name, image_url,
			  original_price, sale_price, discount_pct, stock_left, sold_count, unit, category, sort_order, is_pinned)
			VALUES ($1, $2, $3, NULLIF($4, ''), $5, $6, $7, $8, 0, COALESCE(NULLIF($9, ''), 'cái'), NULLIF($10, ''), $11, $12)`,
			sessionID, it.ProductID, it.ProductName, imgURL,
			it.OriginalPrice, it.SalePrice, it.DiscountPct, it.StockLeft, it.Unit, category, i, it.IsPinned); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// RemoveProduct unpins one live_session_products row by its own id.
// productID here is live_session_products.id, NOT the catalog product
// uuid — that distinction matters because the host UI references the
// session-scoped record.
func (r *SessionRepository) RemoveProduct(ctx context.Context, sessionID, productID uuid.UUID) error {
	_, err := r.pool.Exec(ctx,
		`DELETE FROM live_session_products WHERE session_id = $1 AND id = $2`,
		sessionID, productID)
	return err
}

// SetPinnedProduct highlights one session product as "đang giới thiệu"
// (Shopee Live "GẶP LÊN"). Pass nil productID to clear the pin.
// Returns ErrNotFound if the product doesn't belong to this session
// — that prevents a malicious host from pinning another session's
// product via id guessing.
func (r *SessionRepository) SetPinnedProduct(ctx context.Context, sessionID uuid.UUID, productID *uuid.UUID) error {
	if productID == nil {
		_, err := r.pool.Exec(ctx,
			`UPDATE live_sessions SET pinned_product_id = NULL WHERE id = $1`,
			sessionID)
		return err
	}
	tag, err := r.pool.Exec(ctx, `
		UPDATE live_sessions
		SET pinned_product_id = $2
		WHERE id = $1
		  AND EXISTS (
		      SELECT 1 FROM live_session_products
		      WHERE id = $2 AND session_id = $1
		  )`,
		sessionID, *productID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *SessionRepository) ListProducts(ctx context.Context, sessionID uuid.UUID) ([]SessionProduct, error) {
	const q = `
		SELECT id, session_id, product_id, product_name, image_url,
		       original_price, sale_price, discount_pct, stock_left, sold_count, unit, category, sort_order, is_pinned
		FROM live_session_products
		WHERE session_id = $1
		ORDER BY sort_order
	`
	rows, err := r.pool.Query(ctx, q, sessionID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]SessionProduct, 0)
	for rows.Next() {
		var p SessionProduct
		if err := rows.Scan(&p.ID, &p.SessionID, &p.ProductID, &p.ProductName, &p.ImageURL,
			&p.OriginalPrice, &p.SalePrice, &p.DiscountPct, &p.StockLeft, &p.SoldCount,
			&p.Unit, &p.Category, &p.SortOrder, &p.IsPinned); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// ListProductsForSessions batch-fetches pinned products for many
// sessions in one query. Used by listActive to kill the N+1 pattern —
// 50 sessions used to fire 51 queries (1 list + 50 products), this
// brings it to 2. Returns a map keyed by session_id so callers can
// stitch back without scanning the slice every iteration.
func (r *SessionRepository) ListProductsForSessions(ctx context.Context, sessionIDs []uuid.UUID) (map[uuid.UUID][]SessionProduct, error) {
	if len(sessionIDs) == 0 {
		return map[uuid.UUID][]SessionProduct{}, nil
	}
	const q = `
		SELECT id, session_id, product_id, product_name, image_url,
		       original_price, sale_price, discount_pct, stock_left, sold_count, unit, category, sort_order, is_pinned
		FROM live_session_products
		WHERE session_id = ANY($1)
		ORDER BY session_id, sort_order
	`
	rows, err := r.pool.Query(ctx, q, sessionIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make(map[uuid.UUID][]SessionProduct, len(sessionIDs))
	for rows.Next() {
		var p SessionProduct
		if err := rows.Scan(&p.ID, &p.SessionID, &p.ProductID, &p.ProductName, &p.ImageURL,
			&p.OriginalPrice, &p.SalePrice, &p.DiscountPct, &p.StockLeft, &p.SoldCount,
			&p.Unit, &p.Category, &p.SortOrder, &p.IsPinned); err != nil {
			return nil, err
		}
		out[p.SessionID] = append(out[p.SessionID], p)
	}
	return out, rows.Err()
}

func (r *SessionRepository) GetSessionProduct(ctx context.Context, id uuid.UUID) (*SessionProduct, error) {
	const q = `
		SELECT id, session_id, product_id, product_name, image_url,
		       original_price, sale_price, discount_pct, stock_left, sold_count, unit, category, sort_order, is_pinned
		FROM live_session_products WHERE id = $1
	`
	var p SessionProduct
	err := r.pool.QueryRow(ctx, q, id).Scan(
		&p.ID, &p.SessionID, &p.ProductID, &p.ProductName, &p.ImageURL,
		&p.OriginalPrice, &p.SalePrice, &p.DiscountPct, &p.StockLeft, &p.SoldCount,
		&p.Unit, &p.Category, &p.SortOrder, &p.IsPinned,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("live product not found")
		}
		return nil, err
	}
	return &p, nil
}

// ---------- Profile lookup (small helper used by chat) ----------

// LookupProfile fetches the display name + avatar for the user posting a
// chat message. We do this inline (rather than going through auth.Repository)
// because the chat handler only needs these two fields — full Profile is
// overkill. Returns ("Khách", "") on lookup failure so the chat never
// blocks on a stale profile row.
func (r *SessionRepository) LookupProfile(ctx context.Context, userID uuid.UUID) (name string, avatar string) {
	const q = `SELECT name, COALESCE(avatar_url, '') FROM profiles WHERE id = $1`
	if err := r.pool.QueryRow(ctx, q, userID).Scan(&name, &avatar); err != nil {
		return "Khách", ""
	}
	return name, avatar
}

// ---------- Chat ----------

type ChatMessage struct {
	ID        uuid.UUID `json:"id"`
	SessionID uuid.UUID `json:"session_id"`
	UserID    uuid.UUID `json:"user_id"`
	Username  string    `json:"username"`
	AvatarURL *string   `json:"avatar_url,omitempty"`
	Message   string    `json:"message"`
	IsHost    *bool     `json:"is_host,omitempty"`
	Type      string    `json:"type"`
	CreatedAt time.Time `json:"created_at"`
}

func (r *SessionRepository) InsertChat(ctx context.Context, m ChatMessage) (*ChatMessage, error) {
	const q = `
		INSERT INTO chat_messages (session_id, user_id, username, avatar_url, message, is_host, type)
		VALUES ($1, $2, $3, NULLIF($4, ''), $5, $6, COALESCE(NULLIF($7, ''), 'text'))
		RETURNING id, session_id, user_id, username, avatar_url, message, is_host, type, created_at
	`
	var avatar string
	if m.AvatarURL != nil {
		avatar = *m.AvatarURL
	}
	row := r.pool.QueryRow(ctx, q, m.SessionID, m.UserID, m.Username, avatar, m.Message, m.IsHost, m.Type)
	var out ChatMessage
	if err := row.Scan(&out.ID, &out.SessionID, &out.UserID, &out.Username, &out.AvatarURL,
		&out.Message, &out.IsHost, &out.Type, &out.CreatedAt); err != nil {
		return nil, err
	}
	return &out, nil
}

func (r *SessionRepository) RecentChats(ctx context.Context, sessionID uuid.UUID, limit int) ([]ChatMessage, error) {
	if limit < 1 || limit > 100 {
		limit = 50
	}
	const q = `
		SELECT id, session_id, user_id, username, avatar_url, message, is_host, type, created_at
		FROM chat_messages WHERE session_id = $1
		ORDER BY created_at DESC LIMIT $2
	`
	rows, err := r.pool.Query(ctx, q, sessionID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]ChatMessage, 0)
	for rows.Next() {
		var m ChatMessage
		if err := rows.Scan(&m.ID, &m.SessionID, &m.UserID, &m.Username, &m.AvatarURL,
			&m.Message, &m.IsHost, &m.Type, &m.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	// reverse to chronological order
	for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
		out[i], out[j] = out[j], out[i]
	}
	return out, rows.Err()
}

// TimelineChats fetches every chat message for a session in chronological
// order, bounded by `limit` (caller picks; 10k is sane for replay). Differs
// from RecentChats which is DESC-then-reverse with a small cap for the
// live chat window — replay needs the full ordered stream.
func (r *SessionRepository) TimelineChats(ctx context.Context, sessionID uuid.UUID, limit int) ([]ChatMessage, error) {
	if limit < 1 {
		limit = 10000
	}
	const q = `
		SELECT id, session_id, user_id, username, avatar_url, message, is_host, type, created_at
		FROM chat_messages WHERE session_id = $1
		ORDER BY created_at ASC LIMIT $2
	`
	rows, err := r.pool.Query(ctx, q, sessionID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]ChatMessage, 0)
	for rows.Next() {
		var m ChatMessage
		if err := rows.Scan(&m.ID, &m.SessionID, &m.UserID, &m.Username, &m.AvatarURL,
			&m.Message, &m.IsHost, &m.Type, &m.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// ---------- helpers ----------

type sessRowScanner interface{ Scan(...any) error }

func scanSession(row sessRowScanner, s *Session) error {
	// All callers of scanSession use the LEFT JOIN query with 5 extra
	// columns (profile.name, profile.avatar_url, shop.id, shop.name,
	// shop.logo_url). Create() uses its own scan inline since it doesn't
	// JOIN.
	return row.Scan(
		&s.ID, &s.SellerID, &s.Title, &s.Description, &s.CoverImageURL, &s.Category,
		&s.StreamKey, &s.Status, &s.StartedAt, &s.EndedAt,
		&s.ViewerCount, &s.LikeCount, &s.OrderCount, &s.Revenue,
		&s.CartAddCount, &s.FollowCount, &s.VodHlsURL, &s.VodMp4URL, &s.AiBotEnabled, &s.PinnedProductID, &s.CreatedAt,
		&s.SellerName, &s.SellerAvatar, &s.ShopID, &s.ShopName, &s.ShopLogoURL,
	)
}
