package video

import (
	"context"
	"errors"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrNotFound signals a missing (or soft-deleted) video. Handlers translate it
// into 404 — and for owner-scoped actions, that also avoids leaking which ids
// exist (BOLA defense, same as live/session_repo.go).
var ErrNotFound = errors.New("video: not found")

type Repository struct{ pool *pgxpool.Pool }

func NewRepository(pool *pgxpool.Pool) *Repository { return &Repository{pool: pool} }

// videoCols is the shared SELECT list for the JOINed read queries. $1 is always
// the viewer id (uuid.Nil for anonymous) — used to compute liked / following.
const videoCols = `
	v.id, v.user_id, v.shop_id, v.video_url, v.thumbnail_url, v.caption, v.hashtags,
	v.duration_sec, v.width, v.height, v.allow_reuse, v.status,
	v.view_count, v.like_count, v.comment_count, v.share_count, v.created_at,
	p.name, p.avatar_url, s.name, s.slug, s.logo_url,
	($1 <> '00000000-0000-0000-0000-000000000000'::uuid
		AND EXISTS (SELECT 1 FROM video_likes vl WHERE vl.video_id = v.id AND vl.user_id = $1)) AS liked,
	($1 <> '00000000-0000-0000-0000-000000000000'::uuid
		AND EXISTS (SELECT 1 FROM user_follows uf WHERE uf.follower_id = $1 AND uf.followee_id = v.user_id)) AS following,
	($1 <> '00000000-0000-0000-0000-000000000000'::uuid
		AND v.shop_id IS NOT NULL
		AND EXISTS (SELECT 1 FROM shop_follows sf WHERE sf.user_id = $1 AND sf.shop_id = v.shop_id)) AS shop_following,
	(v.shop_id IS NOT NULL
		AND EXISTS (SELECT 1 FROM coupons c
		             WHERE c.shop_id = v.shop_id AND c.is_active AND c.expires_at > NOW())) AS shop_has_voucher,
	v.overlay_url`

const videoFrom = `
	FROM videos v
	LEFT JOIN profiles p ON p.id = v.user_id
	LEFT JOIN shops    s ON s.id = v.shop_id`

func scanVideo(row pgx.Row, v *Video) error {
	return row.Scan(
		&v.ID, &v.UserID, &v.ShopID, &v.VideoURL, &v.ThumbnailURL, &v.Caption, &v.Hashtags,
		&v.DurationSec, &v.Width, &v.Height, &v.AllowReuse, &v.Status,
		&v.ViewCount, &v.LikeCount, &v.CommentCount, &v.ShareCount, &v.CreatedAt,
		&v.UserName, &v.UserAvatar, &v.ShopName, &v.ShopSlug, &v.ShopAvatar,
		&v.Liked, &v.Following, &v.ShopFollowing, &v.ShopHasVoucher,
		&v.OverlayURL,
	)
}

func (r *Repository) collect(ctx context.Context, q string, args ...any) ([]Video, error) {
	rows, err := r.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]Video, 0)
	for rows.Next() {
		var v Video
		if err := scanVideo(rows, &v); err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	out, err = r.fillProducts(ctx, out)
	if err != nil {
		return nil, err
	}
	return r.fillCoupons(ctx, out)
}

// CreateParams holds the fields for a new video record (the binary is already
// uploaded; video_url points at it).
type CreateParams struct {
	UserID       uuid.UUID
	ShopID       *uuid.UUID
	VideoURL     string
	ThumbnailURL string
	Caption      string
	Hashtags     []string
	DurationSec  int
	Width        int
	Height       int
	AllowReuse   bool
	// Catalog product ids to tag on the clip, in display order. Validated +
	// filtered to the poster's own shop in attachProducts (see below).
	ProductIDs []uuid.UUID
	// Seller coupon ids to feature on the clip, in display order. Validated +
	// filtered to the poster's own shop in attachCoupons (see below).
	CouponIDs []uuid.UUID
}

