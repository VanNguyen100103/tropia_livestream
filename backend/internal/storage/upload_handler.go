package storage

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"path"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tropia/backend/internal/auth"
	"github.com/tropia/backend/internal/httpx"
)

// UploadHandler runs ownership checks against the DB before letting the
// authenticated seller write into R2 under a path that includes the
// target resource id. Without these checks, OWASP API1 (BOLA): any
// seller could overwrite another seller's product/shop/variant/cover
// images by guessing UUIDs.
type UploadHandler struct {
	r2 *R2
	db *pgxpool.Pool
}

func NewUploadHandler(r2 *R2, db *pgxpool.Pool) *UploadHandler {
	return &UploadHandler{r2: r2, db: db}
}

// ownerOfProduct, ownerOfVariant, ownerOfShop, ownerOfSession all return
// the seller_id that owns the given resource, or ErrNoOwner if it
// doesn't exist. The handler then refuses the upload unless seller_id
// matches the JWT's user id (or the caller is admin).
var errNoOwner = errors.New("resource not found")

func (h *UploadHandler) ownerOfProduct(ctx context.Context, productID uuid.UUID) (uuid.UUID, error) {
	var sellerID uuid.UUID
	err := h.db.QueryRow(ctx,
		`SELECT s.seller_id FROM products p JOIN shops s ON s.id = p.shop_id WHERE p.id = $1`,
		productID).Scan(&sellerID)
	if errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, errNoOwner
	}
	return sellerID, err
}

func (h *UploadHandler) ownerOfVariant(ctx context.Context, variantID uuid.UUID) (uuid.UUID, error) {
	var sellerID uuid.UUID
	err := h.db.QueryRow(ctx,
		`SELECT s.seller_id FROM product_variants v
		   JOIN products p ON p.id = v.product_id
		   JOIN shops s    ON s.id = p.shop_id
		  WHERE v.id = $1`,
		variantID).Scan(&sellerID)
	if errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, errNoOwner
	}
	return sellerID, err
}

func (h *UploadHandler) ownerOfShop(ctx context.Context, shopID uuid.UUID) (uuid.UUID, error) {
	var sellerID uuid.UUID
	err := h.db.QueryRow(ctx,
		`SELECT seller_id FROM shops WHERE id = $1`,
		shopID).Scan(&sellerID)
	if errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, errNoOwner
	}
	return sellerID, err
}

func (h *UploadHandler) ownerOfSession(ctx context.Context, sessionID uuid.UUID) (uuid.UUID, error) {
	var sellerID uuid.UUID
	err := h.db.QueryRow(ctx,
		`SELECT seller_id FROM live_sessions WHERE id = $1`,
		sessionID).Scan(&sellerID)
	if errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, errNoOwner
	}
	return sellerID, err
}

// assertOwner is the gate every BOLA-sensitive upload runs through.
// Parses + validates the resource id, fetches its owning seller_id via
// the lookup fn, and compares to the JWT subject. Returns the parsed
// uuid + the caller's claims so handlers can keep the rest of the
// upload flow simple.
func (h *UploadHandler) assertOwner(c *gin.Context, rawID string, lookup func(context.Context, uuid.UUID) (uuid.UUID, error)) (uuid.UUID, bool) {
	id, err := uuid.Parse(rawID)
	if err != nil {
		c.Error(httpx.NewValidation("invalid resource id", nil))
		return uuid.Nil, false
	}
	owner, err := lookup(c.Request.Context(), id)
	if errors.Is(err, errNoOwner) {
		// Return 404 (not 403) so we don't leak which IDs exist —
		// matches the BOLA defense pattern documented in CLAUDE.md.
		c.Error(httpx.NewNotFound("resource not found"))
		return uuid.Nil, false
	}
	if err != nil {
		c.Error(httpx.NewInternal("ownership lookup", err))
		return uuid.Nil, false
	}
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	if owner != uid && claims.Role != auth.RoleAdmin {
		c.Error(httpx.NewNotFound("resource not found"))
		return uuid.Nil, false
	}
	return id, true
}

func (h *UploadHandler) Register(r *gin.RouterGroup, authMw, sellerMw gin.HandlerFunc) {
	authed := r.Group("/", authMw)
	authed.POST("/avatar", h.avatar)

	seller := r.Group("/", authMw, sellerMw)
	seller.POST("/product", h.product)
	seller.POST("/variant", h.variant)
	seller.POST("/shop", h.shop)
	seller.POST("/live", h.liveCover)
	seller.POST("/temp", h.temp)
}

const maxUploadBytes = 5 << 20 // 5MB

var allowedExts = map[string]string{
	".jpg":  "image/jpeg",
	".jpeg": "image/jpeg",
	".png":  "image/png",
	".webp": "image/webp",
}

func (h *UploadHandler) readImage(c *gin.Context, field string) (data []byte, contentType string, err error) {
	file, header, err := c.Request.FormFile(field)
	if err != nil {
		return nil, "", httpx.NewValidation("missing file: "+field, nil)
	}
	defer file.Close()
	if header.Size > maxUploadBytes {
		return nil, "", httpx.NewValidation("file too large (max 5MB)", nil)
	}
	ext := strings.ToLower(path.Ext(header.Filename))
	ct, ok := allowedExts[ext]
	if !ok {
		return nil, "", httpx.NewValidation("only jpg/png/webp allowed", nil)
	}
	data, err = io.ReadAll(file)
	if err != nil {
		return nil, "", httpx.NewInternal("read file", err)
	}
	return data, ct, nil
}

