package live

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// ─────────────────────────────────────────────────────────────────────────
// Spec chat + gift persistence (LIVESTREAM_API.md §7 & §8)
// ─────────────────────────────────────────────────────────────────────────

// SpecChatMessage is the chat item shape the spec returns. `id`/`user_id`
// are integer seqs; `meta` mirrors display_name/avatar and embeds the gift
// object for gift messages.
type SpecChatMessage struct {
	ID          int64          `json:"id"`
	StreamKey   string         `json:"stream_key"`
	UserID      int64          `json:"user_id"`
	Message     string         `json:"message"`
	MessageType string         `json:"message_type"`
	GiftID      *int64         `json:"gift_id"`
	DisplayName string         `json:"display_name"`
	Avatar      string         `json:"avatar"`
	Meta        map[string]any `json:"meta"`
	CreatedAt   time.Time      `json:"created_at"`
}

// GiftCatalogItem is one purchasable gift type.
type GiftCatalogItem struct {
	ID           int64   `json:"id"`
	Code         string  `json:"code"`
	Name         string  `json:"name"`
	IconURL      *string `json:"icon_url"`
	PointCost    int     `json:"point_cost"`
	DisplayValue int     `json:"display_value"`
}

// SpecGift is a sent gift (gift/send response + gifts/recent items).
type SpecGift struct {
	ID           int64     `json:"id"`
	StreamKey    string    `json:"stream_key,omitempty"`
	SenderUserID int64     `json:"sender_user_id"`
	SenderName   string    `json:"sender_name"`
	SenderAvatar string    `json:"sender_avatar"`
	GiftID       int64     `json:"gift_id"`
	GiftCode     string    `json:"gift_code"`
	GiftName     string    `json:"gift_name"`
	GiftIconURL  *string   `json:"gift_icon_url"`
	Quantity     int       `json:"quantity"`
	TotalPoints  int       `json:"total_points"`
	DisplayValue int       `json:"display_value"`
	CreatedAt    time.Time `json:"created_at"`
}

// Sentinel errors for the gift flow — the handler maps each to a
// Vietnamese 400 message per the spec.
var (
	ErrGiftNotFound      = errors.New("gift not found")
	ErrNoLoyaltyAccount  = errors.New("no loyalty account")
	ErrInsufficientPoint = errors.New("insufficient points")
)

// profileSpec returns the integer seq, display name, and avatar for a user.
func (r *SessionRepository) profileSpec(ctx context.Context, uid uuid.UUID) (seq int64, name, avatar string) {
	_ = r.pool.QueryRow(ctx,
		`SELECT COALESCE(seq, 0), COALESCE(name, ''), COALESCE(avatar_url, '')
		   FROM profiles WHERE id = $1`, uid).Scan(&seq, &name, &avatar)
	return seq, name, avatar
}

// InsertSpecChat persists a text chat message and returns it in spec shape.
func (r *SessionRepository) InsertSpecChat(ctx context.Context, sessionID uuid.UUID, streamKey string, userID uuid.UUID, message string, isHost bool) (*SpecChatMessage, error) {
	seq, name, avatar := r.profileSpec(ctx, userID)
	var hostPtr *bool
	if isHost {
		hostPtr = &isHost
	}
	var m SpecChatMessage
	err := r.pool.QueryRow(ctx, `
		INSERT INTO chat_messages (session_id, user_id, username, avatar_url, message, type, is_host)
		VALUES ($1, $2, $3, NULLIF($4, ''), $5, 'text', $6)
		RETURNING seq, message, type, gift_id, created_at
	`, sessionID, userID, name, avatar, message, hostPtr).Scan(
		&m.ID, &m.Message, &m.MessageType, &m.GiftID, &m.CreatedAt,
	)
	if err != nil {
		return nil, err
	}
	m.StreamKey = streamKey
	m.UserID = seq
	m.DisplayName = name
	m.Avatar = avatar
	m.Meta = map[string]any{"display_name": name, "avatar": avatar}
	return &m, nil
}