func (r *Repository) Create(ctx context.Context, p CreateParams) (*Video, error) {
	if p.Hashtags == nil {
		p.Hashtags = []string{}
	}
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	const q = `
		INSERT INTO videos
			(user_id, shop_id, video_url, thumbnail_url, caption, hashtags,
			 duration_sec, width, height, allow_reuse)
		VALUES ($1, $2, $3, NULLIF($4, ''), NULLIF($5, ''), $6, $7, $8, $9, $10)
		RETURNING id`
	var id uuid.UUID
	if err := tx.QueryRow(ctx, q,
		p.UserID, p.ShopID, p.VideoURL, p.ThumbnailURL, p.Caption, p.Hashtags,
		p.DurationSec, p.Width, p.Height, p.AllowReuse,
	).Scan(&id); err != nil {
		return nil, err
	}
	if len(p.ProductIDs) > 0 {
		if err := attachProducts(ctx, tx, id, p.ShopID, p.ProductIDs); err != nil {
			return nil, err
		}
	}
	if len(p.CouponIDs) > 0 {
		if err := attachCoupons(ctx, tx, id, p.ShopID, p.CouponIDs); err != nil {
			return nil, err
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return r.GetByID(ctx, p.UserID, id)
}

// attachProducts links catalog products to a video in the supplied order
// (sort_order = index). Only ACTIVE products the poster is allowed to tag are
// linked: products of their own shop, or — for an admin poster with no shop
// (shopID == nil) — any active product. Unknown / foreign / inactive / duplicate
// ids are silently skipped so a stale client selection can't fail the whole
// publish.
func attachProducts(ctx context.Context, tx pgx.Tx, videoID uuid.UUID, shopID *uuid.UUID, productIDs []uuid.UUID) error {
	// Resolve the subset the poster may actually tag.
	const sel = `
		SELECT id FROM products
		 WHERE id = ANY($1) AND status = 'active'
		   AND ($2::uuid IS NULL OR shop_id = $2)`
	rows, err := tx.Query(ctx, sel, productIDs, shopID)
	if err != nil {
		return err
	}
	allowed := make(map[uuid.UUID]bool)
	for rows.Next() {
		var id uuid.UUID
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return err
		}
		allowed[id] = true
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}

	order := 0
	seen := make(map[uuid.UUID]bool)
	for _, pid := range productIDs {
		if !allowed[pid] || seen[pid] {
			continue
		}
		seen[pid] = true
		if _, err := tx.Exec(ctx,
			`INSERT INTO video_products (video_id, product_id, sort_order)
			 VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`,
			videoID, pid, order); err != nil {
			return err
		}
		order++
	}
	return nil
}

// attachCoupons links seller coupons to a video in the supplied order
// (sort_order = index). Only coupons the poster may feature are linked: active,
// non-expired coupons that belong to the poster's shop — directly (shop_id) or
// via one of the shop's live sessions (the same ownership rule as
// CouponRepository.ListByShop). An admin poster with no shop (shopID == nil) may
// feature any active coupon. Unknown / foreign / expired / duplicate ids are
// silently skipped so a stale client selection can't fail the whole publish.
func attachCoupons(ctx context.Context, tx pgx.Tx, videoID uuid.UUID, shopID *uuid.UUID, couponIDs []uuid.UUID) error {
	// Resolve the subset the poster may actually feature.
	const sel = `
		SELECT c.id FROM coupons c
		 WHERE c.id = ANY($1) AND c.is_active AND c.expires_at > NOW()
		   AND ($2::uuid IS NULL
		        OR c.shop_id = $2
		        OR c.session_id IN (
		               SELECT ls.id FROM live_sessions ls
		               JOIN shops s ON s.seller_id = ls.seller_id
		               WHERE s.id = $2))`
	rows, err := tx.Query(ctx, sel, couponIDs, shopID)
	if err != nil {
		return err
	}
	allowed := make(map[uuid.UUID]bool)
	for rows.Next() {
		var id uuid.UUID
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return err
		}
		allowed[id] = true
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}

	order := 0
	seen := make(map[uuid.UUID]bool)
	for _, cid := range couponIDs {
		if !allowed[cid] || seen[cid] {
			continue
		}
		seen[cid] = true
		if _, err := tx.Exec(ctx,
			`INSERT INTO video_coupons (video_id, coupon_id, sort_order)
			 VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`,
			videoID, cid, order); err != nil {
			return err
		}
		order++
	}
	return nil
}

