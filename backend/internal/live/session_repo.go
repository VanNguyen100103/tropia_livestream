package live

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Session struct {
	ID              uuid.UUID  `json:"id"`
	SellerID        uuid.UUID  `json:"seller_id"`
	Title           string     `json:"title"`
	Description     *string    `json:"description,omitempty"`
	CoverImageURL   *string    `json:"cover_image_url,omitempty"`
	Category        *string    `json:"category,omitempty"`
	AgoraChannel    string     `json:"agora_channel"`           // SRS stream key
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
	CreatedAt       time.Time  `json:"created_at"`
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

func (r *SessionRepository) Create(ctx context.Context, sellerID uuid.UUID, title, description, coverURL, category, agoraChannel string) (*Session, error) {
	const q = `
		INSERT INTO live_sessions (seller_id, title, description, cover_image_url, category, agora_channel)
		VALUES ($1, $2, NULLIF($3, ''), NULLIF($4, ''), NULLIF($5, ''), $6)
		RETURNING id, seller_id, title, description, cover_image_url, category, agora_channel, status,
		          started_at, ended_at, viewer_count, like_count, order_count, revenue,
		          cart_add_count, follow_count, vod_hls_url, vod_mp4_url, created_at
	`
	var s Session
	if err := scanSession(r.pool.QueryRow(ctx, q, sellerID, title, description, coverURL, category, agoraChannel), &s); err != nil {
		return nil, err
	}
	return &s, nil
}

func (r *SessionRepository) GetByID(ctx context.Context, id uuid.UUID) (*Session, error) {
	const q = `
		SELECT id, seller_id, title, description, cover_image_url, category, agora_channel, status,
		       started_at, ended_at, viewer_count, like_count, order_count, revenue,
		       cart_add_count, follow_count, vod_hls_url, vod_mp4_url, created_at
		FROM live_sessions WHERE id = $1
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
		SELECT id, seller_id, title, description, cover_image_url, category, agora_channel, status,
		       started_at, ended_at, viewer_count, like_count, order_count, revenue,
		       cart_add_count, follow_count, vod_hls_url, vod_mp4_url, created_at
		FROM live_sessions WHERE agora_channel = $1
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
	const q = `
		SELECT id, seller_id, title, description, cover_image_url, category, agora_channel, status,
		       started_at, ended_at, viewer_count, like_count, order_count, revenue,
		       cart_add_count, follow_count, vod_hls_url, vod_mp4_url, created_at
		FROM live_sessions
		WHERE status = 'live'
		ORDER BY started_at DESC
		LIMIT $1
	`
	rows, err := r.pool.Query(ctx, q, limit)
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
	_, err := r.pool.Exec(ctx, `UPDATE live_sessions SET status = 'live' WHERE agora_channel = $1`, channel)
	return err
}

func (r *SessionRepository) End(ctx context.Context, id uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `UPDATE live_sessions SET status = 'ended', ended_at = NOW() WHERE id = $1`, id)
	return err
}

func (r *SessionRepository) EndByChannel(ctx context.Context, channel string) error {
	_, err := r.pool.Exec(ctx, `UPDATE live_sessions SET status = 'ended', ended_at = NOW() WHERE agora_channel = $1`, channel)
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

func (r *SessionRepository) IncrementLikes(ctx context.Context, sessionID uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `SELECT increment_likes($1)`, sessionID)
	return err
}

func (r *SessionRepository) IncrementCartAdd(ctx context.Context, sessionID uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `SELECT increment_cart_add($1)`, sessionID)
	return err
}

func (r *SessionRepository) IncrementFollow(ctx context.Context, sessionID uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `SELECT increment_follow_count($1)`, sessionID)
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
		_, err := tx.Exec(ctx, `
			INSERT INTO live_session_products (session_id, product_id, product_name, image_url,
			  original_price, sale_price, discount_pct, stock_left, sold_count, unit, category, sort_order, is_pinned)
			VALUES ($1, $2, $3, NULLIF($4, ''), $5, $6, $7, $8, 0, COALESCE(NULLIF($9, ''), 'cái'), NULLIF($10, ''), $11, $12)`,
			sessionID, it.ProductID, it.ProductName, "",
			it.OriginalPrice, it.SalePrice, it.DiscountPct, it.StockLeft, it.Unit, "", i, it.IsPinned)
		if err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
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

// ---------- helpers ----------

type sessRowScanner interface{ Scan(...any) error }

func scanSession(row sessRowScanner, s *Session) error {
	return row.Scan(
		&s.ID, &s.SellerID, &s.Title, &s.Description, &s.CoverImageURL, &s.Category,
		&s.AgoraChannel, &s.Status, &s.StartedAt, &s.EndedAt,
		&s.ViewerCount, &s.LikeCount, &s.OrderCount, &s.Revenue,
		&s.CartAddCount, &s.FollowCount, &s.VodHlsURL, &s.VodMp4URL, &s.CreatedAt,
	)
}
