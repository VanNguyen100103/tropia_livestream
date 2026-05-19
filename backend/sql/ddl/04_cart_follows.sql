-- =============================================================================
-- DDL 04: Cart items + Shop follows
-- Nguồn: 007_follow_and_cart.sql, 010_cart_live_support.sql
-- Yêu cầu: 02_marketplace.sql đã chạy
-- =============================================================================

-- ── Shop follows ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.shop_follows (
  user_id     UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  shop_id     UUID        NOT NULL REFERENCES public.shops(id)    ON DELETE CASCADE,
  followed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, shop_id)
);

CREATE INDEX IF NOT EXISTS idx_shop_follows_user ON public.shop_follows(user_id);
CREATE INDEX IF NOT EXISTS idx_shop_follows_shop ON public.shop_follows(shop_id);

-- ── Cart items ────────────────────────────────────────────────────────────────
-- variant_id và shop_id không có FK constraint:
--   - Live products không có record trong product_variants (migration 010)
--   - Live sessions dùng seller_id từ profiles, không phải shops.id
CREATE TABLE IF NOT EXISTS public.cart_items (
  id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  variant_id      UUID        NOT NULL,   -- intentionally no FK (live product support)
  product_id      UUID        NOT NULL,
  product_name    TEXT        NOT NULL,
  shop_id         UUID,                   -- nullable: live items may not have a shop record
  shop_name       TEXT        NOT NULL,
  image_url       TEXT,
  attributes      JSONB       NOT NULL DEFAULT '[]',
  unit_price      NUMERIC(12,0) NOT NULL,
  original_price  NUMERIC(12,0) NOT NULL,
  quantity        INT         NOT NULL DEFAULT 1 CHECK (quantity > 0),
  is_selected     BOOL        NOT NULL DEFAULT TRUE,
  added_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, variant_id)
);

CREATE INDEX IF NOT EXISTS idx_cart_items_user    ON public.cart_items(user_id);
CREATE INDEX IF NOT EXISTS idx_cart_items_variant ON public.cart_items(variant_id);
