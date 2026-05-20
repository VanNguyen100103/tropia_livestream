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

	"github.com/tropia/backend-go/internal/httpx"
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
func ApplyCoupon(ctx context.Context, r *CouponRepository, code string, userID uuid.UUID, orderTotal int) (*ApplyResult, error) {
	coupon, err := r.FindByCode(ctx, code)
	if err != nil {
		return nil, httpx.NewValidation("coupon not found", nil)
	}
	if !coupon.IsActive {
		return nil, httpx.NewValidation("coupon inactive", nil)
	}
	if coupon.ExpiresAt.Before(time.Now()) {
		return nil, httpx.NewValidation("coupon expired", nil)
	}
	if coupon.MaxUses != nil && coupon.UsedCount >= *coupon.MaxUses {
		return nil, httpx.NewValidation("coupon usage limit reached", nil)
	}
	if orderTotal < coupon.MinOrderValue {
		return nil, httpx.NewValidation("order total below minimum", nil)
	}
	used, _ := r.UserHasUsed(ctx, coupon.ID, userID)
	if used {
		return nil, httpx.NewValidation("coupon already used", nil)
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
