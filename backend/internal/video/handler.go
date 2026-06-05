package video

import (
	"context"
	"errors"
	"io"
	"net/http"
	"path"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/tropia/backend/internal/auth"
	"github.com/tropia/backend/internal/cache"
	"github.com/tropia/backend/internal/httpx"
)

// ShopResolver resolves the shop a user may post for (shop owner, or an
// approved member with can_live). Satisfied by *live.ShopMemberRepository —
// declared here as a local interface so this package doesn't import live.
type ShopResolver interface {
	AuthorizedShop(ctx context.Context, userID uuid.UUID) (uuid.UUID, bool, error)
}

type Handler struct {
	repo  *Repository
	store MediaStore
	cache *cache.Cache
	shops ShopResolver
}

func NewHandler(repo *Repository, store MediaStore, cc *cache.Cache, shops ShopResolver) *Handler {
	return &Handler{repo: repo, store: store, cache: cc, shops: shops}
}

func (h *Handler) Register(r *gin.RouterGroup, authMw, optAuthMw, liveGate, adminMw gin.HandlerFunc) {
	viewLimit := httpx.RateLimit(h.cache, httpx.RateLimitConfig{Limit: 240, WindowMs: 60 * 1000, FailClosed: false})
	commentLimit := httpx.RateLimit(h.cache, httpx.RateLimitConfig{Limit: 30, WindowMs: 60 * 1000, FailClosed: false})
	reportLimit := httpx.RateLimit(h.cache, httpx.RateLimitConfig{Limit: 20, WindowMs: 60 * 1000, FailClosed: false})
	uploadLimit := httpx.RateLimit(h.cache, httpx.RateLimitConfig{Limit: 20, WindowMs: 60 * 60 * 1000, FailClosed: false})

	// Public reads. optAuth so liked/following populate when a token is sent.
	pub := r.Group("/videos", optAuthMw)
	pub.GET("/feed", h.feed)
	pub.GET("/hashtags", h.hashtags)
	pub.GET("/user/:userId", h.byUser)
	pub.GET("/:id", h.getOne)
	pub.GET("/:id/comments", h.listComments)
	pub.POST("/:id/view", viewLimit, h.incView)
	pub.POST("/:id/share", h.incShare)

	// Authenticated interactions (any logged-in user).
	authed := r.Group("/videos", authMw)
	authed.GET("/following", h.following)
	authed.GET("/me", h.myVideos)
	authed.POST("/:id/like", h.like)
	authed.DELETE("/:id/like", h.unlike)
	authed.POST("/:id/comments", commentLimit, h.addComment)
	authed.POST("/:id/report", reportLimit, h.report)
	authed.POST("/creators/:userId/follow", h.follow)
	authed.DELETE("/creators/:userId/follow", h.unfollow)

	// Posting — gated by the same live-permission rule as livestreaming
	// (shop owner / approved member / admin).
	post := r.Group("/videos", authMw, liveGate)
	post.POST("/upload", uploadLimit, h.upload)
	post.POST("", h.create)
	post.DELETE("/:id", h.delete)

	// Moderation queue — admin only. Registered as a SEPARATE top-level
	// resource (not /videos/reports) to avoid colliding with the /videos/:id
	// param route in gin's router tree.
	adm := r.Group("/video-reports", authMw, adminMw)
	adm.GET("", h.listReports)
	adm.POST("/:reportId/resolve", h.resolveReport)
}

// ── helpers ──────────────────────────────────────────────────────────────────

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

// viewerID is the caller's id, or uuid.Nil for anonymous requests (public
// routes use it to compute liked/following).
func viewerID(c *gin.Context) uuid.UUID {
	id, _ := callerUID(c)
	return id
}

func isAdmin(c *gin.Context) bool {
	claims, ok := auth.ClaimsFrom(c)
	return ok && claims.Role == auth.RoleAdmin
}

func paging(c *gin.Context) (limit, offset int) {
	limit = 10
	if v, err := strconv.Atoi(c.Query("limit")); err == nil && v > 0 {
		limit = v
	}
	if limit > 50 {
		limit = 50
	}
	if v, err := strconv.Atoi(c.Query("offset")); err == nil && v >= 0 {
		offset = v
	} else if p, err := strconv.Atoi(c.Query("page")); err == nil && p > 1 {
		offset = (p - 1) * limit
	}
	return limit, offset
}

func parseID(c *gin.Context, name string) (uuid.UUID, bool) {
	id, err := uuid.Parse(c.Param(name))
	if err != nil {
		c.Error(httpx.NewValidation("invalid "+name, nil))
		return uuid.Nil, false
	}
	return id, true
}

