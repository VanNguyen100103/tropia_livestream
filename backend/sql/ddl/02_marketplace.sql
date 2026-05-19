-- =============================================================================
-- DDL 02: Marketplace – Categories, Shops, Products, Variants
-- Nguồn: 001_marketplace_schema.sql
-- Yêu cầu: 01_core.sql đã chạy (cần bảng profiles)
-- =============================================================================

-- ── Categories (cây đa cấp) ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.categories (
  id          UUID  PRIMARY KEY DEFAULT uuid_generate_v4(),
  name        TEXT  NOT NULL,
  slug        TEXT  NOT NULL UNIQUE,
  parent_id   UUID  REFERENCES public.categories(id) ON DELETE SET NULL,
  image_url   TEXT,
  sort_order  INT   NOT NULL DEFAULT 0,
  is_active   BOOL  NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_categories_parent ON public.categories(parent_id);
CREATE INDEX IF NOT EXISTS idx_categories_slug   ON public.categories(slug);

-- ── Shops (mỗi seller có 1 shop) ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.shops (
  id              UUID  PRIMARY KEY DEFAULT uuid_generate_v4(),
  seller_id       UUID  NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name            TEXT  NOT NULL,
  slug            TEXT  NOT NULL UNIQUE,
  description     TEXT,
  logo_url        TEXT,
  banner_url      TEXT,
  is_active       BOOL  NOT NULL DEFAULT TRUE,
  rating          NUMERIC(3,2) NOT NULL DEFAULT 0,
  total_sales     INT   NOT NULL DEFAULT 0,
  follower_count  INT   NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(seller_id)
);

CREATE INDEX IF NOT EXISTS idx_shops_seller ON public.shops(seller_id);
CREATE INDEX IF NOT EXISTS idx_shops_slug   ON public.shops(slug);

-- ── Products ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.products (
  id            UUID  PRIMARY KEY DEFAULT uuid_generate_v4(),
  shop_id       UUID  NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  name          TEXT  NOT NULL,
  slug          TEXT  NOT NULL UNIQUE,
  description   TEXT,
  images        TEXT[] NOT NULL DEFAULT '{}',
  base_price    NUMERIC(12,0) NOT NULL,
  sale_price    NUMERIC(12,0),
  unit          TEXT  NOT NULL DEFAULT 'cái',
  status        TEXT  NOT NULL DEFAULT 'draft'
                  CHECK (status IN ('draft','active','inactive','deleted')),
  has_variants  BOOL  NOT NULL DEFAULT FALSE,
  total_stock   INT   NOT NULL DEFAULT 0,
  total_sold    INT   NOT NULL DEFAULT 0,
  rating        NUMERIC(3,2) NOT NULL DEFAULT 0,
  review_count  INT   NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_products_shop     ON public.products(shop_id);
CREATE INDEX IF NOT EXISTS idx_products_status   ON public.products(status);
CREATE INDEX IF NOT EXISTS idx_products_slug     ON public.products(slug);
CREATE INDEX IF NOT EXISTS idx_products_fts      ON public.products
  USING GIN (to_tsvector('simple', name || ' ' || COALESCE(description, '')));

-- ── Product variants ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.product_variants (
  id          UUID  PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id  UUID  NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  attributes  JSONB NOT NULL DEFAULT '{}',
  sku         TEXT,
  price       NUMERIC(12,0) NOT NULL,
  sale_price  NUMERIC(12,0),
  stock       INT   NOT NULL DEFAULT 0,
  -- images array thay thế image_url (migration 006)
  images      TEXT[] NOT NULL DEFAULT '{}',
  is_active   BOOL  NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_variants_product ON public.product_variants(product_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_variants_sku ON public.product_variants(sku)
  WHERE sku IS NOT NULL;

-- ── product_categories (many-to-many, migration 004) ─────────────────────────
CREATE TABLE IF NOT EXISTS public.product_categories (
  product_id  UUID NOT NULL REFERENCES public.products(id)    ON DELETE CASCADE,
  category_id UUID NOT NULL REFERENCES public.categories(id)  ON DELETE CASCADE,
  is_primary  BOOL NOT NULL DEFAULT FALSE,
  PRIMARY KEY (product_id, category_id)
);

CREATE INDEX IF NOT EXISTS idx_product_categories_product  ON public.product_categories(product_id);
CREATE INDEX IF NOT EXISTS idx_product_categories_category ON public.product_categories(category_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_product_categories_primary
  ON public.product_categories(product_id) WHERE is_primary = TRUE;
