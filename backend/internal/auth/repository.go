package auth

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrNotFound = errors.New("not found")

type Profile struct {
	ID                   uuid.UUID
	Email                string
	PasswordHash         *string
	Name                 string
	Phone                *string
	ShopName             *string
	Role                 Role
	AvatarURL            *string
	GoogleID             *string
	Status               *string
	EmailVerified        bool
	FailedLoginAttempts  int
	LockedUntil          *time.Time
	PasswordResetToken   *string
	PasswordResetExpires *time.Time
	CreatedAt            time.Time
}

type RefreshTokenRow struct {
	ID        uuid.UUID
	UserID    uuid.UUID
	TokenHash string
	Family    uuid.UUID
	ExpiresAt time.Time
	Revoked   bool
}

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

// ---------- Profile ----------

func (r *Repository) EmailExists(ctx context.Context, email string) (bool, error) {
	var n int
	err := r.pool.QueryRow(ctx, `SELECT COUNT(1) FROM profiles WHERE email = $1`, email).Scan(&n)
	return n > 0, err
}

func (r *Repository) CreateProfile(ctx context.Context, email, passwordHash, name string, phone, shopName *string, role Role) (*Profile, error) {
	const q = `
		INSERT INTO profiles (email, password_hash, name, phone, shop_name, role, email_verified)
		VALUES ($1, $2, $3, $4, $5, $6, FALSE)
		RETURNING id, email, password_hash, name, phone, shop_name, role, avatar_url, google_id, status,
		          email_verified, failed_login_attempts, locked_until, created_at
	`
	var p Profile
	row := r.pool.QueryRow(ctx, q, email, passwordHash, name, phone, shopName, role)
	if err := scanProfile(row, &p); err != nil {
		return nil, err
	}
	return &p, nil
}

func (r *Repository) CreateGoogleProfile(ctx context.Context, email, name, googleID, avatarURL string) (*Profile, error) {
	const q = `
		INSERT INTO profiles (email, name, google_id, avatar_url, role, email_verified)
		VALUES ($1, $2, $3, $4, 'buyer', TRUE)
		RETURNING id, email, password_hash, name, phone, shop_name, role, avatar_url, google_id, status,
		          email_verified, failed_login_attempts, locked_until, created_at
	`
	var p Profile
	row := r.pool.QueryRow(ctx, q, email, name, googleID, avatarURL)
	if err := scanProfile(row, &p); err != nil {
		return nil, err
	}
	return &p, nil
}

func (r *Repository) FindByEmail(ctx context.Context, email string) (*Profile, error) {
	const q = `
		SELECT id, email, password_hash, name, phone, shop_name, role, avatar_url, google_id, status,
		       email_verified, failed_login_attempts, locked_until, created_at
		FROM profiles WHERE email = $1
	`
	var p Profile
	row := r.pool.QueryRow(ctx, q, email)
	if err := scanProfile(row, &p); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &p, nil
}

// FindByPhone resolves a profile by phone number — used by the spec
// `POST /api/login` where `username` is the user's SĐT. Returns ErrNotFound
// when no profile has that phone.
func (r *Repository) FindByPhone(ctx context.Context, phone string) (*Profile, error) {
	const q = `
		SELECT id, email, password_hash, name, phone, shop_name, role, avatar_url, google_id, status,
		       email_verified, failed_login_attempts, locked_until, created_at
		FROM profiles WHERE phone = $1
	`
	var p Profile
	row := r.pool.QueryRow(ctx, q, phone)
	if err := scanProfile(row, &p); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &p, nil
}

// SeqByID returns the integer `seq` of a profile (the spec exposes user
// ids as integers, e.g. host.id / user.id). 0 if not found.
func (r *Repository) SeqByID(ctx context.Context, id uuid.UUID) (int64, error) {
	var seq int64
	err := r.pool.QueryRow(ctx, `SELECT COALESCE(seq, 0) FROM profiles WHERE id = $1`, id).Scan(&seq)
	return seq, err
}

func (r *Repository) FindByID(ctx context.Context, id uuid.UUID) (*Profile, error) {
	const q = `
		SELECT id, email, password_hash, name, phone, shop_name, role, avatar_url, google_id, status,
		       email_verified, failed_login_attempts, locked_until, created_at
		FROM profiles WHERE id = $1
	`
	var p Profile
	row := r.pool.QueryRow(ctx, q, id)
	if err := scanProfile(row, &p); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &p, nil
}

func (r *Repository) MarkEmailVerified(ctx context.Context, id uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `UPDATE profiles SET email_verified = TRUE WHERE id = $1`, id)
	return err
}

func (r *Repository) IncrementFailedLogin(ctx context.Context, id uuid.UUID) (int, error) {
	const q = `
		UPDATE profiles SET failed_login_attempts = failed_login_attempts + 1
		WHERE id = $1
		RETURNING failed_login_attempts
	`
	var n int
	err := r.pool.QueryRow(ctx, q, id).Scan(&n)
	return n, err
}

