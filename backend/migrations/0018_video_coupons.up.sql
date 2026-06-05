-- =============================================================================
-- 0018: video_coupons — seller coupons attached to a short-form video.
-- =============================================================================
-- Shopee Video "Voucher": when publishing a clip the poster ticks which of their
-- shop's coupons to feature on it; the feed overlays them as tappable chips so a
-- viewer can grab the code without leaving the video.
--
-- LEAN join table (same spirit as video_products): the display fields (code /
-- discount / min-order / expiry) are read LIVE from `coupons` at request time,
-- so a chip never shows a stale value and an expired/deactivated coupon simply
-- drops out of the result. Which coupons may be attached is gated to the
-- poster's own shop in the API layer (see video.attachCoupons).
-- =============================================================================

CREATE TABLE video_coupons (
    video_id   UUID NOT NULL REFERENCES videos(id)  ON DELETE CASCADE,
    coupon_id  UUID NOT NULL REFERENCES coupons(id) ON DELETE CASCADE,
    sort_order INTEGER NOT NULL DEFAULT 0,            -- display order on the card
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (video_id, coupon_id)
);

-- Per-video lookup in attach order (the feed reads coupons this way).
CREATE INDEX idx_video_coupons_video ON video_coupons(video_id, sort_order);
-- Reverse lookup ("which videos feature this coupon") + keeps the
-- ON DELETE CASCADE from coupons efficient when a coupon is removed.
CREATE INDEX idx_video_coupons_coupon ON video_coupons(coupon_id);