// clampRunes truncates s to at most max runes (not bytes, so multibyte
// Vietnamese isn't cut mid-character).
func clampRunes(s string, max int) string {
	r := []rune(s)
	if len(r) <= max {
		return s
	}
	return string(r[:max])
}

// ── read endpoints ───────────────────────────────────────────────────────────

func (h *Handler) feed(c *gin.Context) {
	limit, offset := paging(c)
	vids, err := h.repo.Feed(c.Request.Context(), viewerID(c), limit, offset)
	if err != nil {
		c.Error(httpx.NewInternal("video feed", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"videos": vids})
}

// hashtags powers the publish composer's "#" autocomplete. q="" → trending;
// q="ngoc" → tags starting with "ngoc". A leading '#' on q is tolerated.
func (h *Handler) hashtags(c *gin.Context) {
	q := clampRunes(strings.TrimSpace(strings.TrimPrefix(c.Query("q"), "#")), maxHashtagRunes)
	limit := 10
	if v, err := strconv.Atoi(c.Query("limit")); err == nil && v > 0 {
		limit = v
	}
	if limit > 20 {
		limit = 20
	}
	tags, err := h.repo.Hashtags(c.Request.Context(), q, limit)
	if err != nil {
		c.Error(httpx.NewInternal("hashtag suggest", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"hashtags": tags})
}

func (h *Handler) byUser(c *gin.Context) {
	uid, ok := parseID(c, "userId")
	if !ok {
		return
	}
	limit, offset := paging(c)
	vids, err := h.repo.ByUser(c.Request.Context(), viewerID(c), uid, limit, offset)
	if err != nil {
		c.Error(httpx.NewInternal("user videos", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"videos": vids})
}

func (h *Handler) getOne(c *gin.Context) {
	id, ok := parseID(c, "id")
	if !ok {
		return
	}
	v, err := h.repo.GetByID(c.Request.Context(), viewerID(c), id)
	if errors.Is(err, ErrNotFound) {
		c.Error(httpx.NewNotFound("video not found"))
		return
	}
	if err != nil {
		c.Error(httpx.NewInternal("get video", err))
		return
	}
	c.JSON(http.StatusOK, v)
}

func (h *Handler) listComments(c *gin.Context) {
	id, ok := parseID(c, "id")
	if !ok {
		return
	}
	limit, offset := paging(c)
	cs, err := h.repo.ListComments(c.Request.Context(), id, limit, offset)
	if err != nil {
		c.Error(httpx.NewInternal("list comments", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"comments": cs})
}

func (h *Handler) incView(c *gin.Context) {
	id, ok := parseID(c, "id")
	if !ok {
		return
	}
	// Deduped per logged-in user; anonymous still counts (rate-limited).
	_ = h.repo.RecordView(c.Request.Context(), id, viewerID(c))
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

func (h *Handler) incShare(c *gin.Context) {
	id, ok := parseID(c, "id")
	if !ok {
		return
	}
	_ = h.repo.IncShare(c.Request.Context(), id)
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

func (h *Handler) following(c *gin.Context) {
	uid, ok := callerUID(c)
	if !ok {
		c.Error(httpx.NewAuth("unauthenticated"))
		return
	}
	limit, offset := paging(c)
	vids, err := h.repo.Following(c.Request.Context(), uid, limit, offset)
	if err != nil {
		c.Error(httpx.NewInternal("following feed", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"videos": vids})
}

func (h *Handler) myVideos(c *gin.Context) {
	uid, ok := callerUID(c)
	if !ok {
		c.Error(httpx.NewAuth("unauthenticated"))
		return
	}
	limit, offset := paging(c)
	vids, err := h.repo.ByUser(c.Request.Context(), uid, uid, limit, offset)
	if err != nil {
		c.Error(httpx.NewInternal("my videos", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"videos": vids})
}

// ── interactions ─────────────────────────────────────────────────────────────

func (h *Handler) like(c *gin.Context)   { h.setLike(c, true) }
func (h *Handler) unlike(c *gin.Context) { h.setLike(c, false) }

func (h *Handler) setLike(c *gin.Context, liked bool) {
	uid, ok := callerUID(c)
	if !ok {
		c.Error(httpx.NewAuth("unauthenticated"))
		return
	}
	id, ok := parseID(c, "id")
	if !ok {
		return
	}
	exists, err := h.repo.Exists(c.Request.Context(), id)
	if err != nil {
		c.Error(httpx.NewInternal("check video", err))
		return
	}
	if !exists {
		c.Error(httpx.NewNotFound("video not found"))
		return
	}
	var count int
	if liked {
		count, err = h.repo.Like(c.Request.Context(), id, uid)
	} else {
		count, err = h.repo.Unlike(c.Request.Context(), id, uid)
	}
	if err != nil {
		c.Error(httpx.NewInternal("toggle like", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"liked": liked, "like_count": count})
}

type commentReq struct {
	Content string `json:"content" binding:"required,min=1,max=500"`
}

func (h *Handler) addComment(c *gin.Context) {
	uid, ok := callerUID(c)
	if !ok {
		c.Error(httpx.NewAuth("unauthenticated"))
		return
	}
	id, ok := parseID(c, "id")
	if !ok {
		return
	}
	var req commentReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	exists, err := h.repo.Exists(c.Request.Context(), id)
	if err != nil {
		c.Error(httpx.NewInternal("check video", err))
		return
	}
	if !exists {
		c.Error(httpx.NewNotFound("video not found"))
		return
	}
	cm, err := h.repo.AddComment(c.Request.Context(), id, uid, httpx.CleanString(strings.TrimSpace(req.Content)))
	if err != nil {
		c.Error(httpx.NewInternal("add comment", err))
		return
	}
	c.JSON(http.StatusOK, cm)
}

func (h *Handler) follow(c *gin.Context)   { h.setFollow(c, true) }
func (h *Handler) unfollow(c *gin.Context) { h.setFollow(c, false) }

func (h *Handler) setFollow(c *gin.Context, follow bool) {
	uid, ok := callerUID(c)
	if !ok {
		c.Error(httpx.NewAuth("unauthenticated"))
		return
	}
	target, ok := parseID(c, "userId")
	if !ok {
		return
	}
	if target == uid {
		c.Error(httpx.NewValidation("không thể tự theo dõi chính mình", nil))
		return
	}
	var following bool
	var err error
	if follow {
		following, err = h.repo.Follow(c.Request.Context(), uid, target)
	} else {
		following, err = h.repo.Unfollow(c.Request.Context(), uid, target)
	}
	if errors.Is(err, ErrNotFound) {
		c.Error(httpx.NewNotFound("creator not found"))
		return
	}
	if err != nil {
		c.Error(httpx.NewInternal("toggle follow", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"following": following})
}

// ── moderation ───────────────────────────────────────────────────────────────

type reportReq struct {
	Reason string `json:"reason" binding:"required,min=1,max=200"`
}

func (h *Handler) report(c *gin.Context) {
	uid, ok := callerUID(c)
	if !ok {
		c.Error(httpx.NewAuth("unauthenticated"))
		return
	}
	id, ok := parseID(c, "id")
	if !ok {
		return
	}
	var req reportReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	exists, err := h.repo.Exists(c.Request.Context(), id)
	if err != nil {
		c.Error(httpx.NewInternal("check video", err))
		return
	}
	if !exists {
		c.Error(httpx.NewNotFound("video not found"))
		return
	}
	if err := h.repo.AddReport(c.Request.Context(), id, uid, httpx.CleanString(strings.TrimSpace(req.Reason))); err != nil {
		if errors.Is(err, ErrNotFound) {
			c.Error(httpx.NewNotFound("video not found"))
			return
		}
		c.Error(httpx.NewInternal("add report", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

func (h *Handler) listReports(c *gin.Context) {
	status := strings.TrimSpace(c.Query("status"))
	if status == "" {
		status = "pending"
	}
	if status == "all" {
		status = ""
	}
	limit, offset := paging(c)
	reports, err := h.repo.ListReports(c.Request.Context(), status, limit, offset)
	if err != nil {
		c.Error(httpx.NewInternal("list reports", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"reports": reports})
}

type resolveReq struct {
	Action string `json:"action" binding:"required,oneof=takedown dismiss"`
}

func (h *Handler) resolveReport(c *gin.Context) {
	uid, ok := callerUID(c)
	if !ok {
		c.Error(httpx.NewAuth("unauthenticated"))
		return
	}
	id, ok := parseID(c, "reportId")
	if !ok {
		return
	}
	var req resolveReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	err := h.repo.ResolveReport(c.Request.Context(), id, uid, req.Action == "takedown")
	if errors.Is(err, ErrNotFound) {
		c.Error(httpx.NewNotFound("report not found"))
		return
	}
	if err != nil {
		c.Error(httpx.NewInternal("resolve report", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// ── posting ──────────────────────────────────────────────────────────────────

const (
	maxVideoBytes = 50 << 20 // 50MB per clip
	maxThumbBytes = 5 << 20  // 5MB per cover
	// Hard cap on the whole multipart body. /api/videos/upload is exempt from
	// the global RequestSizeGuard (it carries large files), so without this a
	// client could stream gigabytes → disk/RAM exhaustion (DoS). MaxBytesReader
	// makes reads past the cap fail, and FormFile/ReadAll then error out.
	maxUploadRequestBytes = 60 << 20
	maxCaptionRunes       = 2200
	maxHashtagRunes       = 50
	maxHashtags           = 20
	maxVideoProducts      = 20 // tagged products per clip
	maxVideoCoupons       = 10 // featured coupons per clip
)

var allowedVideoExts = map[string]string{
	".mp4": "video/mp4",
	".mov": "video/quicktime",
}

var allowedThumbExts = map[string]string{
	".jpg":  "image/jpeg",
	".jpeg": "image/jpeg",
	".png":  "image/png",
	".webp": "image/webp",
}

// looksLikeVideo verifies the MP4/MOV "ftyp" box at offset 4 so a renamed
// non-video (HTML/SVG/script) can't be stored and later served. Extension +
// content-type checks alone are spoofable.
func looksLikeVideo(b []byte) bool {
	return len(b) >= 12 && string(b[4:8]) == "ftyp"
}

// looksLikeImage matches the magic bytes of the cover formats we accept.
func looksLikeImage(b []byte) bool {
	switch {
	case len(b) >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF: // JPEG
		return true
	case len(b) >= 8 && string(b[0:8]) == "\x89PNG\r\n\x1a\n": // PNG
		return true
	case len(b) >= 12 && string(b[0:4]) == "RIFF" && string(b[8:12]) == "WEBP": // WEBP
		return true
	}
	return false
}

// upload stores the MP4 (and an optional cover image) and returns their URLs.
// The client then POSTs /api/videos with these URLs + caption/hashtags.
func (h *Handler) upload(c *gin.Context) {
	// Hard-cap the whole request body (this route is exempt from the global
	// RequestSizeGuard). Reads past the cap fail, so FormFile below errors out
	// instead of buffering an attacker's multi-GB upload.
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxUploadRequestBytes)

	file, header, err := c.Request.FormFile("video")
	if err != nil {
		c.Error(httpx.NewValidation("thiếu hoặc video quá lớn", nil))
		return
	}
	defer file.Close()
	if header.Size > maxVideoBytes {
		c.Error(httpx.NewValidation("video quá lớn (tối đa 50MB)", nil))
		return
	}
	ext := strings.ToLower(path.Ext(header.Filename))
	ct, ok := allowedVideoExts[ext]
	if !ok {
		c.Error(httpx.NewValidation("chỉ chấp nhận mp4/mov", nil))
		return
	}
	data, err := io.ReadAll(file)
	if err != nil {
		// MaxBytesReader trips here when the real bytes exceed the cap even if
		// the declared Content-Length was small (spoofed header.Size).
		c.Error(httpx.NewValidation("không đọc được video (có thể quá lớn)", nil))
		return
	}
	if len(data) > maxVideoBytes {
		c.Error(httpx.NewValidation("video quá lớn (tối đa 50MB)", nil))
		return
	}
	if !looksLikeVideo(data) {
		c.Error(httpx.NewValidation("tệp không phải video hợp lệ (mp4/mov)", nil))
		return
	}
	vid := uuid.NewString()
	videoURL, err := h.store.Save(c.Request.Context(), "videos/"+vid+ext, ct, data)
	if err != nil {
		c.Error(httpx.NewInternal("save video", err))
		return
	}
	resp := gin.H{"video_url": videoURL}

	// Optional cover image — same content validation.
	if tf, th, terr := c.Request.FormFile("thumbnail"); terr == nil {
		defer tf.Close()
		text := strings.ToLower(path.Ext(th.Filename))
		if tct, okT := allowedThumbExts[text]; okT && th.Size <= maxThumbBytes {
			if tdata, e := io.ReadAll(tf); e == nil && len(tdata) <= maxThumbBytes && looksLikeImage(tdata) {
				if turl, e2 := h.store.Save(c.Request.Context(), "videos/"+vid+"_thumb"+text, tct, tdata); e2 == nil {
					resp["thumbnail_url"] = turl
				}
			}
		}
	}
	c.JSON(http.StatusOK, resp)
}

type createReq struct {
	VideoURL     string   `json:"video_url" binding:"required"`
	ThumbnailURL string   `json:"thumbnail_url"`
	Caption      string   `json:"caption"`
	Hashtags     []string `json:"hashtags"`
	DurationSec  int      `json:"duration_sec"`
	Width        int      `json:"width"`
	Height       int      `json:"height"`
	AllowReuse   *bool    `json:"allow_reuse"`
	// Catalog product ids to tag on the clip ("Xem sản phẩm"). The repo
	// validates each belongs to the poster's shop, so a bad/foreign id is
	// dropped rather than rejected.
	ProductIDs []string `json:"product_ids"`
	// Seller coupon ids to feature on the clip ("Voucher"). The repo validates
	// each belongs to the poster's shop, so a bad/foreign id is dropped.
	CouponIDs []string `json:"coupon_ids"`
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
	allow := true
	if req.AllowReuse != nil {
		allow = *req.AllowReuse
	}
	// Only accept media URLs we actually issued from an upload — never an
	// arbitrary client-supplied URL (would let a poster point the feed at any
	// external resource: content injection / viewer-IP tracking).
	videoURL := strings.TrimSpace(req.VideoURL)
	if !h.store.Owns(videoURL) {
		c.Error(httpx.NewValidation("video_url không hợp lệ (phải là tệp đã upload)", nil))
		return
	}
	thumbURL := strings.TrimSpace(req.ThumbnailURL)
	if thumbURL != "" && !h.store.Owns(thumbURL) {
		c.Error(httpx.NewValidation("thumbnail_url không hợp lệ", nil))
		return
	}
	// Resolve the poster's shop (nil for admin with no shop). The liveGate
	// already verified they may post; this only attributes the clip.
	var shopID *uuid.UUID
	if h.shops != nil {
		if sid, okShop, err := h.shops.AuthorizedShop(c.Request.Context(), uid); err == nil && okShop {
			shopID = &sid
		}
	}
	// Normalise hashtags: strip leading '#', drop blanks, clamp length + count.
	tags := make([]string, 0, len(req.Hashtags))
	for _, t := range req.Hashtags {
		t = httpx.CleanString(strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(t), "#")))
		if t == "" {
			continue
		}
		tags = append(tags, clampRunes(t, maxHashtagRunes))
		if len(tags) >= maxHashtags {
			break
		}
	}
	// Parse + dedupe tagged product ids (ownership is enforced in the repo).
	productIDs := make([]uuid.UUID, 0, len(req.ProductIDs))
	seenProd := make(map[uuid.UUID]bool)
	for _, s := range req.ProductIDs {
		pid, perr := uuid.Parse(strings.TrimSpace(s))
		if perr != nil || seenProd[pid] {
			continue
		}
		seenProd[pid] = true
		productIDs = append(productIDs, pid)
		if len(productIDs) >= maxVideoProducts {
			break
		}
	}
	// Parse + dedupe featured coupon ids (ownership is enforced in the repo).
	couponIDs := make([]uuid.UUID, 0, len(req.CouponIDs))
	seenCoupon := make(map[uuid.UUID]bool)
	for _, s := range req.CouponIDs {
		cid, cerr := uuid.Parse(strings.TrimSpace(s))
		if cerr != nil || seenCoupon[cid] {
			continue
		}
		seenCoupon[cid] = true
		couponIDs = append(couponIDs, cid)
		if len(couponIDs) >= maxVideoCoupons {
			break
		}
	}
	v, err := h.repo.Create(c.Request.Context(), CreateParams{
		UserID:       uid,
		ShopID:       shopID,
		VideoURL:     videoURL,
		ThumbnailURL: thumbURL,
		Caption:      clampRunes(httpx.CleanString(strings.TrimSpace(req.Caption)), maxCaptionRunes),
		Hashtags:     tags,
		DurationSec:  req.DurationSec,
		Width:        req.Width,
		Height:       req.Height,
		AllowReuse:   allow,
		ProductIDs:   productIDs,
		CouponIDs:    couponIDs,
	})
	if err != nil {
		c.Error(httpx.NewInternal("create video", err))
		return
	}
	c.JSON(http.StatusCreated, v)
}

func (h *Handler) delete(c *gin.Context) {
	uid, ok := callerUID(c)
	if !ok {
		c.Error(httpx.NewAuth("unauthenticated"))
		return
	}
	id, ok := parseID(c, "id")
	if !ok {
		return
	}
	err := h.repo.SoftDelete(c.Request.Context(), id, uid, isAdmin(c))
	if errors.Is(err, ErrNotFound) {
		c.Error(httpx.NewNotFound("video not found"))
		return
	}
	if err != nil {
		c.Error(httpx.NewInternal("delete video", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}
