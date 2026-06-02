package live

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ─────────────────────────────────────────────────────────────────────────
// Shop live-permission repository (migration 0011)
//
// Backs the platform rule "only shop owner / granted staff / approved
// collaborator may livestream". The owner is the sole approver of their own
// shop's members.
// ─────────────────────────────────────────────────────────────────────────

var (
	ErrShopNotFound        = errors.New("shop not found for owner")
	ErrMemberUserNotFound  = errors.New("user not found")
	ErrCannotAddOwner      = errors.New("owner is already authorized")
	ErrMemberNotFound      = errors.New("member not found")
)

// ShopMember is one row of shop_live_permissions joined with the member's
// profile, for the owner's management UI.
type ShopMember struct {
	ID         uuid.UUID  `json:"-"`
	ShopID     uuid.UUID  `json:"-"`
	UserID     uuid.UUID  `json:"-"`
	UserSeq    int64      `json:"user_id"`
	Name       string     `json:"full_name"`
	Email      string     `json:"email"`
	Phone      string     `json:"so_dien_thoai"`
	MemberType string     `json:"member_type"`
	CanLive    bool       `json:"can_live"`
	Status     string     `json:"status"`
	ApprovedAt *time.Time `json:"approved_at,omitempty"`
	CreatedAt  time.Time  `json:"created_at"`
}

type ShopMemberRepository struct{ pool *pgxpool.Pool }

func NewShopMemberRepository(pool *pgxpool.Pool) *ShopMemberRepository {
	return &ShopMemberRepository{pool: pool}
}

// AuthorizedShop reports the shop a user may livestream for, if any:
//   1. a shop they own (shops.seller_id), or
//   2. a shop where they hold an approved, can_live membership.
// Returns ok=false when the user is not authorized to livestream.
func (r *ShopMemberRepository) AuthorizedShop(ctx context.Context, userID uuid.UUID) (uuid.UUID, bool, error) {
	// Owner path.
	var shopID uuid.UUID
	err := r.pool.QueryRow(ctx,
		`SELECT id FROM shops WHERE seller_id = $1 LIMIT 1`, userID).Scan(&shopID)
	if err == nil {
		return shopID, true, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, false, err
	}
	// Approved-member path.
	err = r.pool.QueryRow(ctx,
		`SELECT shop_id FROM shop_live_permissions
		  WHERE user_id = $1 AND status = 'approved' AND can_live = TRUE
		  LIMIT 1`, userID).Scan(&shopID)
	if err == nil {
		return shopID, true, nil
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, false, nil
	}
	return uuid.Nil, false, err
}

// ShopByOwner returns the shop owned by ownerID. ErrShopNotFound if the
// user owns no shop (so they can't manage members).
func (r *ShopMemberRepository) ShopByOwner(ctx context.Context, ownerID uuid.UUID) (uuid.UUID, error) {
	var shopID uuid.UUID
	err := r.pool.QueryRow(ctx,
		`SELECT id FROM shops WHERE seller_id = $1 LIMIT 1`, ownerID).Scan(&shopID)
	if errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, ErrShopNotFound
	}
	return shopID, err
}

// ResolveUser maps an email or phone identifier to a user id + uuid.
func (r *ShopMemberRepository) ResolveUser(ctx context.Context, identifier string) (uuid.UUID, error) {
	identifier = strings.TrimSpace(identifier)
	var col string
	var arg string
	if strings.Contains(identifier, "@") {
		col, arg = "email", strings.ToLower(identifier)
	} else {
		col, arg = "phone", identifier
	}
	var id uuid.UUID
	err := r.pool.QueryRow(ctx,
		`SELECT id FROM profiles WHERE `+col+` = $1 LIMIT 1`, arg).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, ErrMemberUserNotFound
	}
	return id, err
}

// UserBySeq maps a profile's integer seq (used in management URLs) back to
// its uuid.
func (r *ShopMemberRepository) UserBySeq(ctx context.Context, seq int64) (uuid.UUID, error) {
	var id uuid.UUID
	err := r.pool.QueryRow(ctx, `SELECT id FROM profiles WHERE seq = $1`, seq).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, ErrMemberUserNotFound
	}
	return id, err
}

