-- =============================================================================
-- 0015: video_products — catalog products tagged on a short-form video.
-- =============================================================================
-- Shopee Video "Xem sản phẩm (N)": a poster attaches products from their shop
-- catalog to a clip; the feed overlays a tappable product card → product detail.
--
-- This is a LEAN join table on purpose. Unlike live_session_products (which
-- snapshots name/price because a live host can quick-create off-catalog items),
-- the video card's display fields (name / image / price / sold / rating) are
-- read LIVE from `products` at request time, so the card never shows a stale
-- price. Which products may be attached is gated to the poster's own shop in
-- the API layer (see video.attachProducts).
-- =============================================================================

CREATE TABLE video_products (
    video_id    UUID NOT NULL REFERENCES videos(id)   ON DELETE CASCADE,
    product_id  UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    sort_order  INTEGER NOT NULL DEFAULT 0,            -- display order on the card
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (video_id, product_id)
);

-- Per-video lookup in attach order (the feed reads products this way).
CREATE INDEX idx_video_products_video ON video_products(video_id, sort_order);
-- Reverse lookup ("which videos feature this product") + keeps the
-- ON DELETE CASCADE from products efficient when a product is removed.
CREATE INDEX idx_video_products_product ON video_products(product_id);
