package commerce

import (
	"context"
	"errors"
	"math"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tropia/backend/internal/httpx"
)

type Coupon struct {
	ID            uuid.UUID  `json:"id"`
	Code          string     `json:"code"`
	DiscountType  string     `json:"discount_type"` // percent | fixed
	DiscountValue float64    `json:"discount_value"`
	MinOrderValue int        `json:"min_order_value"`
	MaxDiscount   *int       `json:"max_discount,omitempty"`
	MaxUses       *int       `json:"max_uses,omitempty"`
	UsedCount     int        `json:"used_count"`
	ExpiresAt     time.Time  `json:"expires_at"`
	IsActive      bool       `json:"is_active"`
	SessionID     *uuid.UUID `json:"session_id,omitempty"`
	CreatedBy     uuid.UUID  `json:"created_by"`
	CreatedAt     time.Time  `json:"created_at"`
}

type CouponRepository struct{ pool *pgxpool.Pool }

func NewCouponRepository(pool *pgxpool.Pool) *CouponRepository {
	return &CouponRepository{pool: pool}
}

var ErrCouponNotFound = errors.New("coupon not found")

func (r *CouponRepository) FindByCode(ctx context.Context, code string) (*Coupon, error) {
	const q = `
		SELECT id, code, discount_type, discount_value, min_order_value, max_discount, max_uses,
		       used_count, expires_at, is_active, session_id, created_by, created_at
		FROM coupons WHERE code = $1
	`
	var c Coupon
	if err := scanCoupon(r.pool.QueryRow(ctx, q, strings.ToUpper(code)), &c); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrCouponNotFound
		}
		return nil, err
	}
	return &c, nil
}

func (r *CouponRepository) UserHasUsed(ctx context.Context, couponID, userID uuid.UUID) (bool, error) {
	var n int
	err := r.pool.QueryRow(ctx,
		`SELECT COUNT(1) FROM coupon_usages WHERE coupon_id = $1 AND user_id = $2`,
		couponID, userID).Scan(&n)
	return n > 0, err
}

