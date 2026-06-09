package shops

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tropia/backend/internal/auth"
	"github.com/tropia/backend/internal/httpx"
)

type Shop struct {
	ID             uuid.UUID `json:"id"`
	SellerID       uuid.UUID `json:"seller_id"`
	Name           string    `json:"name"`
	Slug           string    `json:"slug"`
	Description    *string   `json:"description,omitempty"`
	LogoURL        *string   `json:"logo_url,omitempty"`
	BannerURL      *string   `json:"banner_url,omitempty"`
	Rating         float64   `json:"rating"`
	TotalSales     int       `json:"total_sales"`
	FollowerCount  int       `json:"follower_count"`
	IsActive       bool      `json:"is_active"`
	CreatedAt      time.Time `json:"created_at"`
}

type Repository struct{ pool *pgxpool.Pool }

func NewRepository(pool *pgxpool.Pool) *Repository { return &Repository{pool: pool} }

var ErrNotFound = errors.New("shop not found")

func (r *Repository) ListActive(ctx context.Context, limit, offset int) ([]Shop, error) {
	const q = `
		SELECT id, seller_id, name, slug, description, logo_url, banner_url,
		       rating, total_sales, follower_count, is_active, created_at
		FROM shops
		WHERE is_active = TRUE
		ORDER BY total_sales DESC
		LIMIT $1 OFFSET $2
	`
	rows, err := r.pool.Query(ctx, q, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]Shop, 0)
	for rows.Next() {
		var s Shop
		if err := scan(rows, &s); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

// FindBySlug - accepts slug, shop ID UUID, or seller_id UUID (mirrors Node.js fuzziness)
func (r *Repository) FindBySlug(ctx context.Context, slugOrID string) (*Shop, error) {
	var q string
	var arg any
	if id, err := uuid.Parse(slugOrID); err == nil {
		q = `SELECT id, seller_id, name, slug, description, logo_url, banner_url,
		       rating, total_sales, follower_count, is_active, created_at
		    FROM shops WHERE id = $1 OR seller_id = $1 LIMIT 1`
		arg = id
	} else {
		q = `SELECT id, seller_id, name, slug, description, logo_url, banner_url,
		       rating, total_sales, follower_count, is_active, created_at
		    FROM shops WHERE slug = $1 LIMIT 1`
		arg = slugOrID
	}
	var s Shop
	if err := scan(r.pool.QueryRow(ctx, q, arg), &s); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &s, nil
}

func (r *Repository) FindBySellerID(ctx context.Context, sellerID uuid.UUID) (*Shop, error) {
	const q = `SELECT id, seller_id, name, slug, description, logo_url, banner_url,
		       rating, total_sales, follower_count, is_active, created_at
		FROM shops WHERE seller_id = $1`
	var s Shop
	if err := scan(r.pool.QueryRow(ctx, q, sellerID), &s); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &s, nil
}

func (r *Repository) Create(ctx context.Context, sellerID uuid.UUID, name, slug, desc string) (*Shop, error) {
	// New shops are created WITHOUT a logo (logo_url NULL): the client draws a
	// name-based initials avatar locally (InitialsAvatar) so cards/videos show
	// an avatar from day one without depending on any external image service.
	// (We used to default to a ui-avatars.com URL, but its broken CORS header
	// blocked the image on Flutter Web.) The seller can upload a real logo later.
	const q = `
		INSERT INTO shops (seller_id, name, slug, description)
		VALUES ($1, $2, $3, NULLIF($4, ''))
		RETURNING id, seller_id, name, slug, description, logo_url, banner_url,
		          rating, total_sales, follower_count, is_active, created_at
	`
	var s Shop
	if err := scan(r.pool.QueryRow(ctx, q, sellerID, name, slug, desc), &s); err != nil {
		return nil, err
	}
	return &s, nil
}

func (r *Repository) Update(ctx context.Context, id uuid.UUID, name, slug, desc *string) (*Shop, error) {
	const q = `
		UPDATE shops SET
			name = COALESCE($2, name),
			slug = COALESCE($3, slug),
			description = COALESCE($4, description)
		WHERE id = $1
		RETURNING id, seller_id, name, slug, description, logo_url, banner_url,
		          rating, total_sales, follower_count, is_active, created_at
	`
	var s Shop
	if err := scan(r.pool.QueryRow(ctx, q, id, name, slug, desc), &s); err != nil {
		return nil, err
	}
	return &s, nil
}

func (r *Repository) Follow(ctx context.Context, userID, shopID uuid.UUID) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO shop_follows (user_id, shop_id) VALUES ($1, $2)
		 ON CONFLICT DO NOTHING`,
		userID, shopID)
	if err == nil {
		_, _ = r.pool.Exec(ctx, `UPDATE shops SET follower_count = follower_count + 1 WHERE id = $1`, shopID)
	}
	return err
}

func (r *Repository) Unfollow(ctx context.Context, userID, shopID uuid.UUID) error {
	res, err := r.pool.Exec(ctx, `DELETE FROM shop_follows WHERE user_id = $1 AND shop_id = $2`, userID, shopID)
	if err == nil && res.RowsAffected() > 0 {
		_, _ = r.pool.Exec(ctx, `UPDATE shops SET follower_count = GREATEST(0, follower_count - 1) WHERE id = $1`, shopID)
	}
	return err
}

func (r *Repository) IsFollowing(ctx context.Context, userID, shopID uuid.UUID) (bool, error) {
	var n int
	err := r.pool.QueryRow(ctx, `SELECT COUNT(1) FROM shop_follows WHERE user_id = $1 AND shop_id = $2`, userID, shopID).Scan(&n)
	return n > 0, err
}

func (r *Repository) ListFollowing(ctx context.Context, userID uuid.UUID, limit, offset int) ([]Shop, error) {
	const q = `
		SELECT s.id, s.seller_id, s.name, s.slug, s.description, s.logo_url, s.banner_url,
		       s.rating, s.total_sales, s.follower_count, s.is_active, s.created_at
		FROM shops s JOIN shop_follows f ON f.shop_id = s.id
		WHERE f.user_id = $1
		ORDER BY f.followed_at DESC
		LIMIT $2 OFFSET $3
	`
	rows, err := r.pool.Query(ctx, q, userID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]Shop, 0)
	for rows.Next() {
		var s Shop
		if err := scan(rows, &s); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

type rowScanner interface {
	Scan(...any) error
}

func scan(row rowScanner, s *Shop) error {
	return row.Scan(
		&s.ID, &s.SellerID, &s.Name, &s.Slug, &s.Description, &s.LogoURL, &s.BannerURL,
		&s.Rating, &s.TotalSales, &s.FollowerCount, &s.IsActive, &s.CreatedAt,
	)
}

// ============================================================================
// Handler
// ============================================================================

type Handler struct{ repo *Repository }

func NewHandler(repo *Repository) *Handler { return &Handler{repo: repo} }

func (h *Handler) Register(r *gin.RouterGroup, authMw, sellerMw gin.HandlerFunc, optAuthMw gin.HandlerFunc) {
	r.GET("", h.list)
	r.GET("/:slug", optAuthMw, h.getBySlug)

	authed := r.Group("/", authMw)
	authed.GET("/me/info", h.myShop)
	authed.GET("/me/following", h.following)
	authed.GET("/:slug/follow-status", h.followStatus)
	authed.POST("/:slug/follow", h.follow)
	authed.DELETE("/:slug/follow", h.unfollow)

	sellerOnly := r.Group("/", authMw, sellerMw)
	sellerOnly.POST("", h.create)
	sellerOnly.PATCH("/:slug", h.update)
}

func (h *Handler) list(c *gin.Context) {
	shops, err := h.repo.ListActive(c.Request.Context(), 50, 0)
	if err != nil {
		c.Error(httpx.NewInternal("list shops", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"shops": shops})
}

func (h *Handler) getBySlug(c *gin.Context) {
	shop, err := h.repo.FindBySlug(c.Request.Context(), c.Param("slug"))
	if err != nil {
		c.Error(httpx.NewNotFound("shop not found"))
		return
	}
	out := gin.H{"shop": shop}
	if claims, ok := auth.ClaimsFrom(c); ok {
		uid, _ := uuid.Parse(claims.UserID)
		following, _ := h.repo.IsFollowing(c.Request.Context(), uid, shop.ID)
		out["is_following"] = following
	}
	c.JSON(http.StatusOK, out)
}

func (h *Handler) myShop(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	shop, err := h.repo.FindBySellerID(c.Request.Context(), uid)
	if err != nil {
		c.JSON(http.StatusOK, gin.H{"shop": nil})
		return
	}
	c.JSON(http.StatusOK, gin.H{"shop": shop})
}

func (h *Handler) following(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	// Pagination params — caller (Flutter ShopRepository) sends
	// offset+limit. Defaults match the historical 50/0 values.
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}
	shops, err := h.repo.ListFollowing(c.Request.Context(), uid, limit, offset)
	if err != nil {
		c.Error(httpx.NewInternal("list following", err))
		return
	}
	// Response shape contract the Flutter side parses: `data` (array of
	// shops) + `count` (total length). Was returning `{shops: [...]}` so
	// the frontend's `(d['data'] as List)` crashed in the try/catch and
	// silently returned an empty follow set — every live card flashed
	// "+ Theo dõi" on reload even for shops the user already follows.
	c.JSON(http.StatusOK, gin.H{
		"data":  shops,
		"count": len(shops),
	})
}

type createShopReq struct {
	Name        string `json:"name" binding:"required,min=1,max=200"`
	Slug        string `json:"slug" binding:"omitempty,max=200"`
	Description string `json:"description"`
}

func (h *Handler) create(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	sellerID, _ := uuid.Parse(claims.UserID)
	var req createShopReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	slug := req.Slug
	if slug == "" {
		slug = slugify(req.Name) + "-" + sellerID.String()[:8]
	}
	shop, err := h.repo.Create(c.Request.Context(), sellerID, req.Name, slug, req.Description)
	if err != nil {
		if strings.Contains(err.Error(), "unique") {
			c.Error(httpx.NewConflict("shop already exists or slug taken"))
			return
		}
		c.Error(httpx.NewInternal("create shop", err))
		return
	}
	c.JSON(http.StatusCreated, gin.H{"shop": shop})
}

func (h *Handler) update(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	sellerID, _ := uuid.Parse(claims.UserID)
	existing, err := h.repo.FindBySlug(c.Request.Context(), c.Param("slug"))
	if err != nil {
		c.Error(httpx.NewNotFound("shop not found"))
		return
	}
	if existing.SellerID != sellerID && claims.Role != auth.RoleAdmin {
		c.Error(httpx.NewForbidden("not your shop"))
		return
	}
	var body struct {
		Name        *string `json:"name"`
		Slug        *string `json:"slug"`
		Description *string `json:"description"`
	}
	_ = c.ShouldBindJSON(&body)
	shop, err := h.repo.Update(c.Request.Context(), existing.ID, body.Name, body.Slug, body.Description)
	if err != nil {
		c.Error(httpx.NewInternal("update shop", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"shop": shop})
}

func (h *Handler) followStatus(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	shop, err := h.repo.FindBySlug(c.Request.Context(), c.Param("slug"))
	if err != nil {
		c.Error(httpx.NewNotFound("shop not found"))
		return
	}
	following, _ := h.repo.IsFollowing(c.Request.Context(), uid, shop.ID)
	c.JSON(http.StatusOK, gin.H{"followed": following})
}

func (h *Handler) follow(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	shop, err := h.repo.FindBySlug(c.Request.Context(), c.Param("slug"))
	if err != nil {
		c.Error(httpx.NewNotFound("shop not found"))
		return
	}
	_ = h.repo.Follow(c.Request.Context(), uid, shop.ID)
	c.JSON(http.StatusOK, gin.H{"followed": true})
}

func (h *Handler) unfollow(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	shop, err := h.repo.FindBySlug(c.Request.Context(), c.Param("slug"))
	if err != nil {
		c.Error(httpx.NewNotFound("shop not found"))
		return
	}
	_ = h.repo.Unfollow(c.Request.Context(), uid, shop.ID)
	c.JSON(http.StatusOK, gin.H{"followed": false})
}

func slugify(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	var b strings.Builder
	prevDash := false
	for _, r := range s {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			b.WriteRune(r)
			prevDash = false
		case r == ' ', r == '-', r == '_':
			if !prevDash {
				b.WriteRune('-')
				prevDash = true
			}
		}
	}
	return strings.Trim(b.String(), "-")
}
