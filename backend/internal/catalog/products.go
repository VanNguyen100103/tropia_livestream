package catalog

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

	"github.com/tropia/backend-go/internal/auth"
	"github.com/tropia/backend-go/internal/cache"
	"github.com/tropia/backend-go/internal/httpx"
)

type Product struct {
	ID           uuid.UUID `json:"id"`
	ShopID       uuid.UUID `json:"shop_id"`
	Name         string    `json:"name"`
	Slug         string    `json:"slug"`
	Description  *string   `json:"description,omitempty"`
	Images       []string  `json:"images"`
	BasePrice    int       `json:"base_price"`
	SalePrice    *int      `json:"sale_price,omitempty"`
	Unit         string    `json:"unit"`
	HasVariants  bool      `json:"has_variants"`
	Rating       float64   `json:"rating"`
	ReviewCount  int       `json:"review_count"`
	TotalSold    int       `json:"total_sold"`
	TotalStock   int       `json:"total_stock"`
	Status       string    `json:"status"`
	CreatedAt    time.Time `json:"created_at"`
}

var ErrProductNotFound = errors.New("product not found")

type ProductRepository struct{ pool *pgxpool.Pool }

func NewProductRepository(pool *pgxpool.Pool) *ProductRepository {
	return &ProductRepository{pool: pool}
}

type BrowseFilters struct {
	CategorySlug string
	ShopID       *uuid.UUID
	Search       string
	Sort         string // price_asc | price_desc | newest | rating | default(total_sold)
	MinPrice     *int
	MaxPrice     *int
	Page         int
	Limit        int
}

func (r *ProductRepository) Browse(ctx context.Context, f BrowseFilters) ([]Product, int, error) {
	if f.Page < 1 {
		f.Page = 1
	}
	if f.Limit < 1 || f.Limit > 100 {
		f.Limit = 20
	}
	offset := (f.Page - 1) * f.Limit

	wheres := []string{"p.status = 'active'"}
	args := []any{}
	idx := 1

	if f.ShopID != nil {
		wheres = append(wheres, "p.shop_id = $"+strconv.Itoa(idx))
		args = append(args, *f.ShopID)
		idx++
	}
	if f.CategorySlug != "" {
		wheres = append(wheres, "EXISTS (SELECT 1 FROM product_categories pc JOIN categories c ON c.id = pc.category_id WHERE pc.product_id = p.id AND c.slug = $"+strconv.Itoa(idx)+")")
		args = append(args, f.CategorySlug)
		idx++
	}
	if f.Search != "" {
		wheres = append(wheres, "p.search_vector @@ plainto_tsquery('simple', $"+strconv.Itoa(idx)+")")
		args = append(args, f.Search)
		idx++
	}
	if f.MinPrice != nil {
		wheres = append(wheres, "COALESCE(p.sale_price, p.base_price) >= $"+strconv.Itoa(idx))
		args = append(args, *f.MinPrice)
		idx++
	}
	if f.MaxPrice != nil {
		wheres = append(wheres, "COALESCE(p.sale_price, p.base_price) <= $"+strconv.Itoa(idx))
		args = append(args, *f.MaxPrice)
		idx++
	}

	order := "p.total_sold DESC"
	switch f.Sort {
	case "price_asc":
		order = "COALESCE(p.sale_price, p.base_price) ASC"
	case "price_desc":
		order = "COALESCE(p.sale_price, p.base_price) DESC"
	case "newest":
		order = "p.created_at DESC"
	case "rating":
		order = "p.rating DESC"
	}

	whereSQL := strings.Join(wheres, " AND ")

	countQ := "SELECT COUNT(*) FROM products p WHERE " + whereSQL
	var total int
	if err := r.pool.QueryRow(ctx, countQ, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	listQ := `
		SELECT p.id, p.shop_id, p.name, p.slug, p.description, p.images, p.base_price, p.sale_price,
		       p.unit, p.has_variants, p.rating, p.review_count, p.total_sold, p.total_stock, p.status, p.created_at
		FROM products p WHERE ` + whereSQL + ` ORDER BY ` + order +
		` LIMIT $` + strconv.Itoa(idx) + ` OFFSET $` + strconv.Itoa(idx+1)
	args = append(args, f.Limit, offset)

	rows, err := r.pool.Query(ctx, listQ, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := make([]Product, 0)
	for rows.Next() {
		var p Product
		if err := scanProduct(rows, &p); err != nil {
			return nil, 0, err
		}
		out = append(out, p)
	}
	return out, total, rows.Err()
}

func (r *ProductRepository) FindBySlug(ctx context.Context, slug string) (*Product, error) {
	const q = `SELECT id, shop_id, name, slug, description, images, base_price, sale_price,
	            unit, has_variants, rating, review_count, total_sold, total_stock, status, created_at
	          FROM products WHERE slug = $1 AND status != 'deleted'`
	var p Product
	if err := scanProduct(r.pool.QueryRow(ctx, q, slug), &p); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrProductNotFound
		}
		return nil, err
	}
	return &p, nil
}