func (r *CouponRepository) RecordUsage(ctx context.Context, couponID, userID, orderID uuid.UUID) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	_, err = tx.Exec(ctx,
		`INSERT INTO coupon_usages (coupon_id, user_id, order_id) VALUES ($1, $2, $3)`,
		couponID, userID, orderID)
	if err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `SELECT increment_coupon_uses($1)`, couponID)
	if err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (r *CouponRepository) ListPlatformActive(ctx context.Context) ([]Coupon, error) {
	const q = `
		SELECT id, code, discount_type, discount_value, min_order_value, max_discount, max_uses,
		       used_count, expires_at, is_active, session_id, created_by, created_at
		FROM coupons
		WHERE session_id IS NULL AND is_active = TRUE AND expires_at > NOW()
		ORDER BY created_at DESC
	`
	rows, err := r.pool.Query(ctx, q)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]Coupon, 0)
	for rows.Next() {
		var c Coupon
		if err := scanCoupon(rows, &c); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// ListByShop returns active, non-expired coupons created by the seller
// that owns this shop. Joins coupons → live_sessions → shops so a shop's
// coupons surface in the cart's "Voucher của Shop" row even after the
// originating live session ended — buyers expect to keep using a code
// they saved during a live broadcast. There is no `coupons.shop_id`
// column; we resolve ownership via the session's seller.
func (r *CouponRepository) ListByShop(ctx context.Context, shopID uuid.UUID) ([]Coupon, error) {
	const q = `
		SELECT c.id, c.code, c.discount_type, c.discount_value, c.min_order_value, c.max_discount, c.max_uses,
		       c.used_count, c.expires_at, c.is_active, c.session_id, c.created_by, c.created_at
		FROM coupons c
		JOIN live_sessions ls ON ls.id = c.session_id
		JOIN shops s          ON s.seller_id = ls.seller_id
		WHERE s.id = $1 AND c.is_active = TRUE AND c.expires_at > NOW()
		ORDER BY c.created_at DESC
	`
	rows, err := r.pool.Query(ctx, q, shopID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]Coupon, 0)
	for rows.Next() {
		var c Coupon
		if err := scanCoupon(rows, &c); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (r *CouponRepository) ListBySession(ctx context.Context, sessionID uuid.UUID) ([]Coupon, error) {
	const q = `
		SELECT id, code, discount_type, discount_value, min_order_value, max_discount, max_uses,
		       used_count, expires_at, is_active, session_id, created_by, created_at
		FROM coupons WHERE session_id = $1 AND is_active = TRUE
		ORDER BY created_at DESC
	`
	rows, err := r.pool.Query(ctx, q, sessionID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]Coupon, 0)
	for rows.Next() {
		var c Coupon
		if err := scanCoupon(rows, &c); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (r *CouponRepository) Create(ctx context.Context, code, discountType string, value, minOrder float64, maxDiscount, maxUses *int, expires time.Time, sessionID *uuid.UUID, createdBy uuid.UUID) (*Coupon, error) {
	const q = `
		INSERT INTO coupons (code, discount_type, discount_value, min_order_value, max_discount, max_uses, expires_at, session_id, created_by)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		RETURNING id, code, discount_type, discount_value, min_order_value, max_discount, max_uses,
		          used_count, expires_at, is_active, session_id, created_by, created_at
	`
	var c Coupon
	if err := scanCoupon(r.pool.QueryRow(ctx, q,
		strings.ToUpper(code), discountType, value, int(minOrder), maxDiscount, maxUses, expires, sessionID, createdBy,
	), &c); err != nil {
		return nil, err
	}
	return &c, nil
}

func scanCoupon(row interface{ Scan(...any) error }, c *Coupon) error {
	return row.Scan(
		&c.ID, &c.Code, &c.DiscountType, &c.DiscountValue, &c.MinOrderValue, &c.MaxDiscount, &c.MaxUses,
		&c.UsedCount, &c.ExpiresAt, &c.IsActive, &c.SessionID, &c.CreatedBy, &c.CreatedAt,
	)
}

// ============================================================================
// Apply logic
// ============================================================================

type ApplyResult struct {
	Coupon         *Coupon
	DiscountAmount int
}

// ApplyCoupon validates and computes discount.
//
// Validation errors carry a `details` payload of the form
//
//	{"coupon_code": "<upper-case code>", "reason": "<machine-readable tag>"}
//
// so the client can identify which coupon failed (a checkout request may
// send several at once) and auto-unapply it instead of just showing the
// raw English message.
func ApplyCoupon(ctx context.Context, r *CouponRepository, code string, userID uuid.UUID, orderTotal int) (*ApplyResult, error) {
	upper := strings.ToUpper(code)
	failure := func(reason, msg string) *httpx.AppError {
		return httpx.NewValidation(msg, map[string]string{
			"coupon_code": upper,
			"reason":      reason,
		})
	}
	coupon, err := r.FindByCode(ctx, code)
	if err != nil {
		return nil, failure("not_found", "coupon not found")
	}
	if !coupon.IsActive {
		return nil, failure("inactive", "coupon inactive")
	}
	if coupon.ExpiresAt.Before(time.Now()) {
		return nil, failure("expired", "coupon expired")
	}
	if coupon.MaxUses != nil && coupon.UsedCount >= *coupon.MaxUses {
		return nil, failure("limit_reached", "coupon usage limit reached")
	}
	if orderTotal < coupon.MinOrderValue {
		return nil, failure("min_order", "order total below minimum")
	}
	used, _ := r.UserHasUsed(ctx, coupon.ID, userID)
	if used {
		return nil, failure("already_used", "coupon already used")
	}
	var discount int
	if coupon.DiscountType == "percent" {
		discount = int(math.Floor(float64(orderTotal) * coupon.DiscountValue / 100))
		if coupon.MaxDiscount != nil && discount > *coupon.MaxDiscount {
			discount = *coupon.MaxDiscount
		}
	} else {
		discount = int(coupon.DiscountValue)
	}
	if discount > orderTotal {
		discount = orderTotal
	}
	return &ApplyResult{Coupon: coupon, DiscountAmount: discount}, nil
}
