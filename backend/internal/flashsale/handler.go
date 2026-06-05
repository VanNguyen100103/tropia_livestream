package flashsale

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/tropia/backend/internal/auth"
	"github.com/tropia/backend/internal/httpx"
)

type Handler struct{ repo *Repository }

func NewHandler(repo *Repository) *Handler { return &Handler{repo: repo} }

// Register wires:
//
//	GET    /flash-sales/active             — public: sales live right now.
//	GET    /flash-sales                    — admin: all (optionally inactive).
//	POST   /flash-sales                    — admin: create (with products).
//	GET    /flash-sales/:id                — admin: one sale + products.
//	PATCH  /flash-sales/:id                — admin: edit name/window/active.
//	DELETE /flash-sales/:id                — admin: delete.
//	PUT    /flash-sales/:id/products       — admin: replace the product set.
//	DELETE /flash-sales/:id/products/:productId — admin: drop one product.
// Register wires:
//
//	GET    /flash-sales/active             — public: sales live right now.
//	GET    /flash-sales                    — admin: all (optionally inactive).
//	POST   /flash-sales                    — admin: create (with products).
//	GET    /flash-sales/:id                — admin: one sale + products.
//	PATCH  /flash-sales/:id                — admin: edit name/window/active.
//	DELETE /flash-sales/:id                — admin: delete.
//	PUT    /flash-sales/:id/products       — admin: replace the product set.
//	DELETE /flash-sales/:id/products/:productId — admin: drop one product.
func (h *Handler) Register(r *gin.RouterGroup, authMw, adminMw gin.HandlerFunc) {
	pub := r.Group("/flash-sales")
	pub.GET("/active", h.listActive)

	adm := r.Group("/flash-sales", authMw, adminMw)
	adm.GET("", h.list)
	adm.POST("", h.create)
	adm.GET("/:id", h.getOne)
	adm.PATCH("/:id", h.update)
	adm.DELETE("/:id", h.delete)
	adm.PUT("/:id/products", h.setProducts)
	adm.DELETE("/:id/products/:productId", h.removeProduct)
}

func callerUID(c *gin.Context) (uuid.UUID, bool) {
	claims, ok := auth.ClaimsFrom(c)
	if !ok {
		return uuid.Nil, false
	}
	id, err := uuid.Parse(claims.UserID)
	if err != nil {
		return uuid.Nil, false
	}
	return id, true
}

func parseID(c *gin.Context, name string) (uuid.UUID, bool) {
	id, err := uuid.Parse(c.Param(name))
	if err != nil {
		c.Error(httpx.NewValidation("invalid "+name, nil))
		return uuid.Nil, false
	}
	return id, true
}

// mapErr translates repo errors into HTTP errors (the DB window CHECK surfaces
// as a validation error rather than a 500).
func mapErr(c *gin.Context, ctxMsg string, err error) {
	switch {
	case errors.Is(err, ErrNotFound):
		c.Error(httpx.NewNotFound("flash sale not found"))
	case err != nil && strings.Contains(err.Error(), "flash_sales_window"):
		c.Error(httpx.NewValidation("thời gian kết thúc phải sau thời gian bắt đầu", nil))
	default:
		c.Error(httpx.NewInternal(ctxMsg, err))
	}
}

