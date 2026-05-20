package catalog

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tropia/backend/internal/cache"
	"github.com/tropia/backend/internal/httpx"
)

type Category struct {
	ID        uuid.UUID  `json:"id"`
	Name      string     `json:"name"`
	Slug      string     `json:"slug"`
	ParentID  *uuid.UUID `json:"parent_id,omitempty"`
	ImageURL  *string    `json:"image_url,omitempty"`
	SortOrder int        `json:"sort_order"`
	IsActive  bool       `json:"is_active"`
	CreatedAt time.Time  `json:"created_at"`
}

type CategoryRepository struct{ pool *pgxpool.Pool }

func NewCategoryRepository(pool *pgxpool.Pool) *CategoryRepository {
	return &CategoryRepository{pool: pool}
}

var ErrCategoryNotFound = errors.New("category not found")

func (r *CategoryRepository) ListAll(ctx context.Context) ([]Category, error) {
	const q = `
		SELECT id, name, slug, parent_id, image_url, sort_order, is_active, created_at
		FROM categories WHERE is_active = TRUE
		ORDER BY sort_order, name
	`
	rows, err := r.pool.Query(ctx, q)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]Category, 0)
	for rows.Next() {
		var c Category
		if err := scanCategory(rows, &c); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (r *CategoryRepository) FindBySlug(ctx context.Context, slug string) (*Category, error) {
	const q = `SELECT id, name, slug, parent_id, image_url, sort_order, is_active, created_at
	           FROM categories WHERE slug = $1`
	var c Category
	if err := scanCategory(r.pool.QueryRow(ctx, q, slug), &c); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrCategoryNotFound
		}
		return nil, err
	}
	return &c, nil
}

func (r *CategoryRepository) Create(ctx context.Context, name, slug string, parentID *uuid.UUID, imageURL string, sortOrder int) (*Category, error) {
	const q = `
		INSERT INTO categories (name, slug, parent_id, image_url, sort_order)
		VALUES ($1, $2, $3, NULLIF($4, ''), $5)
		RETURNING id, name, slug, parent_id, image_url, sort_order, is_active, created_at
	`
	var c Category
	if err := scanCategory(r.pool.QueryRow(ctx, q, name, slug, parentID, imageURL, sortOrder), &c); err != nil {
		return nil, err
	}
	return &c, nil
}

func (r *CategoryRepository) Update(ctx context.Context, id uuid.UUID, name, slug, imageURL *string, sortOrder *int, isActive *bool) (*Category, error) {
	const q = `
		UPDATE categories SET
			name = COALESCE($2, name),
			slug = COALESCE($3, slug),
			image_url = COALESCE($4, image_url),
			sort_order = COALESCE($5, sort_order),
			is_active = COALESCE($6, is_active)
		WHERE id = $1
		RETURNING id, name, slug, parent_id, image_url, sort_order, is_active, created_at
	`
	var c Category
	if err := scanCategory(r.pool.QueryRow(ctx, q, id, name, slug, imageURL, sortOrder, isActive), &c); err != nil {
		return nil, err
	}
	return &c, nil
}

func (r *CategoryRepository) Delete(ctx context.Context, id uuid.UUID) error {
	// Check usage in product_categories
	var n int
	if err := r.pool.QueryRow(ctx,
		`SELECT COUNT(1) FROM product_categories pc JOIN products p ON p.id = pc.product_id
		 WHERE pc.category_id = $1 AND p.status != 'deleted'`,
		id).Scan(&n); err != nil {
		return err
	}
	if n > 0 {
		return httpx.NewConflict("category still in use by active products")
	}
	_, err := r.pool.Exec(ctx, `DELETE FROM categories WHERE id = $1`, id)
	return err
}

func scanCategory(row interface{ Scan(...any) error }, c *Category) error {
	return row.Scan(&c.ID, &c.Name, &c.Slug, &c.ParentID, &c.ImageURL, &c.SortOrder, &c.IsActive, &c.CreatedAt)
}

// ============================================================================
// Handler
// ============================================================================

type CategoryHandler struct {
	repo  *CategoryRepository
	cache *cache.Cache
}

func NewCategoryHandler(repo *CategoryRepository, c *cache.Cache) *CategoryHandler {
	return &CategoryHandler{repo: repo, cache: c}
}

func (h *CategoryHandler) Register(r *gin.RouterGroup, authMw, adminMw gin.HandlerFunc) {
	r.GET("", h.list)
	r.GET("/:slug", h.getBySlug)

	admin := r.Group("/", authMw, adminMw)
	admin.POST("", h.create)
	admin.PATCH("/:id", h.update)
	admin.DELETE("/:id", h.delete)
}

func (h *CategoryHandler) list(c *gin.Context) {
	cats, err := cache.Aside(c.Request.Context(), h.cache, "categories:all", 5*time.Minute, func(ctx context.Context) ([]Category, error) {
		return h.repo.ListAll(ctx)
	})
	if err != nil {
		c.Error(httpx.NewInternal("list categories", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"categories": cats})
}

func (h *CategoryHandler) getBySlug(c *gin.Context) {
	cat, err := h.repo.FindBySlug(c.Request.Context(), c.Param("slug"))
	if err != nil {
		c.Error(httpx.NewNotFound("category not found"))
		return
	}
	c.JSON(http.StatusOK, gin.H{"category": cat})
}

type createCatReq struct {
	Name      string     `json:"name" binding:"required,min=1,max=100"`
	Slug      string     `json:"slug" binding:"required,min=1,max=100"`
	ParentID  *uuid.UUID `json:"parent_id"`
	ImageURL  string     `json:"image_url"`
	SortOrder int        `json:"sort_order"`
}

func (h *CategoryHandler) create(c *gin.Context) {
	var req createCatReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	cat, err := h.repo.Create(c.Request.Context(), req.Name, req.Slug, req.ParentID, req.ImageURL, req.SortOrder)
	if err != nil {
		c.Error(httpx.NewInternal("create category", err))
		return
	}
	_ = h.cache.InvalidatePattern(c.Request.Context(), "categories:*")
	c.JSON(http.StatusCreated, gin.H{"category": cat})
}

func (h *CategoryHandler) update(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	var body struct {
		Name      *string `json:"name"`
		Slug      *string `json:"slug"`
		ImageURL  *string `json:"image_url"`
		SortOrder *int    `json:"sort_order"`
		IsActive  *bool   `json:"is_active"`
	}
	_ = c.ShouldBindJSON(&body)
	cat, err := h.repo.Update(c.Request.Context(), id, body.Name, body.Slug, body.ImageURL, body.SortOrder, body.IsActive)
	if err != nil {
		c.Error(httpx.NewInternal("update category", err))
		return
	}
	_ = h.cache.InvalidatePattern(c.Request.Context(), "categories:*")
	c.JSON(http.StatusOK, gin.H{"category": cat})
}

func (h *CategoryHandler) delete(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	if err := h.repo.Delete(c.Request.Context(), id); err != nil {
		c.Error(err)
		return
	}
	_ = h.cache.InvalidatePattern(c.Request.Context(), "categories:*")
	c.Status(http.StatusNoContent)
}