func (h *UploadHandler) avatar(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	data, ct, err := h.readImage(c, "image")
	if err != nil {
		c.Error(err)
		return
	}
	key := fmt.Sprintf("images/avatars/%s%s", uid, extFromCT(ct))
	url, err := h.r2.Upload(c.Request.Context(), key, ct, data)
	if err != nil {
		c.Error(httpx.NewInternal("r2 upload", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"url": url, "key": key})
}

func (h *UploadHandler) product(c *gin.Context) {
	rawID := c.PostForm("product_id")
	if rawID == "" {
		c.Error(httpx.NewValidation("product_id required", nil))
		return
	}
	productID, ok := h.assertOwner(c, rawID, h.ownerOfProduct)
	if !ok {
		return
	}
	form, err := c.MultipartForm()
	if err != nil {
		c.Error(httpx.NewValidation("multipart parse failed", nil))
		return
	}
	files := form.File["images"]
	if len(files) == 0 {
		c.Error(httpx.NewValidation("no files", nil))
		return
	}
	if len(files) > 10 {
		c.Error(httpx.NewValidation("max 10 files", nil))
		return
	}
	urls := make([]string, 0, len(files))
	for i, fh := range files {
		f, err := fh.Open()
		if err != nil {
			continue
		}
		data, _ := io.ReadAll(f)
		f.Close()
		ext := strings.ToLower(path.Ext(fh.Filename))
		ct := allowedExts[ext]
		if ct == "" {
			continue
		}
		key := fmt.Sprintf("images/products/%s/%d_%d%s", productID, time.Now().UnixNano(), i, ext)
		url, err := h.r2.Upload(c.Request.Context(), key, ct, data)
		if err != nil {
			continue
		}
		urls = append(urls, url)
	}
	c.JSON(http.StatusOK, gin.H{"urls": urls})
}

// variant uploads images for a specific product_variant (color/size SKU).
// Form: variant_id (text) + images[] (max 5 files).
// Returns {urls: [...]} matching the product endpoint shape.
func (h *UploadHandler) variant(c *gin.Context) {
	rawID := c.PostForm("variant_id")
	if rawID == "" {
		c.Error(httpx.NewValidation("variant_id required", nil))
		return
	}
	variantID, ok := h.assertOwner(c, rawID, h.ownerOfVariant)
	if !ok {
		return
	}
	form, err := c.MultipartForm()
	if err != nil {
		c.Error(httpx.NewValidation("multipart parse failed", nil))
		return
	}
	files := form.File["images"]
	if len(files) == 0 {
		c.Error(httpx.NewValidation("no files", nil))
		return
	}
	if len(files) > 5 {
		c.Error(httpx.NewValidation("max 5 files per variant", nil))
		return
	}
	urls := make([]string, 0, len(files))
	for i, fh := range files {
		f, err := fh.Open()
		if err != nil {
			continue
		}
		data, _ := io.ReadAll(f)
		f.Close()
		ext := strings.ToLower(path.Ext(fh.Filename))
		ct := allowedExts[ext]
		if ct == "" {
			continue
		}
		key := fmt.Sprintf("images/variants/%s/%d_%d%s", variantID, time.Now().UnixNano(), i, ext)
		url, err := h.r2.Upload(c.Request.Context(), key, ct, data)
		if err != nil {
			continue
		}
		urls = append(urls, url)
	}
	c.JSON(http.StatusOK, gin.H{"urls": urls})
}

func (h *UploadHandler) shop(c *gin.Context) {
	rawID := c.PostForm("shop_id")
	if rawID == "" {
		c.Error(httpx.NewValidation("shop_id required", nil))
		return
	}
	shopID, ok := h.assertOwner(c, rawID, h.ownerOfShop)
	if !ok {
		return
	}
	data, ct, err := h.readImage(c, "image")
	if err != nil {
		c.Error(err)
		return
	}
	key := fmt.Sprintf("images/shops/%s/banner%s", shopID, extFromCT(ct))
	url, err := h.r2.Upload(c.Request.Context(), key, ct, data)
	if err != nil {
		c.Error(httpx.NewInternal("r2 upload", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"url": url, "key": key})
}

func (h *UploadHandler) liveCover(c *gin.Context) {
	rawID := c.PostForm("session_id")
	if rawID == "" {
		c.Error(httpx.NewValidation("session_id required", nil))
		return
	}
	sessionID, ok := h.assertOwner(c, rawID, h.ownerOfSession)
	if !ok {
		return
	}
	data, ct, err := h.readImage(c, "image")
	if err != nil {
		c.Error(err)
		return
	}
	key := fmt.Sprintf("images/live-covers/%s/cover%s", sessionID, extFromCT(ct))
	url, err := h.r2.Upload(c.Request.Context(), key, ct, data)
	if err != nil {
		c.Error(httpx.NewInternal("r2 upload", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"url": url, "key": key})
}

func (h *UploadHandler) temp(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	data, ct, err := h.readImage(c, "image")
	if err != nil {
		c.Error(err)
		return
	}
	key := fmt.Sprintf("images/temp/%s/%d%s", uid, time.Now().UnixNano(), extFromCT(ct))
	url, err := h.r2.Upload(c.Request.Context(), key, ct, data)
	if err != nil {
		c.Error(httpx.NewInternal("r2 upload", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"url": url, "key": key})
}

func extFromCT(ct string) string {
	switch ct {
	case "image/jpeg":
		return ".jpg"
	case "image/png":
		return ".png"
	case "image/webp":
		return ".webp"
	}
	return ""
}
