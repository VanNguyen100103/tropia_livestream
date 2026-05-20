package storage

import (
	"fmt"
	"io"
	"net/http"
	"path"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/tropia/backend/internal/auth"
	"github.com/tropia/backend/internal/httpx"
)

type UploadHandler struct {
	r2 *R2
}

func NewUploadHandler(r2 *R2) *UploadHandler {
	return &UploadHandler{r2: r2}
}

func (h *UploadHandler) Register(r *gin.RouterGroup, authMw, sellerMw gin.HandlerFunc) {
	authed := r.Group("/", authMw)
	authed.POST("/avatar", h.avatar)

	seller := r.Group("/", authMw, sellerMw)
	seller.POST("/product", h.product)
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
	key := fmt.Sprintf("avatars/%s%s", uid, extFromCT(ct))
	url, err := h.r2.Upload(c.Request.Context(), key, ct, data)
	if err != nil {
		c.Error(httpx.NewInternal("r2 upload", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"url": url, "key": key})
}

func (h *UploadHandler) product(c *gin.Context) {
	productID := c.PostForm("product_id")
	if productID == "" {
		c.Error(httpx.NewValidation("product_id required", nil))
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
		key := fmt.Sprintf("products/%s/%d_%d%s", productID, time.Now().UnixNano(), i, ext)
		url, err := h.r2.Upload(c.Request.Context(), key, ct, data)
		if err != nil {
			continue
		}
		urls = append(urls, url)
	}
	c.JSON(http.StatusOK, gin.H{"urls": urls})
}

func (h *UploadHandler) shop(c *gin.Context) {
	shopID := c.PostForm("shop_id")
	if shopID == "" {
		c.Error(httpx.NewValidation("shop_id required", nil))
		return
	}
	data, ct, err := h.readImage(c, "image")
	if err != nil {
		c.Error(err)
		return
	}
	key := fmt.Sprintf("shops/%s/banner%s", shopID, extFromCT(ct))
	url, err := h.r2.Upload(c.Request.Context(), key, ct, data)
	if err != nil {
		c.Error(httpx.NewInternal("r2 upload", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"url": url, "key": key})
}

func (h *UploadHandler) liveCover(c *gin.Context) {
	sessionID := c.PostForm("session_id")
	if sessionID == "" {
		c.Error(httpx.NewValidation("session_id required", nil))
		return
	}
	data, ct, err := h.readImage(c, "image")
	if err != nil {
		c.Error(err)
		return
	}
	key := fmt.Sprintf("live/%s/cover%s", sessionID, extFromCT(ct))
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
	key := fmt.Sprintf("temp/%s/%d%s", uid, time.Now().UnixNano(), extFromCT(ct))
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