// ChatHistory returns up to `limit` messages for a session in chronological
// (old→new) order. When beforeSeq > 0 only messages with seq < beforeSeq
// are returned (spec before_id pagination).
func (r *SessionRepository) ChatHistory(ctx context.Context, sessionID uuid.UUID, streamKey string, limit int, beforeSeq int64) ([]SpecChatMessage, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	var rows pgx.Rows
	var err error
	const base = `
		SELECT cm.seq, COALESCE(p.seq, 0), cm.message, cm.type, cm.gift_id, cm.created_at,
		       COALESCE(cm.username, ''), COALESCE(cm.avatar_url, ''),
		       lg.id, COALESCE(p2.seq, 0), COALESCE(p2.name, ''), COALESCE(p2.avatar_url, ''),
		       gc.id, gc.code, gc.name, gc.icon_url, lg.quantity, lg.total_points, lg.display_value
		  FROM chat_messages cm
		  LEFT JOIN profiles p   ON p.id = cm.user_id
		  LEFT JOIN live_gifts lg ON lg.id = cm.gift_id
		  LEFT JOIN profiles p2  ON p2.id = lg.sender_user_id
		  LEFT JOIN live_gift_catalog gc ON gc.id = lg.gift_id
		 WHERE cm.session_id = $1`
	if beforeSeq > 0 {
		rows, err = r.pool.Query(ctx, base+` AND cm.seq < $2 ORDER BY cm.seq DESC LIMIT $3`, sessionID, beforeSeq, limit)
	} else {
		rows, err = r.pool.Query(ctx, base+` ORDER BY cm.seq DESC LIMIT $2`, sessionID, limit)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	// Collected newest-first; reversed to oldest-first before returning.
	collected := make([]SpecChatMessage, 0, limit)
	for rows.Next() {
		var m SpecChatMessage
		var (
			lgID, gcID                            *int64
			senderSeq                             int64
			senderName, senderAvatar, gcCode, gcN string
			gcIcon                                *string
			qty, totalPts, dispVal                *int
		)
		if err := rows.Scan(
			&m.ID, &m.UserID, &m.Message, &m.MessageType, &m.GiftID, &m.CreatedAt,
			&m.DisplayName, &m.Avatar,
			&lgID, &senderSeq, &senderName, &senderAvatar,
			&gcID, &gcCode, &gcN, &gcIcon, &qty, &totalPts, &dispVal,
		); err != nil {
			return nil, err
		}
		m.StreamKey = streamKey
		m.Meta = map[string]any{"display_name": m.DisplayName, "avatar": m.Avatar}
		if m.MessageType == "gift" && lgID != nil && gcID != nil {
			m.Meta["gift"] = map[string]any{
				"id":           *lgID,
				"stream_key":   streamKey,
				"sender_user_id": senderSeq,
				"sender_name":  senderName,
				"gift_id":      *gcID,
				"gift_code":    gcCode,
				"gift_name":    gcN,
				"quantity":     deref(qty),
				"total_points": deref(totalPts),
				"display_value": deref(dispVal),
			}
		}
		collected = append(collected, m)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	// Reverse to chronological order.
	for i, j := 0, len(collected)-1; i < j; i, j = i+1, j-1 {
		collected[i], collected[j] = collected[j], collected[i]
	}
	return collected, nil
}

func deref(p *int) int {
	if p == nil {
		return 0
	}
	return *p
}

// ListGiftCatalog returns the active gift catalog ordered for display.
func (r *SessionRepository) ListGiftCatalog(ctx context.Context) ([]GiftCatalogItem, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, code, name, icon_url, point_cost, display_value
		   FROM live_gift_catalog WHERE is_active = TRUE ORDER BY sort_order, id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]GiftCatalogItem, 0)
	for rows.Next() {
		var g GiftCatalogItem
		if err := rows.Scan(&g.ID, &g.Code, &g.Name, &g.IconURL, &g.PointCost, &g.DisplayValue); err != nil {
			return nil, err
		}
		out = append(out, g)
	}
	return out, rows.Err()
}

