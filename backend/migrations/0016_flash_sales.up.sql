-- =============================================================================
-- 0016: flash_sales — admin-scheduled, platform-wide time-boxed discounts.
-- =============================================================================
-- Shopee "Flash Sale": admin creates a sale window (starts_at..ends_at) and
-- attaches catalog products with a discounted flash_price. While the window is
-- live, surfaces (video feed card, future flash-sale page) show the flash price
-- + a countdown to ends_at. Distinct from `coupons` (order-level vouchers
-- applied at checkout) — a flash sale rewrites the *unit price* of a product
-- for everyone, no code needed.
--
-- flash_price is an ABSOLUTE VND amount per product (not a percent) so the
-- displayed price never drifts if base_price changes mid-sale. The discount %
-- shown on the card is derived (base_price → flash_price) at read time.
-- =============================================================================

CREATE TABLE flash_sales (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        TEXT NOT NULL,
    starts_at   TIMESTAMPTZ NOT NULL,
    ends_at     TIMESTAMPTZ NOT NULL,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_by  UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT flash_sales_window CHECK (ends_at > starts_at)
);

-- Window lookup for "which sales are live now" (the common read path).
CREATE INDEX idx_flash_sales_window ON flash_sales(starts_at, ends_at) WHERE is_active;

CREATE TABLE flash_sale_products (
    flash_sale_id UUID NOT NULL REFERENCES flash_sales(id) ON DELETE CASCADE,
    product_id    UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    flash_price   INTEGER NOT NULL,            -- absolute VND price during the sale
    stock_limit   INTEGER,                     -- NULL = unlimited for this sale
    sold_count    INTEGER NOT NULL DEFAULT 0,  -- units sold against this flash slot
    sort_order    INTEGER NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (flash_sale_id, product_id),
    CONSTRAINT flash_price_nonneg CHECK (flash_price >= 0),
    CONSTRAINT flash_stock_nonneg CHECK (stock_limit IS NULL OR stock_limit >= 0)
);

-- Reverse lookup: "is THIS product in an active flash sale right now" — drives
-- the LATERAL join in video.productsForVideos and the flash-sale page.
CREATE INDEX idx_flash_sale_products_product ON flash_sale_products(product_id);