func (r *ProductRepository) FindByID(ctx context.Context, id uuid.UUID) (*Product, error) {
	const q = `SELECT id, shop_id, name, slug, description, images, base_price, sale_price,
	            unit, has_variants, rating, review_count, total_sold, total_stock, status, created_at
	          FROM products WHERE id = $1`
	var p Product
	if err := scanProduct(r.pool.QueryRow(ctx, q, id), &p); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrProductNotFound
		}
		return nil, err
	}
	return &p, nil
}

func (r *ProductRepository) QuickCreate(ctx context.Context, shopID uuid.UUID, name, description string, price, stock int, imageURL string) (*Product, error) {
	slug := slugifyProduct(name) + "-" + strconv.FormatInt(time.Now().Unix(), 36)
	images := []string{}
	if imageURL != "" {
		images = []string{imageURL}
	}
	const q = `
		INSERT INTO products (shop_id, name, slug, description, images, base_price, total_stock, status, has_variants)
		VALUES ($1, $2, $3, NULLIF($4, ''), $5, $6, $7, 'active', FALSE)
		RETURNING id, shop_id, name, slug, description, images, base_price, sale_price,
		          unit, has_variants, rating, review_count, total_sold, total_stock, status, created_at
	`
	var p Product
	if err := scanProduct(r.pool.QueryRow(ctx, q, shopID, name, slug, description, images, price, stock), &p); err != nil {
		return nil, err
	}
	// Default variant for cart compatibility
	_, _ = r.pool.Exec(ctx,
		`INSERT INTO product_variants (product_id, price, stock, is_active) VALUES ($1, $2, $3, TRUE)`,
		p.ID, price, stock)
	return &p, nil
}

func (r *ProductRepository) UpdateStatus(ctx context.Context, id uuid.UUID, status string) error {
	_, err := r.pool.Exec(ctx, `UPDATE products SET status = $2 WHERE id = $1`, id, status)
	return err
}

func (r *ProductRepository) SoftDelete(ctx context.Context, id uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `UPDATE products SET status = 'deleted' WHERE id = $1`, id)
	return err
}

func (r *ProductRepository) AssertOwner(ctx context.Context, productID, sellerID uuid.UUID) (bool, error) {
	var n int
	err := r.pool.QueryRow(ctx,
		`SELECT COUNT(1) FROM products p JOIN shops s ON s.id = p.shop_id
		 WHERE p.id = $1 AND s.seller_id = $2`,
		productID, sellerID).Scan(&n)
	return n > 0, err
}

func scanProduct(row interface{ Scan(...any) error }, p *Product) error {
	return row.Scan(
		&p.ID, &p.ShopID, &p.Name, &p.Slug, &p.Description, &p.Images, &p.BasePrice, &p.SalePrice,
		&p.Unit, &p.HasVariants, &p.Rating, &p.ReviewCount, &p.TotalSold, &p.TotalStock, &p.Status, &p.CreatedAt,
	)
}

func slugifyProduct(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	var b strings.Builder
	prev := false
	for _, r := range s {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			b.WriteRune(r)
			prev = false
		case r == ' ', r == '-', r == '_':
			if !prev {
				b.WriteRune('-')
				prev = true
			}
		}
	}
	return strings.Trim(b.String(), "-")
}

// ============================================================================
// Handler
// ============================================================================

type ProductHandler struct {
	repo    *ProductRepository
	shops   shopOwnerResolver
	cache   *cache.Cache
}

type shopOwnerResolver interface {
	FindBySellerID(ctx context.Context, sellerID uuid.UUID) (shopInfo, error)
}

type shopInfo interface {
	GetID() uuid.UUID
}

// SimpleShopResolver wraps shops.Repository
type SimpleShopResolver struct {
	Lookup func(ctx context.Context, sellerID uuid.UUID) (uuid.UUID, error)
}

func (s SimpleShopResolver) FindBySellerID(ctx context.Context, sellerID uuid.UUID) (shopInfo, error) {
	id, err := s.Lookup(ctx, sellerID)
	if err != nil {
		return nil, err
	}
	return shopID(id), nil
}