// productsForVideos batch-loads tagged products for many videos at once (avoids
// N+1 in the feed). Display fields come live from `products`; a product that was
// since deleted/deactivated simply drops out of the result.
func (r *Repository) productsForVideos(ctx context.Context, videoIDs []uuid.UUID) (map[uuid.UUID][]VideoProduct, error) {
	out := make(map[uuid.UUID][]VideoProduct, len(videoIDs))
	if len(videoIDs) == 0 {
		return out, nil
	}
	// LEFT JOIN LATERAL picks each product's currently-live flash-sale slot (if
	// any): lowest flash price wins, soonest-ending as tiebreaker. A slot whose
	// per-sale stock is exhausted (sold_count >= stock_limit) is excluded.
	const q = `
		SELECT vp.video_id, p.id, p.name, p.slug, (p.images)[1],
		       p.base_price, p.sale_price, p.total_sold, p.rating, p.review_count,
		       fs.flash_price, fs.ends_at
		FROM video_products vp
		JOIN products p ON p.id = vp.product_id AND p.status = 'active'
		LEFT JOIN LATERAL (
			SELECT fsp.flash_price, sale.ends_at
			FROM flash_sale_products fsp
			JOIN flash_sales sale ON sale.id = fsp.flash_sale_id
			WHERE fsp.product_id = p.id
			  AND sale.is_active
			  AND sale.starts_at <= NOW() AND sale.ends_at > NOW()
			  AND (fsp.stock_limit IS NULL OR fsp.sold_count < fsp.stock_limit)
			ORDER BY fsp.flash_price ASC, sale.ends_at ASC
			LIMIT 1
		) fs ON TRUE
		WHERE vp.video_id = ANY($1)
		ORDER BY vp.video_id, vp.sort_order`
	rows, err := r.pool.Query(ctx, q, videoIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var vid uuid.UUID
		var vp VideoProduct
		if err := rows.Scan(&vid, &vp.ProductID, &vp.Name, &vp.Slug, &vp.ImageURL,
			&vp.BasePrice, &vp.SalePrice, &vp.TotalSold, &vp.Rating, &vp.ReviewCount,
			&vp.FlashPrice, &vp.FlashEndsAt); err != nil {
			return nil, err
		}
		out[vid] = append(out[vid], vp)
	}
	return out, rows.Err()
}

// fillProducts populates the Products slice on each video (always non-nil so the
// JSON field is [] rather than null).
func (r *Repository) fillProducts(ctx context.Context, vids []Video) ([]Video, error) {
	if len(vids) == 0 {
		return vids, nil
	}
	ids := make([]uuid.UUID, len(vids))
	for i := range vids {
		ids[i] = vids[i].ID
	}
	byVideo, err := r.productsForVideos(ctx, ids)
	if err != nil {
		return nil, err
	}
	for i := range vids {
		if ps := byVideo[vids[i].ID]; ps != nil {
			vids[i].Products = ps
		} else {
			vids[i].Products = []VideoProduct{}
		}
	}
	return vids, nil
}

// couponsForVideos batch-loads featured coupons for many videos at once (avoids
// N+1 in the feed). Display fields come live from `coupons`; a coupon that since
// expired or was deactivated drops out of the result.
func (r *Repository) couponsForVideos(ctx context.Context, videoIDs []uuid.UUID) (map[uuid.UUID][]VideoCoupon, error) {
	out := make(map[uuid.UUID][]VideoCoupon, len(videoIDs))
	if len(videoIDs) == 0 {
		return out, nil
	}
	const q = `
		SELECT vc.video_id, c.id, c.code, c.discount_type, c.discount_value,
		       c.min_order_value, c.max_discount, c.expires_at
		FROM video_coupons vc
		JOIN coupons c ON c.id = vc.coupon_id AND c.is_active AND c.expires_at > NOW()
		WHERE vc.video_id = ANY($1)
		ORDER BY vc.video_id, vc.sort_order`
	rows, err := r.pool.Query(ctx, q, videoIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var vid uuid.UUID
		var vc VideoCoupon
		if err := rows.Scan(&vid, &vc.CouponID, &vc.Code, &vc.DiscountType, &vc.DiscountValue,
			&vc.MinOrderValue, &vc.MaxDiscount, &vc.ExpiresAt); err != nil {
			return nil, err
		}
		out[vid] = append(out[vid], vc)
	}
	return out, rows.Err()
}