// SendGift charges the sender's loyalty balance, records the gift, and
// posts a 'gift' chat message — all in one transaction. Returns the gift
// and the sender's remaining point balance.
//
// Errors: ErrGiftNotFound (bad gift_id), ErrNoLoyaltyAccount (sender has no
// loyalty row), ErrInsufficientPoint (balance < cost — `need` carries the
// required total so the handler can build the Vietnamese message).
func (r *SessionRepository) SendGift(ctx context.Context, sessionID uuid.UUID, streamKey string, senderID uuid.UUID, giftID int64, quantity int) (gift *SpecGift, pointsRemaining int, need int, err error) {
	if quantity <= 0 {
		quantity = 1
	}
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, 0, 0, err
	}
	defer tx.Rollback(ctx)

	// Catalog lookup.
	var (
		gCode, gName string
		gIcon        *string
		pointCost    int
		dispValue    int
	)
	err = tx.QueryRow(ctx,
		`SELECT code, name, icon_url, point_cost, display_value
		   FROM live_gift_catalog WHERE id = $1 AND is_active = TRUE`, giftID).
		Scan(&gCode, &gName, &gIcon, &pointCost, &dispValue)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, 0, 0, ErrGiftNotFound
	}
	if err != nil {
		return nil, 0, 0, err
	}
	totalPoints := pointCost * quantity
	totalDisplay := dispValue * quantity

	// Lock the sender's loyalty row.
	var balance int
	err = tx.QueryRow(ctx,
		`SELECT points FROM user_loyalty WHERE user_id = $1 FOR UPDATE`, senderID).Scan(&balance)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, 0, 0, ErrNoLoyaltyAccount
	}
	if err != nil {
		return nil, 0, 0, err
	}
	if balance < totalPoints {
		return nil, balance, totalPoints, ErrInsufficientPoint
	}

	// Deduct.
	if _, err = tx.Exec(ctx,
		`UPDATE user_loyalty SET points = points - $2, updated_at = NOW() WHERE user_id = $1`,
		senderID, totalPoints); err != nil {
		return nil, 0, 0, err
	}
	pointsRemaining = balance - totalPoints

	// Record the gift.
	var g SpecGift
	err = tx.QueryRow(ctx, `
		INSERT INTO live_gifts (session_id, stream_key, sender_user_id, gift_id, quantity, total_points, display_value)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id, created_at
	`, sessionID, streamKey, senderID, giftID, quantity, totalPoints, totalDisplay).Scan(&g.ID, &g.CreatedAt)
	if err != nil {
		return nil, 0, 0, err
	}

	senderSeq, senderName, senderAvatar := profileSpecTx(ctx, tx, senderID)

	// Gift system chat message so history/overlay reflect the gift.
	giftMsg := fmt.Sprintf("%s tặng %dx %s", senderName, quantity, gName)
	if _, err = tx.Exec(ctx, `
		INSERT INTO chat_messages (session_id, user_id, username, avatar_url, message, type, gift_id)
		VALUES ($1, $2, $3, NULLIF($4, ''), $5, 'gift', $6)
	`, sessionID, senderID, senderName, senderAvatar, giftMsg, g.ID); err != nil {
		return nil, 0, 0, err
	}

	if err = tx.Commit(ctx); err != nil {
		return nil, 0, 0, err
	}

	g.StreamKey = streamKey
	g.SenderUserID = senderSeq
	g.SenderName = senderName
	g.SenderAvatar = senderAvatar
	g.GiftID = giftID
	g.GiftCode = gCode
	g.GiftName = gName
	g.GiftIconURL = gIcon
	g.Quantity = quantity
	g.TotalPoints = totalPoints
	g.DisplayValue = totalDisplay
	return &g, pointsRemaining, 0, nil
}

// profileSpecTx is profileSpec inside an open transaction.
func profileSpecTx(ctx context.Context, tx pgx.Tx, uid uuid.UUID) (seq int64, name, avatar string) {
	_ = tx.QueryRow(ctx,
		`SELECT COALESCE(seq, 0), COALESCE(name, ''), COALESCE(avatar_url, '')
		   FROM profiles WHERE id = $1`, uid).Scan(&seq, &name, &avatar)
	return seq, name, avatar
}

// RecentGifts returns sent gifts for a session, newest first.
func (r *SessionRepository) RecentGifts(ctx context.Context, sessionID uuid.UUID, limit int) ([]SpecGift, error) {
	if limit <= 0 || limit > 100 {
		limit = 30
	}
	rows, err := r.pool.Query(ctx, `
		SELECT lg.id, COALESCE(p.seq, 0), COALESCE(p.name, ''), COALESCE(p.avatar_url, ''),
		       lg.gift_id, gc.code, gc.name, gc.icon_url,
		       lg.quantity, lg.total_points, lg.display_value, lg.created_at
		  FROM live_gifts lg
		  JOIN live_gift_catalog gc ON gc.id = lg.gift_id
		  LEFT JOIN profiles p ON p.id = lg.sender_user_id
		 WHERE lg.session_id = $1
		 ORDER BY lg.id DESC
		 LIMIT $2
	`, sessionID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]SpecGift, 0)
	for rows.Next() {
		var g SpecGift
		if err := rows.Scan(
			&g.ID, &g.SenderUserID, &g.SenderName, &g.SenderAvatar,
			&g.GiftID, &g.GiftCode, &g.GiftName, &g.GiftIconURL,
			&g.Quantity, &g.TotalPoints, &g.DisplayValue, &g.CreatedAt,
		); err != nil {
			return nil, err
		}
		out = append(out, g)
	}
	return out, rows.Err()
}