const memberSelect = `
	SELECT slp.id, slp.shop_id, slp.user_id, COALESCE(p.seq, 0),
	       COALESCE(p.name, ''), COALESCE(p.email, ''), COALESCE(p.phone, ''),
	       slp.member_type, slp.can_live, slp.status, slp.approved_at, slp.created_at
	FROM shop_live_permissions slp
	LEFT JOIN profiles p ON p.id = slp.user_id`

func scanMember(row pgx.Row, m *ShopMember) error {
	return row.Scan(&m.ID, &m.ShopID, &m.UserID, &m.UserSeq, &m.Name, &m.Email,
		&m.Phone, &m.MemberType, &m.CanLive, &m.Status, &m.ApprovedAt, &m.CreatedAt)
}

// ListMembers returns every member row for a shop (any status).
func (r *ShopMemberRepository) ListMembers(ctx context.Context, shopID uuid.UUID) ([]ShopMember, error) {
	rows, err := r.pool.Query(ctx, memberSelect+` WHERE slp.shop_id = $1 ORDER BY slp.created_at DESC`, shopID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]ShopMember, 0)
	for rows.Next() {
		var m ShopMember
		if err := scanMember(rows, &m); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// UpsertMember inserts or updates a member row, returning the resulting row.
// The owner self-approves, so callers typically pass status='approved'.
func (r *ShopMemberRepository) UpsertMember(ctx context.Context, shopID, userID uuid.UUID, memberType string, canLive bool, status string, approver uuid.UUID) (*ShopMember, error) {
	var approvedAt *time.Time
	if status == "approved" {
		now := time.Now()
		approvedAt = &now
	}
	const q = `
		INSERT INTO shop_live_permissions
		  (shop_id, user_id, member_type, can_live, status, invited_by, approved_by, approved_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		ON CONFLICT (shop_id, user_id) DO UPDATE SET
		  member_type = EXCLUDED.member_type,
		  can_live    = EXCLUDED.can_live,
		  status      = EXCLUDED.status,
		  approved_by = EXCLUDED.approved_by,
		  approved_at = EXCLUDED.approved_at,
		  updated_at  = NOW()
		RETURNING id`
	var id uuid.UUID
	var approverArg any
	if approver != uuid.Nil {
		approverArg = approver
	}
	if err := r.pool.QueryRow(ctx, q,
		shopID, userID, memberType, canLive, status, approverArg, approverArg, approvedAt).Scan(&id); err != nil {
		return nil, err
	}
	return r.GetMember(ctx, shopID, userID)
}

// UpdateStatus changes a member's status/can_live (approve / reject / toggle).
func (r *ShopMemberRepository) UpdateStatus(ctx context.Context, shopID, userID uuid.UUID, status string, canLive bool, approver uuid.UUID) (*ShopMember, error) {
	var approvedAt *time.Time
	if status == "approved" {
		now := time.Now()
		approvedAt = &now
	}
	tag, err := r.pool.Exec(ctx,
		`UPDATE shop_live_permissions
		    SET status = $3, can_live = $4, approved_by = $5, approved_at = $6, updated_at = NOW()
		  WHERE shop_id = $1 AND user_id = $2`,
		shopID, userID, status, canLive, nullableUUID(approver), approvedAt)
	if err != nil {
		return nil, err
	}
	if tag.RowsAffected() == 0 {
		return nil, ErrMemberNotFound
	}
	return r.GetMember(ctx, shopID, userID)
}

func (r *ShopMemberRepository) RemoveMember(ctx context.Context, shopID, userID uuid.UUID) error {
	tag, err := r.pool.Exec(ctx,
		`DELETE FROM shop_live_permissions WHERE shop_id = $1 AND user_id = $2`, shopID, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrMemberNotFound
	}
	return nil
}

func (r *ShopMemberRepository) GetMember(ctx context.Context, shopID, userID uuid.UUID) (*ShopMember, error) {
	var m ShopMember
	if err := scanMember(r.pool.QueryRow(ctx, memberSelect+` WHERE slp.shop_id = $1 AND slp.user_id = $2`, shopID, userID), &m); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrMemberNotFound
		}
		return nil, err
	}
	return &m, nil
}

func nullableUUID(id uuid.UUID) any {
	if id == uuid.Nil {
		return nil
	}
	return id
}