// fillCoupons populates the Coupons slice on each video (always non-nil so the
// JSON field is [] rather than null).
func (r *Repository) fillCoupons(ctx context.Context, vids []Video) ([]Video, error) {
	if len(vids) == 0 {
		return vids, nil
	}
	ids := make([]uuid.UUID, len(vids))
	for i := range vids {
		ids[i] = vids[i].ID
	}
	byVideo, err := r.couponsForVideos(ctx, ids)
	if err != nil {
		return nil, err
	}
	for i := range vids {
		if cs := byVideo[vids[i].ID]; cs != nil {
			vids[i].Coupons = cs
		} else {
			vids[i].Coupons = []VideoCoupon{}
		}
	}
	return vids, nil
}

func (r *Repository) GetByID(ctx context.Context, viewerID, id uuid.UUID) (*Video, error) {
	q := `SELECT ` + videoCols + videoFrom + ` WHERE v.id = $2 AND v.status = 'active'`
	var v Video
	if err := scanVideo(r.pool.QueryRow(ctx, q, viewerID, id), &v); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	byVideo, err := r.productsForVideos(ctx, []uuid.UUID{id})
	if err != nil {
		return nil, err
	}
	if v.Products = byVideo[id]; v.Products == nil {
		v.Products = []VideoProduct{}
	}
	byCoupon, err := r.couponsForVideos(ctx, []uuid.UUID{id})
	if err != nil {
		return nil, err
	}
	if v.Coupons = byCoupon[id]; v.Coupons == nil {
		v.Coupons = []VideoCoupon{}
	}
	return &v, nil
}

// Feed is the public "for you" recommendation list: active videos ranked by a
// simple engagement score, newest as tiebreaker. Offset paging is fine at MVP
// volumes.
func (r *Repository) Feed(ctx context.Context, viewerID uuid.UUID, limit, offset int) ([]Video, error) {
	q := `SELECT ` + videoCols + videoFrom + `
		WHERE v.status = 'active'
		ORDER BY (v.like_count * 3 + v.comment_count * 2 + v.view_count * 0.1) DESC,
		         v.created_at DESC
		LIMIT $2 OFFSET $3`
	return r.collect(ctx, q, viewerID, limit, offset)
}

// ByUser lists a creator's active videos, newest first (profile grid).
func (r *Repository) ByUser(ctx context.Context, viewerID, userID uuid.UUID, limit, offset int) ([]Video, error) {
	q := `SELECT ` + videoCols + videoFrom + `
		WHERE v.status = 'active' AND v.user_id = $2
		ORDER BY v.created_at DESC
		LIMIT $3 OFFSET $4`
	return r.collect(ctx, q, viewerID, userID, limit, offset)
}

// Following lists active videos from creators the viewer follows.
func (r *Repository) Following(ctx context.Context, viewerID uuid.UUID, limit, offset int) ([]Video, error) {
	q := `SELECT ` + videoCols + videoFrom + `
		WHERE v.status = 'active'
		  AND v.user_id IN (SELECT followee_id FROM user_follows WHERE follower_id = $1)
		ORDER BY v.created_at DESC
		LIMIT $2 OFFSET $3`
	return r.collect(ctx, q, viewerID, limit, offset)
}

// Liked lists the active videos a user has liked, most-recently-liked first —
// powers the profile "Đã thích" grid. $1 (viewerID) drives the liked/following
// flags; $2 (likerID) selects the likes. When the viewer is browsing their own
// liked tab the two are the same, so every row comes back liked=true. The join
// alias is `lk` to avoid colliding with the `vl` subquery alias in videoCols.
func (r *Repository) Liked(ctx context.Context, viewerID, likerID uuid.UUID, limit, offset int) ([]Video, error) {
	q := `SELECT ` + videoCols + videoFrom + `
		JOIN video_likes lk ON lk.video_id = v.id AND lk.user_id = $2
		WHERE v.status = 'active'
		ORDER BY lk.created_at DESC
		LIMIT $3 OFFSET $4`
	return r.collect(ctx, q, viewerID, likerID, limit, offset)
}

// HashtagSuggestion is a single hashtag plus how many active videos use it and
// their total views — powers the "#" autocomplete in the publish composer
// (Shopee Video shows "<n> lượt xem" next to each suggestion).
type HashtagSuggestion struct {
	Tag        string `json:"tag"`
	VideoCount int    `json:"video_count"`
	ViewCount  int    `json:"view_count"`
}

