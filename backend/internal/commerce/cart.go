package commerce

import (
	"context"
	"encoding/json"
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
	ID          uuid.UUID  `json:"id"`
	UserID      uuid.UUID  `json:"user_id"`
	VariantID   uuid.UUID  `json:"variant_id"`
	ProductID   *uuid.UUID `json:"product_id,omitempty"`
	ProductName string     `json:"product_name"`
	ShopID      *uuid.UUID `json:"shop_id,omitempty"`
	ShopName    *string    `json:"shop_name,omitempty"`
	ImageURL    *string    `json:"image_url,omitempty"`
	// Attributes is the raw JSONB blob from cart_items.attributes. Using
	// json.RawMessage (not []byte) so json.Marshal emits the array
	// verbatim — a plain []byte would be base64-encoded ("W10=" for "[]"),
	// which crashes the Flutter parser expecting a List.
	Attributes    json.RawMessage `json:"attributes"`
	UnitPrice     int             `json:"unit_price"`
	OriginalPrice int             `json:"original_price"`
	Quantity      int             `json:"quantity"`
	IsSelected    bool            `json:"is_selected"`
	AddedAt       time.Time       `json:"added_at"`
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

// UpdateQty updates a cart row's quantity and returns the refreshed
// item. The frontend's cart provider expects the full row back so it can
// reconcile its local state in one round-trip (no second GET /cart) —
// returning 204 here caused "type 'String' is not a subtype of
// Map<String, dynamic>" in the Flutter cast on the empty body.
func (r *CartRepository) UpdateQty(ctx context.Context, userID, itemID uuid.UUID, qty int) (*CartItem, error) {
	const q = `
		UPDATE cart_items SET quantity = $3 WHERE id = $2 AND user_id = $1
		RETURNING id, user_id, variant_id, product_id, product_name, shop_id, shop_name, image_url,
		          attributes, unit_price, original_price, quantity, is_selected, added_at
	`
	var out CartItem
	if err := scanCart(r.Pool.QueryRow(ctx, q, userID, itemID, qty), &out); err != nil {
		return nil, err
	}
	return &out, nil
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
	// Attach routes directly to `r` (= /api/cart) rather than nesting
	// `r.Group("/", authMw)` — the inner Group("/") produces a base path
	// with a trailing slash, so `GET ""` would resolve to `/api/cart/`.
	// Gin's RedirectTrailingSlash then 301-redirects `/api/cart` →
	// `/api/cart/` *without* CORS headers (the 301 short-circuits before
	// the CORS middleware runs), and browsers block credentialed XHRs on
	// such redirects. Registering at the exact path keeps the response on
	// the CORS-wrapped route.
	r.GET("", authMw, h.list)
	r.POST("/items", authMw, h.addItem)
	r.POST("/items/from-live", authMw, h.addItemFromLive)
	// IMPORTANT: register /items/selected BEFORE /items/:id to avoid the Node.js bug
	r.DELETE("/items/selected", authMw, h.removeSelected)
	r.PATCH("/select-all", authMw, h.selectAll)
	r.PATCH("/items/:id/qty", authMw, h.updateQty)
	r.PATCH("/items/:id/select", authMw, h.updateSelected)
	r.DELETE("/items/:id", authMw, h.remove)
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
	// An active flash sale overrides the unit price (Shopee "Flash Sale"). The
	// feed card already advertises this price; applying it here keeps the cart
	// and checkout honest. OriginalPrice stays the variant base price so the
	// cart's "tiết kiệm" line reflects the full saving. (sold_count is not
	// decremented here — cart-add isn't a sale; per-slot stock enforcement at
	// purchase time is future work.)
	var flashPrice *int
	_ = pool.QueryRow(c.Request.Context(),
		`SELECT fsp.flash_price
		   FROM flash_sale_products fsp
		   JOIN flash_sales fs ON fs.id = fsp.flash_sale_id
		  WHERE fsp.product_id = $1
		    AND fs.is_active AND fs.starts_at <= NOW() AND fs.ends_at > NOW()
		    AND (fsp.stock_limit IS NULL OR fsp.sold_count < fsp.stock_limit)
		  ORDER BY fsp.flash_price ASC, fs.ends_at ASC
		  LIMIT 1`,
		productID).Scan(&flashPrice)
	if flashPrice != nil && *flashPrice < unitPrice {
		unitPrice = *flashPrice
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
		productID   *uuid.UUID
		productName string
		imageURL    *string
		original    float64
		sale        float64
		shopID      *uuid.UUID
		shopName    *string
	)
	// Join to live_sessions → shops so the cart row carries the seller's
	// shop (cart UI groups items by shop). product_id may be NULL when the
	// live item isn't backed by a catalog product — fall back to the
	// live_session_products.id (= variant_id) so the frontend always has
	// a non-null string to render.
	err := pool.QueryRow(c.Request.Context(),
		`SELECT lsp.product_id, lsp.product_name, lsp.image_url,
		        lsp.original_price, lsp.sale_price,
		        sh.id, sh.name
		 FROM live_session_products lsp
		 JOIN live_sessions ls ON ls.id = lsp.session_id
		 LEFT JOIN shops sh ON sh.seller_id = ls.seller_id
		 WHERE lsp.id = $1 AND lsp.session_id = $2`,
		req.LiveProductID, req.SessionID).
		Scan(&productID, &productName, &imageURL, &original, &sale, &shopID, &shopName)
	if err != nil {
		c.Error(httpx.NewNotFound("live product not found"))
		return
	}
	// Fall back to the live product id when the live item isn't linked to
	// a catalog product — keeps cart_items.product_id NOT-NULL-ish for the
	// frontend grouping logic without changing the schema.
	if productID == nil {
		productID = &req.LiveProductID
	}
	item, err := h.repo.Upsert(c.Request.Context(), CartItem{
		UserID: uid, VariantID: req.LiveProductID,
		ProductID: productID, ProductName: productName,
		ShopID: shopID, ShopName: shopName,
		ImageURL:  imageURL,
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
	item, err := h.repo.UpdateQty(c.Request.Context(), uid, itemID, body.Quantity)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.Error(httpx.NewNotFound("cart item not found"))
			return
		}
		c.Error(httpx.NewInternal("update qty", err))
		return
	}
	c.JSON(http.StatusOK, item)
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