func (h *Handler) listActive(c *gin.Context) {
	sales, err := h.repo.ListActive(c.Request.Context())
	if err != nil {
		c.Error(httpx.NewInternal("list active flash sales", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"flash_sales": sales})
}

func (h *Handler) list(c *gin.Context) {
	includeInactive := c.Query("all") == "true" || c.Query("include_inactive") == "true"
	limit := 50
	if v, err := strconv.Atoi(c.Query("limit")); err == nil && v > 0 && v <= 100 {
		limit = v
	}
	offset := 0
	if v, err := strconv.Atoi(c.Query("offset")); err == nil && v >= 0 {
		offset = v
	}
	sales, err := h.repo.List(c.Request.Context(), includeInactive, limit, offset)
	if err != nil {
		c.Error(httpx.NewInternal("list flash sales", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"flash_sales": sales})
}

type productInputReq struct {
	ProductID  string `json:"product_id" binding:"required"`
	FlashPrice int    `json:"flash_price" binding:"min=0"`
	StockLimit *int   `json:"stock_limit"`
}

type createReq struct {
	Name     string            `json:"name" binding:"required,min=1,max=200"`
	StartsAt time.Time         `json:"starts_at" binding:"required"`
	EndsAt   time.Time         `json:"ends_at" binding:"required"`
	Products []productInputReq `json:"products"`
}

// parseProducts validates + dedupes the product inputs (a bad/duplicate id is
// dropped, not rejected). flash_price must be >= 0; stock_limit (if present) >= 0.
func parseProducts(in []productInputReq) []ProductInput {
	out := make([]ProductInput, 0, len(in))
	seen := make(map[uuid.UUID]bool)
	for _, p := range in {
		pid, err := uuid.Parse(strings.TrimSpace(p.ProductID))
		if err != nil || seen[pid] || p.FlashPrice < 0 {
			continue
		}
		if p.StockLimit != nil && *p.StockLimit < 0 {
			continue
		}
		seen[pid] = true
		out = append(out, ProductInput{ProductID: pid, FlashPrice: p.FlashPrice, StockLimit: p.StockLimit})
	}
	return out
}

func (h *Handler) create(c *gin.Context) {
	uid, ok := callerUID(c)
	if !ok {
		c.Error(httpx.NewAuth("unauthenticated"))
		return
	}
	var req createReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	if !req.EndsAt.After(req.StartsAt) {
		c.Error(httpx.NewValidation("thời gian kết thúc phải sau thời gian bắt đầu", nil))
		return
	}
	sale, err := h.repo.Create(c.Request.Context(), CreateParams{
		Name:      httpx.CleanString(strings.TrimSpace(req.Name)),
		StartsAt:  req.StartsAt,
		EndsAt:    req.EndsAt,
		CreatedBy: uid,
		Products:  parseProducts(req.Products),
	})
	if err != nil {
		mapErr(c, "create flash sale", err)
		return
	}
	c.JSON(http.StatusCreated, sale)
}

func (h *Handler) getOne(c *gin.Context) {
	id, ok := parseID(c, "id")
	if !ok {
		return
	}
	sale, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		mapErr(c, "get flash sale", err)
		return
	}
	c.JSON(http.StatusOK, sale)
}

type updateReq struct {
	Name     *string    `json:"name"`
	StartsAt *time.Time `json:"starts_at"`
	EndsAt   *time.Time `json:"ends_at"`
	IsActive *bool      `json:"is_active"`
}

func (h *Handler) update(c *gin.Context) {
	id, ok := parseID(c, "id")
	if !ok {
		return
	}
	var req updateReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	if req.Name != nil {
		cleaned := httpx.CleanString(strings.TrimSpace(*req.Name))
		if cleaned == "" {
			c.Error(httpx.NewValidation("tên không hợp lệ", nil))
			return
		}
		req.Name = &cleaned
	}
	if req.StartsAt != nil && req.EndsAt != nil && !req.EndsAt.After(*req.StartsAt) {
		c.Error(httpx.NewValidation("thời gian kết thúc phải sau thời gian bắt đầu", nil))
		return
	}
	if err := h.repo.Update(c.Request.Context(), id, req.Name, req.StartsAt, req.EndsAt, req.IsActive); err != nil {
		mapErr(c, "update flash sale", err)
		return
	}
	sale, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		mapErr(c, "reload flash sale", err)
		return
	}
	c.JSON(http.StatusOK, sale)
}

func (h *Handler) delete(c *gin.Context) {
	id, ok := parseID(c, "id")
	if !ok {
		return
	}
	if err := h.repo.Delete(c.Request.Context(), id); err != nil {
		mapErr(c, "delete flash sale", err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

type setProductsReq struct {
	Products []productInputReq `json:"products"`
}

func (h *Handler) setProducts(c *gin.Context) {
	id, ok := parseID(c, "id")
	if !ok {
		return
	}
	var req setProductsReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	if err := h.repo.SetProducts(c.Request.Context(), id, parseProducts(req.Products)); err != nil {
		mapErr(c, "set flash sale products", err)
		return
	}
	sale, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		mapErr(c, "reload flash sale", err)
		return
	}
	c.JSON(http.StatusOK, sale)
}

func (h *Handler) removeProduct(c *gin.Context) {
	id, ok := parseID(c, "id")
	if !ok {
		return
	}
	pid, ok := parseID(c, "productId")
	if !ok {
		return
	}
	if err := h.repo.RemoveProduct(c.Request.Context(), id, pid); err != nil {
		mapErr(c, "remove flash sale product", err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}