// Hashtags returns suggestions for the composer's "#" dropdown. With an empty
// query it's the global trending list (most-viewed tags first); with a query
// it's a case-insensitive prefix match. Both video_count and the total
// view_count are aggregated live from active videos' hashtags arrays — there's
// no separate counter table, and the GIN index on hashtags keeps this cheap at
// MVP volumes.
func (r *Repository) Hashtags(ctx context.Context, query string, limit int) ([]HashtagSuggestion, error) {
	const q = `
		SELECT tag, COUNT(*) AS video_count, COALESCE(SUM(view_count), 0)::int AS view_count
		FROM (SELECT unnest(hashtags) AS tag, view_count FROM videos WHERE status = 'active') t
		WHERE ($1 = '' OR left(lower(tag), char_length($1)) = lower($1))
		GROUP BY tag
		ORDER BY view_count DESC, video_count DESC, tag ASC
		LIMIT $2`
	rows, err := r.pool.Query(ctx, q, query, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]HashtagSuggestion, 0)
	for rows.Next() {
		var s HashtagSuggestion
		if err := rows.Scan(&s.Tag, &s.VideoCount, &s.ViewCount); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

// Exists reports whether an active video with this id exists.
func (r *Repository) Exists(ctx context.Context, id uuid.UUID) (bool, error) {
	var x int
	err := r.pool.QueryRow(ctx, `SELECT 1 FROM videos WHERE id = $1 AND status = 'active'`, id).Scan(&x)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	return err == nil, err
}

// SoftDelete marks a video deleted. Only the owner (or admin) succeeds; a
// non-owner gets ErrNotFound so we don't reveal the id exists.
func (r *Repository) SoftDelete(ctx context.Context, id, userID uuid.UUID, isAdmin bool) error {
	tag, err := r.pool.Exec(ctx,
		`UPDATE videos SET status = 'deleted'
		  WHERE id = $1 AND status = 'active' AND ($3 OR user_id = $2)`,
		id, userID, isAdmin)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// ── Overlay bake bookkeeping ──────────────────────────────────────────────────

// SetOverlayStatus moves a video's overlay-bake job through its lifecycle
// ('processing' | 'failed' | 'skipped'). Missing ids are a no-op.
func (r *Repository) SetOverlayStatus(ctx context.Context, id uuid.UUID, status string) error {
	_, err := r.pool.Exec(ctx, `UPDATE videos SET overlay_status = $2 WHERE id = $1`, id, status)
	return err
}

// SetOverlayURL records the baked overlay copy's URL and marks the job 'ready'.
func (r *Repository) SetOverlayURL(ctx context.Context, id uuid.UUID, url string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE videos SET overlay_url = NULLIF($2, ''), overlay_status = 'ready' WHERE id = $1`,
		id, url)
	return err
}

// Like adds a like (idempotent) and returns the resulting like_count.
func (r *Repository) Like(ctx context.Context, id, userID uuid.UUID) (int, error) {
	tag, err := r.pool.Exec(ctx,
		`INSERT INTO video_likes (video_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
		id, userID)
	if err != nil {
		return 0, err
	}
	if tag.RowsAffected() == 1 {
		var c int
		err = r.pool.QueryRow(ctx,
			`UPDATE videos SET like_count = like_count + 1 WHERE id = $1 RETURNING like_count`,
			id).Scan(&c)
		return c, err
	}
	return r.likeCount(ctx, id)
}

// Unlike removes a like (idempotent) and returns the resulting like_count.
func (r *Repository) Unlike(ctx context.Context, id, userID uuid.UUID) (int, error) {
	tag, err := r.pool.Exec(ctx, `DELETE FROM video_likes WHERE video_id = $1 AND user_id = $2`, id, userID)
	if err != nil {
		return 0, err
	}
	if tag.RowsAffected() == 1 {
		var c int
		err = r.pool.QueryRow(ctx,
			`UPDATE videos SET like_count = GREATEST(0, like_count - 1) WHERE id = $1 RETURNING like_count`,
			id).Scan(&c)
		return c, err
	}
	return r.likeCount(ctx, id)
}

func (r *Repository) likeCount(ctx context.Context, id uuid.UUID) (int, error) {
	var c int
	err := r.pool.QueryRow(ctx, `SELECT like_count FROM videos WHERE id = $1`, id).Scan(&c)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, ErrNotFound
	}
	return c, err
}

// IncView / IncShare bump the denormalised counters. Missing/deleted ids are a
// no-op (no error) — view pings are fire-and-forget.
func (r *Repository) IncView(ctx context.Context, id uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `UPDATE videos SET view_count = view_count + 1 WHERE id = $1 AND status = 'active'`, id)
	return err
}