type shopID uuid.UUID

func (s shopID) GetID() uuid.UUID { return uuid.UUID(s) }

func NewProductHandler(repo *ProductRepository, shopResolver SimpleShopResolver, c *cache.Cache) *ProductHandler {
	return &ProductHandler{repo: repo, shops: shopResolver, cache: c}
}

func (h *ProductHandler) Register(r *gin.RouterGroup, authMw, sellerMw gin.HandlerFunc) {
	r.GET("", h.browse)
	r.GET("/:slug", h.getBySlug)

	seller := r.Group("/", authMw, sellerMw)
	seller.POST("/quick-create", h.quickCreate)
	seller.PATCH("/:id/status", h.updateStatus)
	seller.DELETE("/:id", h.softDelete)
}

func (h *ProductHandler) browse(c *gin.Context) {
	f := BrowseFilters{
		CategorySlug: c.Query("category"),
		Search:       c.Query("search"),
		Sort:         c.Query("sort"),
	}
	if v, err := strconv.Atoi(c.Query("page")); err == nil {
		f.Page = v
	}
	if v, err := strconv.Atoi(c.Query("limit")); err == nil {
		f.Limit = v
	}
	if v, err := strconv.Atoi(c.Query("min_price")); err == nil {
		f.MinPrice = &v
	}
	if v, err := strconv.Atoi(c.Query("max_price")); err == nil {
		f.MaxPrice = &v
	}
	if shop := c.Query("shop"); shop != "" {
		if id, err := uuid.Parse(shop); err == nil {
			f.ShopID = &id
		}
	}
	products, total, err := h.repo.Browse(c.Request.Context(), f)
	if err != nil {
		c.Error(httpx.NewInternal("browse products", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"data": products,
		"pagination": gin.H{
			"page":  f.Page,
			"limit": f.Limit,
			"total": total,
		},
	})
}

func (h *ProductHandler) getBySlug(c *gin.Context) {
	p, err := h.repo.FindBySlug(c.Request.Context(), c.Param("slug"))
	if err != nil {
		c.Error(httpx.NewNotFound("product not found"))
		return
	}
	c.JSON(http.StatusOK, gin.H{"product": p})
}

type quickCreateReq struct {
	Name        string `json:"name" binding:"required,min=1,max=200"`
	Description string `json:"description"`
	Price       int    `json:"price" binding:"required,min=0"`
	Stock       int    `json:"stock" binding:"min=0"`
	ImageURL    string `json:"image_url"`
}

func (h *ProductHandler) quickCreate(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	sellerID, _ := uuid.Parse(claims.UserID)
	shop, err := h.shops.FindBySellerID(c.Request.Context(), sellerID)
	if err != nil {
		c.Error(httpx.NewForbidden("seller has no shop"))
		return
	}
	var req quickCreateReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	p, err := h.repo.QuickCreate(c.Request.Context(), shop.GetID(), req.Name, req.Description, req.Price, req.Stock, req.ImageURL)
	if err != nil {
		c.Error(httpx.NewInternal("quick create", err))
		return
	}
	c.JSON(http.StatusCreated, gin.H{"product": p})
}

func (h *ProductHandler) updateStatus(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	var body struct {
		Status string `json:"status" binding:"required,oneof=draft active inactive"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	claims, _ := auth.ClaimsFrom(c)
	sellerID, _ := uuid.Parse(claims.UserID)
	if claims.Role != auth.RoleAdmin {
		ok, _ := h.repo.AssertOwner(c.Request.Context(), id, sellerID)
		if !ok {
			c.Error(httpx.NewForbidden("not your product"))
			return
		}
	}
	if err := h.repo.UpdateStatus(c.Request.Context(), id, body.Status); err != nil {
		c.Error(httpx.NewInternal("update status", err))
		return
	}
	c.Status(http.StatusNoContent)
}

func (h *ProductHandler) softDelete(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	claims, _ := auth.ClaimsFrom(c)
	sellerID, _ := uuid.Parse(claims.UserID)
	if claims.Role != auth.RoleAdmin {
		ok, _ := h.repo.AssertOwner(c.Request.Context(), id, sellerID)
		if !ok {
			c.Error(httpx.NewForbidden("not your product"))
			return
		}
	}
	if err := h.repo.SoftDelete(c.Request.Context(), id); err != nil {
		c.Error(httpx.NewInternal("delete product", err))
		return
	}
	c.Status(http.StatusNoContent)
}