func (r *Repository) LockUntil(ctx context.Context, id uuid.UUID, until time.Time) error {
	_, err := r.pool.Exec(ctx, `UPDATE profiles SET locked_until = $2 WHERE id = $1`, id, until)
	return err
}

func (r *Repository) ResetLoginCounters(ctx context.Context, id uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `UPDATE profiles SET failed_login_attempts = 0, locked_until = NULL WHERE id = $1`, id)
	return err
}

func (r *Repository) SetPasswordReset(ctx context.Context, id uuid.UUID, tokenHash string, expires time.Time) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE profiles SET password_reset_token = $2, password_reset_expires = $3 WHERE id = $1`,
		id, tokenHash, expires)
	return err
}

func (r *Repository) FindByPasswordResetToken(ctx context.Context, tokenHash string) (*Profile, error) {
	const q = `
		SELECT id, email, password_hash, name, phone, shop_name, role, avatar_url, google_id, status,
		       email_verified, failed_login_attempts, locked_until, created_at
		FROM profiles
		WHERE password_reset_token = $1 AND password_reset_expires > NOW()
	`
	var p Profile
	row := r.pool.QueryRow(ctx, q, tokenHash)
	if err := scanProfile(row, &p); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &p, nil
}

func (r *Repository) UpdatePassword(ctx context.Context, id uuid.UUID, newHash string) error {
	const q = `
		UPDATE profiles
		SET password_hash = $2,
		    password_reset_token = NULL,
		    password_reset_expires = NULL,
		    failed_login_attempts = 0,
		    locked_until = NULL
		WHERE id = $1
	`
	_, err := r.pool.Exec(ctx, q, id, newHash)
	return err
}

func (r *Repository) UpdateGoogleID(ctx context.Context, id uuid.UUID, googleID, avatarURL string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE profiles SET google_id = COALESCE(google_id, $2), avatar_url = COALESCE(avatar_url, $3) WHERE id = $1`,
		id, googleID, avatarURL)
	return err
}

// ---------- Refresh tokens ----------

func (r *Repository) InsertRefreshToken(ctx context.Context, userID uuid.UUID, tokenHash string, family uuid.UUID, expiresAt time.Time) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO refresh_tokens (user_id, token_hash, family, expires_at) VALUES ($1, $2, $3, $4)`,
		userID, tokenHash, family, expiresAt)
	return err
}

func (r *Repository) FindRefreshToken(ctx context.Context, tokenHash string) (*RefreshTokenRow, error) {
	const q = `
		SELECT id, user_id, token_hash, family, expires_at, revoked
		FROM refresh_tokens WHERE token_hash = $1
	`
	var t RefreshTokenRow
	row := r.pool.QueryRow(ctx, q, tokenHash)
	err := row.Scan(&t.ID, &t.UserID, &t.TokenHash, &t.Family, &t.ExpiresAt, &t.Revoked)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &t, nil
}

func (r *Repository) RevokeRefreshToken(ctx context.Context, tokenHash string) error {
	_, err := r.pool.Exec(ctx, `UPDATE refresh_tokens SET revoked = TRUE WHERE token_hash = $1`, tokenHash)
	return err
}

func (r *Repository) RevokeFamily(ctx context.Context, family uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `UPDATE refresh_tokens SET revoked = TRUE WHERE family = $1`, family)
	return err
}

func (r *Repository) RevokeAllForUser(ctx context.Context, userID uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `UPDATE refresh_tokens SET revoked = TRUE WHERE user_id = $1`, userID)
	return err
}

// ---------- Shops (helper for seller registration) ----------

func (r *Repository) CreateShopForSeller(ctx context.Context, sellerID uuid.UUID, name, slug string) error {
	// Create the shop WITHOUT a logo (logo_url NULL): the client draws a
	// name-based initials avatar locally (InitialsAvatar) so cards/videos show
	// an avatar right away without an external image service. (A ui-avatars.com
	// default used to live here but its broken CORS header blocked the image on
	// Flutter Web.) The seller can upload a real logo later.
	_, err := r.pool.Exec(ctx,
		`INSERT INTO shops (seller_id, name, slug, is_active)
		 VALUES ($1, $2, $3, TRUE)
		 ON CONFLICT (seller_id) DO NOTHING`,
		sellerID, name, slug)
	return err
}

// ---------- helpers ----------

type rowScanner interface {
	Scan(dest ...any) error
}

func scanProfile(row rowScanner, p *Profile) error {
	return row.Scan(
		&p.ID, &p.Email, &p.PasswordHash, &p.Name, &p.Phone, &p.ShopName,
		&p.Role, &p.AvatarURL, &p.GoogleID, &p.Status,
		&p.EmailVerified, &p.FailedLoginAttempts, &p.LockedUntil, &p.CreatedAt,
	)
}