func (r *Repository) IncShare(ctx context.Context, id uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `UPDATE videos SET share_count = share_count + 1 WHERE id = $1 AND status = 'active'`, id)
	return err
}

// AddComment inserts a comment, bumps comment_count, and returns the new row
// with its author display info.
func (r *Repository) AddComment(ctx context.Context, videoID, userID uuid.UUID, content string) (*VideoComment, error) {
	const q = `
		WITH ins AS (
			INSERT INTO video_comments (video_id, user_id, content)
			VALUES ($1, $2, $3)
			RETURNING id, video_id, user_id, content, like_count, created_at
		)
		SELECT ins.id, ins.video_id, ins.user_id, ins.content, ins.like_count, ins.created_at,
		       p.name, p.avatar_url
		FROM ins LEFT JOIN profiles p ON p.id = ins.user_id`
	var c VideoComment
	if err := r.pool.QueryRow(ctx, q, videoID, userID, content).Scan(
		&c.ID, &c.VideoID, &c.UserID, &c.Content, &c.LikeCount, &c.CreatedAt,
		&c.UserName, &c.UserAvatar,
	); err != nil {
		return nil, err
	}
	_, _ = r.pool.Exec(ctx, `UPDATE videos SET comment_count = comment_count + 1 WHERE id = $1`, videoID)
	return &c, nil
}

func (r *Repository) ListComments(ctx context.Context, videoID uuid.UUID, limit, offset int) ([]VideoComment, error) {
	const q = `
		SELECT c.id, c.video_id, c.user_id, c.content, c.like_count, c.created_at,
		       p.name, p.avatar_url
		FROM video_comments c
		LEFT JOIN profiles p ON p.id = c.user_id
		WHERE c.video_id = $1
		ORDER BY c.created_at DESC
		LIMIT $2 OFFSET $3`
	rows, err := r.pool.Query(ctx, q, videoID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]VideoComment, 0)
	for rows.Next() {
		var c VideoComment
		if err := rows.Scan(&c.ID, &c.VideoID, &c.UserID, &c.Content, &c.LikeCount, &c.CreatedAt,
			&c.UserName, &c.UserAvatar); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// Follow / Unfollow a creator. Returns whether the viewer follows them after
// the call (so the client can sync its button).
func (r *Repository) Follow(ctx context.Context, follower, followee uuid.UUID) (bool, error) {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO user_follows (follower_id, followee_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
		follower, followee)
	if err != nil {
		// FK violation = the target user doesn't exist → surface as not-found
		// rather than a 500.
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23503" {
			return false, ErrNotFound
		}
		return false, err
	}
	return true, nil
}

func (r *Repository) Unfollow(ctx context.Context, follower, followee uuid.UUID) (bool, error) {
	_, err := r.pool.Exec(ctx,
		`DELETE FROM user_follows WHERE follower_id = $1 AND followee_id = $2`, follower, followee)
	if err != nil {
		return true, err
	}
	return false, nil
}

// CreatorStats aggregates the three counters on a user's profile header:
// how many accounts they follow ("đang theo dõi"), how many follow them
// ("người theo dõi"), and the total likes across their videos.
//
// A "follow" in this app targets whichever a video/live is attributed to — the
// shop when one is present, otherwise the creator — so the two follow tables
// are summed. shop_follows feeds the Live tab's "Theo dõi", user_follows feeds
// the video creator-follow; counting both keeps the profile header in sync with
// what the Live/Video tabs actually show. A shop-owning user's followers also
// include their shop's follower_count.
func (r *Repository) CreatorStats(ctx context.Context, userID uuid.UUID) (following, followers, likes int, err error) {
	err = r.pool.QueryRow(ctx, `
		SELECT
		  ((SELECT COUNT(*) FROM user_follows WHERE follower_id = $1)
		    + (SELECT COUNT(*) FROM shop_follows WHERE user_id = $1))::int,
		  ((SELECT COUNT(*) FROM user_follows WHERE followee_id = $1)
		    + COALESCE((SELECT follower_count FROM shops WHERE seller_id = $1), 0))::int,
		  COALESCE((SELECT SUM(like_count) FROM videos
		            WHERE user_id = $1 AND status = 'active'), 0)::int
	`, userID).Scan(&following, &followers, &likes)
	return
}

