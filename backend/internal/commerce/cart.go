package commerce

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tropia/backend/internal/auth"
	"github.com/tropia/backend/internal/httpx"
)

type CartItem struct {
	ID            uuid.UUID `json:"id"`
	UserID        uuid.UUID `json:"user_id"`
	VariantID     uuid.UUID `json:"variant_id"`
	ProductID     *uuid.UUID `json:"product_id,omitempty"`
	ProductName   string    `json:"product_name"`
	ShopID        *uuid.UUID `json:"shop_id,omitempty"`
	ShopName      *string   `json:"shop_name,omitempty"`
	ImageURL      *string   `json:"image_url,omitempty"`
	Attributes    []byte    `json:"attributes"`
	UnitPrice     int       `json:"unit_price"`
	OriginalPrice int       `json:"original_price"`
	Quantity      int       `json:"quantity"`
	IsSelected    bool      `json:"is_selected"`
	AddedAt       time.Time `json:"added_at"`
}

type CartRepository struct{ Pool *pgxpool.Pool }

func NewCartRepository(pool *pgxpool.Pool) *CartRepository {
	return &CartRepository{Pool: pool}
}

func (r *CartRepository) List(ctx context.Context, userID uuid.UUID) ([]CartItem, error) {
	const q = `
		SELECT id, user_id, variant_id, product_id, product_name, shop_id, shop_name, image_url,
		       attributes, unit_price, original_price, quantity, is_selected, added_at
		FROM cart_items WHERE user_id = $1
		ORDER BY added_at DESC
	`
	rows, err := r.Pool.Query(ctx, q, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]CartItem, 0)
	for rows.Next() {
		var it CartItem
		if err := scanCart(rows, &it); err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

func (r *CartRepository) Upsert(ctx context.Context, it CartItem) (*CartItem, error) {
	// Try update first
	const updateQ = `
		UPDATE cart_items
		SET quantity = quantity + $3, is_selected = TRUE, added_at = NOW()
		WHERE user_id = $1 AND variant_id = $2
		RETURNING id, user_id, variant_id, product_id, product_name, shop_id, shop_name, image_url,
		          attributes, unit_price, original_price, quantity, is_selected, added_at
	`
	row := r.Pool.QueryRow(ctx, updateQ, it.UserID, it.VariantID, it.Quantity)
	var out CartItem
	err := scanCart(row, &out)
	if err == nil {
		return &out, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return nil, err
	}

	// Insert new
	const insertQ = `
		INSERT INTO cart_items (user_id, variant_id, product_id, product_name, shop_id, shop_name,
		                        image_url, attributes, unit_price, original_price, quantity)
		VALUES ($1, $2, $3, $4, $5, $6, NULLIF($7, ''), $8, $9, $10, $11)
		RETURNING id, user_id, variant_id, product_id, product_name, shop_id, shop_name, image_url,
		          attributes, unit_price, original_price, quantity, is_selected, added_at
	`
	attrs := it.Attributes
	if attrs == nil {
		attrs = []byte(`[]`)
	}
	var shopName, imgURL string
	if it.ShopName != nil {
		shopName = *it.ShopName
	}
	if it.ImageURL != nil {
		imgURL = *it.ImageURL
	}
	row = r.Pool.QueryRow(ctx, insertQ,
		it.UserID, it.VariantID, it.ProductID, it.ProductName, it.ShopID, shopName,
		imgURL, attrs, it.UnitPrice, it.OriginalPrice, it.Quantity,
	)
	if err := scanCart(row, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

func (r *CartRepository) UpdateQty(ctx context.Context, userID, itemID uuid.UUID, qty int) error {
	_, err := r.Pool.Exec(ctx,
		`UPDATE cart_items SET quantity = $3 WHERE id = $2 AND user_id = $1`,
		userID, itemID, qty)
	return err
}

func (r *CartRepository) UpdateSelected(ctx context.Context, userID, itemID uuid.UUID, selected bool) error {
	_, err := r.Pool.Exec(ctx,
		`UPDATE cart_items SET is_selected = $3 WHERE id = $2 AND user_id = $1`,
		userID, itemID, selected)
	return err
}

func (r *CartRepository) SelectAll(ctx context.Context, userID uuid.UUID, selected bool) error {
	_, err := r.Pool.Exec(ctx,
		`UPDATE cart_items SET is_selected = $2 WHERE user_id = $1`,
		userID, selected)
	return err
}

func (r *CartRepository) Remove(ctx context.Context, userID, itemID uuid.UUID) error {
	_, err := r.Pool.Exec(ctx,
		`DELETE FROM cart_items WHERE id = $2 AND user_id = $1`,
		userID, itemID)
	return err
}

func (r *CartRepository) RemoveSelected(ctx context.Context, userID uuid.UUID) error {
	_, err := r.Pool.Exec(ctx,
		`DELETE FROM cart_items WHERE user_id = $1 AND is_selected = TRUE`,
		userID)
	return err
}

func (r *CartRepository) ListSelected(ctx context.Context, userID uuid.UUID) ([]CartItem, error) {
	const q = `
		SELECT id, user_id, variant_id, product_id, product_name, shop_id, shop_name, image_url,
		       attributes, unit_price, original_price, quantity, is_selected, added_at
		FROM cart_items WHERE user_id = $1 AND is_selected = TRUE
	`
	rows, err := r.Pool.Query(ctx, q, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]CartItem, 0)
	for rows.Next() {
		var it CartItem
		if err := scanCart(rows, &it); err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

func scanCart(row interface{ Scan(...any) error }, it *CartItem) error {
	return row.Scan(
		&it.ID, &it.UserID, &it.VariantID, &it.ProductID, &it.ProductName,
		&it.ShopID, &it.ShopName, &it.ImageURL, &it.Attributes,
		&it.UnitPrice, &it.OriginalPrice, &it.Quantity, &it.IsSelected, &it.AddedAt,
	)
}

// ============================================================================
// Handler
// ============================================================================

type CartHandler struct {
	repo *CartRepository
}

func NewCartHandler(repo *CartRepository) *CartHandler {
	return &CartHandler{repo: repo}
}

func (h *CartHandler) Register(r *gin.RouterGroup, authMw gin.HandlerFunc) {
	g := r.Group("/", authMw)
	g.GET("", h.list)
	g.POST("/items", h.addItem)
	g.POST("/items/from-live", h.addItemFromLive)
	// IMPORTANT: register /items/selected BEFORE /items/:id to avoid the Node.js bug
	g.DELETE("/items/selected", h.removeSelected)
	g.PATCH("/select-all", h.selectAll)
	g.PATCH("/items/:id/qty", h.updateQty)
	g.PATCH("/items/:id/select", h.updateSelected)
	g.DELETE("/items/:id", h.remove)
}

func (h *CartHandler) list(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	items, err := h.repo.List(c.Request.Context(), uid)
	if err != nil {
		c.Error(httpx.NewInternal("list cart", err))
		return
	}
	var totalItems, totalPrice, totalSaving int
	for _, it := range items {
		if !it.IsSelected {
			continue
		}
		totalItems += it.Quantity
		totalPrice += it.UnitPrice * it.Quantity
		totalSaving += (it.OriginalPrice - it.UnitPrice) * it.Quantity
	}
	c.JSON(http.StatusOK, gin.H{
		"items":   items,
		"summary": gin.H{"total_items": totalItems, "total_price": totalPrice, "total_saving": totalSaving},
	})
}

type addItemReq struct {
	VariantID uuid.UUID `json:"variant_id" binding:"required"`
	Quantity  int       `json:"quantity" binding:"required,min=1,max=999"`
}

func (h *CartHandler) addItem(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	var req addItemReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	// Look up variant_detail
	pool := h.repo.Pool
	var (
		productID  uuid.UUID
		productName string
		shopID     *uuid.UUID
		shopName   *string
		imageURL   *string
		price      int
		salePrice  *int
	)
	err := pool.QueryRow(c.Request.Context(),
		`SELECT p.id, p.name, p.shop_id, s.name, p.images[1], v.price, v.sale_price
		 FROM product_variants v
		 JOIN products p ON p.id = v.product_id
		 LEFT JOIN shops s ON s.id = p.shop_id
		 WHERE v.id = $1 AND v.is_active = TRUE`,
		req.VariantID).Scan(&productID, &productName, &shopID, &shopName, &imageURL, &price, &salePrice)
	if err != nil {
		c.Error(httpx.NewNotFound("variant not found"))
		return
	}
	unitPrice := price
	if salePrice != nil {
		unitPrice = *salePrice
	}
	item, err := h.repo.Upsert(c.Request.Context(), CartItem{
		UserID: uid, VariantID: req.VariantID, ProductID: &productID, ProductName: productName,
		ShopID: shopID, ShopName: shopName, ImageURL: imageURL,
		UnitPrice: unitPrice, OriginalPrice: price, Quantity: req.Quantity,
	})
	if err != nil {
		c.Error(httpx.NewInternal("upsert cart", err))
		return
	}
	c.JSON(http.StatusCreated, item)
}

type addItemFromLiveReq struct {
	LiveProductID uuid.UUID `json:"live_product_id" binding:"required"`
	SessionID     uuid.UUID `json:"session_id" binding:"required"`
	Quantity      int       `json:"quantity" binding:"required,min=1,max=999"`
}

func (h *CartHandler) addItemFromLive(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	var req addItemFromLiveReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	pool := h.repo.Pool
	var (
		productName string
		imageURL    *string
		original    float64
		sale        float64
	)
	err := pool.QueryRow(c.Request.Context(),
		`SELECT product_name, image_url, original_price, sale_price
		 FROM live_session_products WHERE id = $1 AND session_id = $2`,
		req.LiveProductID, req.SessionID).Scan(&productName, &imageURL, &original, &sale)
	if err != nil {
		c.Error(httpx.NewNotFound("live product not found"))
		return
	}
	item, err := h.repo.Upsert(c.Request.Context(), CartItem{
		UserID: uid, VariantID: req.LiveProductID, ProductName: productName,
		ImageURL: imageURL,
		UnitPrice: int(sale), OriginalPrice: int(original), Quantity: req.Quantity,
		Attributes: []byte(`[]`),
	})
	if err != nil {
		c.Error(httpx.NewInternal("upsert cart from live", err))
		return
	}
	c.JSON(http.StatusCreated, item)
}

func (h *CartHandler) updateQty(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	itemID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	var body struct {
		Quantity int `json:"quantity" binding:"required,min=1,max=999"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	_ = h.repo.UpdateQty(c.Request.Context(), uid, itemID, body.Quantity)
	c.Status(http.StatusNoContent)
}

func (h *CartHandler) updateSelected(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	itemID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	var body struct {
		IsSelected bool `json:"is_selected"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	_ = h.repo.UpdateSelected(c.Request.Context(), uid, itemID, body.IsSelected)
	c.Status(http.StatusNoContent)
}

func (h *CartHandler) selectAll(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	var body struct {
		IsSelected bool `json:"is_selected"`
	}
	_ = c.ShouldBindJSON(&body)
	_ = h.repo.SelectAll(c.Request.Context(), uid, body.IsSelected)
	c.Status(http.StatusNoContent)
}

func (h *CartHandler) remove(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	itemID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	_ = h.repo.Remove(c.Request.Context(), uid, itemID)
	c.Status(http.StatusNoContent)
}

func (h *CartHandler) removeSelected(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	_ = h.repo.RemoveSelected(c.Request.Context(), uid)
	c.Status(http.StatusNoContent)
}
