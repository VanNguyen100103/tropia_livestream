package admin

import (
	"context"
	"errors"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrUserNotFound is returned when the target profile id doesn't exist.
var ErrUserNotFound = errors.New("user not found")

// Repository wraps the pool for admin-only writes: changing a user's role and
// crediting loyalty points. Self-contained (no dependency on the auth repo) so
// admin concerns stay in one place.
type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository { return &Repository{pool: pool} }

// RoleChange is the before/after of a role update plus the user's identity for
// the audit row + response.
type RoleChange struct {
	ID      uuid.UUID
	Email   string
	Name    string
	OldRole string
	NewRole string
}

// SetRole updates profiles.role and revokes the user's refresh tokens in one
// transaction, so the new privilege level takes effect on their next login.
// (Their current access token still carries the old role until it expires —
// the access TTL is short.) Returns ErrUserNotFound if no profile has that id.
func (r *Repository) SetRole(ctx context.Context, id uuid.UUID, newRole string) (*RoleChange, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	// CTE snapshots the pre-update role; the UPDATE returns it alongside the
	// (unchanged) email/name so we get before+after in one round-trip.
	var oldRole, email, name string
	err = tx.QueryRow(ctx, `
		WITH old AS (SELECT id, role, email, name FROM profiles WHERE id = $1)
		UPDATE profiles p
		   SET role = $2
		  FROM old
		 WHERE p.id = old.id
		RETURNING old.role, p.email, p.name
	`, id, newRole).Scan(&oldRole, &email, &name)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrUserNotFound
	}
	if err != nil {
		return nil, err
	}

	if _, err = tx.Exec(ctx,
		`UPDATE refresh_tokens SET revoked = TRUE WHERE user_id = $1`, id); err != nil {
		return nil, err
	}
	if err = tx.Commit(ctx); err != nil {
		return nil, err
	}
	return &RoleChange{ID: id, Email: email, Name: name, OldRole: oldRole, NewRole: newRole}, nil
}

// LoyaltyCredit is the outcome of crediting points: the amount added and the
// resulting running balance.
type LoyaltyCredit struct {
	UserID  uuid.UUID
	Email   string
	Added   int
	Balance int
}

// AddLoyalty credits `delta` points to a user's loyalty balance, creating the
// row on first credit (upsert). Returns ErrUserNotFound if the profile doesn't
// exist — checked up front so a missing user is a clean 404 rather than a raw
// foreign-key violation from the insert.
func (r *Repository) AddLoyalty(ctx context.Context, id uuid.UUID, delta int) (*LoyaltyCredit, error) {
	var email string
	err := r.pool.QueryRow(ctx, `SELECT email FROM profiles WHERE id = $1`, id).Scan(&email)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrUserNotFound
	}
	if err != nil {
		return nil, err
	}

	var balance int
	err = r.pool.QueryRow(ctx, `
		INSERT INTO user_loyalty (user_id, points)
		VALUES ($1, $2)
		ON CONFLICT (user_id) DO UPDATE
			SET points     = user_loyalty.points + EXCLUDED.points,
			    updated_at = NOW()
		RETURNING points
	`, id, delta).Scan(&balance)
	if err != nil {
		return nil, err
	}
	return &LoyaltyCredit{UserID: id, Email: email, Added: delta, Balance: balance}, nil
}