// RecordView counts a view. For a logged-in user it's deduped (counts once per
// video, ever) via video_views; anonymous views (userID == Nil) just increment,
// relying on the per-IP rate limit + client per-session dedupe.
func (r *Repository) RecordView(ctx context.Context, videoID, userID uuid.UUID) error {
	if userID == uuid.Nil {
		return r.IncView(ctx, videoID)
	}
	tag, err := r.pool.Exec(ctx,
		`INSERT INTO video_views (video_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
		videoID, userID)
	if err != nil {
		// FK violation = video missing; view pings are fire-and-forget.
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23503" {
			return nil
		}
		return err
	}
	if tag.RowsAffected() == 1 {
		return r.IncView(ctx, videoID)
	}
	return nil
}

// ── Reports / moderation ──────────────────────────────────────────────────────

// AddReport records (or refreshes) a report. ErrNotFound if the video is gone.
func (r *Repository) AddReport(ctx context.Context, videoID, reporterID uuid.UUID, reason string) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO video_reports (video_id, reporter_id, reason)
		VALUES ($1, $2, $3)
		ON CONFLICT (video_id, reporter_id) DO UPDATE
		   SET reason = EXCLUDED.reason, status = 'pending', action = NULL,
		       resolved_by = NULL, resolved_at = NULL, created_at = NOW()`,
		videoID, reporterID, reason)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23503" {
			return ErrNotFound
		}
		return err
	}
	return nil
}

func scanReport(row pgx.Row, rp *VideoReport) error {
	return row.Scan(&rp.ID, &rp.VideoID, &rp.ReporterID, &rp.Reason, &rp.Status, &rp.Action, &rp.CreatedAt,
		&rp.ReporterName, &rp.VideoCaption, &rp.VideoThumb, &rp.VideoStatus, &rp.OwnerName)
}

// ListReports returns the moderation queue. status="" lists all; otherwise
// filters (typically "pending").
func (r *Repository) ListReports(ctx context.Context, status string, limit, offset int) ([]VideoReport, error) {
	const q = `
		SELECT rp.id, rp.video_id, rp.reporter_id, rp.reason, rp.status, rp.action, rp.created_at,
		       rep.name, v.caption, v.thumbnail_url, v.status, own.name
		FROM video_reports rp
		LEFT JOIN profiles rep ON rep.id = rp.reporter_id
		LEFT JOIN videos   v   ON v.id   = rp.video_id
		LEFT JOIN profiles own ON own.id = v.user_id
		WHERE ($1 = '' OR rp.status = $1)
		ORDER BY rp.created_at DESC
		LIMIT $2 OFFSET $3`
	rows, err := r.pool.Query(ctx, q, status, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]VideoReport, 0)
	for rows.Next() {
		var rp VideoReport
		if err := scanReport(rows, &rp); err != nil {
			return nil, err
		}
		out = append(out, rp)
	}
	return out, rows.Err()
}

// ResolveReport closes a report. takedown=true soft-deletes the video and
// resolves every pending report on it in one transaction; takedown=false just
// dismisses this report. ErrNotFound if the report id is unknown.
func (r *Repository) ResolveReport(ctx context.Context, reportID, adminID uuid.UUID, takedown bool) error {
	var videoID uuid.UUID
	err := r.pool.QueryRow(ctx, `SELECT video_id FROM video_reports WHERE id = $1`, reportID).Scan(&videoID)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if takedown {
		if _, err := tx.Exec(ctx, `UPDATE videos SET status = 'deleted' WHERE id = $1`, videoID); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			UPDATE video_reports
			   SET status = 'resolved', action = 'takedown', resolved_by = $2, resolved_at = NOW()
			 WHERE video_id = $1 AND status = 'pending'`, videoID, adminID); err != nil {
			return err
		}
	} else {
		if _, err := tx.Exec(ctx, `
			UPDATE video_reports
			   SET status = 'dismissed', action = 'dismiss', resolved_by = $2, resolved_at = NOW()
			 WHERE id = $1`, reportID, adminID); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}
