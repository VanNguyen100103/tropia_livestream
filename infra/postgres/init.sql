-- Tropia - Full schema (ported from Node.js/Supabase backend)
-- Auto-run by Postgres container on first boot.
-- Snake_case columns, UUID PKs, TIMESTAMPTZ everywhere.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =============================================================================
-- 1. PROFILES (users: buyers / sellers / admins)
-- =============================================================================
CREATE TABLE profiles (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email                   TEXT UNIQUE NOT NULL,
    password_hash           TEXT,                              -- NULL for google-only
    name                    TEXT NOT NULL,
    phone                   TEXT,
    shop_name               TEXT,                              -- snapshot from register
    role                    TEXT NOT NULL DEFAULT 'buyer'
                            CHECK (role IN ('buyer', 'seller', 'admin')),
    avatar_url              TEXT,
    google_id               TEXT UNIQUE,
    status                  TEXT,                              -- 'deleted' = soft-delete
    email_verified          BOOLEAN NOT NULL DEFAULT FALSE,
    verify_token            TEXT,                              -- legacy
    verify_token_expires    TIMESTAMPTZ,
    password_reset_token    TEXT,                              -- sha256 hex
    password_reset_expires  TIMESTAMPTZ,
    failed_login_attempts   INTEGER NOT NULL DEFAULT 0,
    locked_until            TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_profiles_email ON profiles(email);
CREATE INDEX idx_profiles_role ON profiles(role) WHERE status IS DISTINCT FROM 'deleted';

-- =============================================================================
-- 2. REFRESH_TOKENS (rotation + reuse detection)
-- =============================================================================
CREATE TABLE refresh_tokens (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    token_hash  TEXT NOT NULL UNIQUE,                          -- sha256(raw_token)
    family      UUID NOT NULL,                                  -- token-family for reuse
    expires_at  TIMESTAMPTZ NOT NULL,
    revoked     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_family ON refresh_tokens(family);
CREATE INDEX idx_refresh_tokens_hash ON refresh_tokens(token_hash);

-- =============================================================================
-- 3. SHOPS
-- =============================================================================
CREATE TABLE shops (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    seller_id       UUID NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    slug            TEXT NOT NULL UNIQUE,
    description     TEXT,
    logo_url        TEXT,
    banner_url      TEXT,
    rating          NUMERIC(3,2) NOT NULL DEFAULT 0,
    total_sales     INTEGER NOT NULL DEFAULT 0,
    follower_count  INTEGER NOT NULL DEFAULT 0,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_shops_slug ON shops(slug);
CREATE INDEX idx_shops_active ON shops(is_active, total_sales DESC);

-- =============================================================================
-- 4. SHOP_FOLLOWS
-- =============================================================================
CREATE TABLE shop_follows (
    user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    shop_id     UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    followed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, shop_id)
);

CREATE INDEX idx_shop_follows_shop ON shop_follows(shop_id);

-- =============================================================================
-- 5. CATEGORIES (tree)
-- =============================================================================
CREATE TABLE categories (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        TEXT NOT NULL,
    slug        TEXT NOT NULL UNIQUE,
    parent_id   UUID REFERENCES categories(id) ON DELETE SET NULL,
    image_url   TEXT,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_categories_parent ON categories(parent_id);
CREATE INDEX idx_categories_slug ON categories(slug);

-- =============================================================================
-- 6. PRODUCTS
-- =============================================================================
CREATE TABLE products (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id         UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    slug            TEXT NOT NULL UNIQUE,
    description     TEXT,
    images          TEXT[] NOT NULL DEFAULT '{}',
    base_price      INTEGER NOT NULL,                          -- VND
    sale_price      INTEGER,
    unit            TEXT NOT NULL DEFAULT 'cái',
    has_variants    BOOLEAN NOT NULL DEFAULT FALSE,
    rating          NUMERIC(3,2) NOT NULL DEFAULT 0,
    review_count    INTEGER NOT NULL DEFAULT 0,
    total_sold      INTEGER NOT NULL DEFAULT 0,
    total_stock     INTEGER NOT NULL DEFAULT 0,
    status          TEXT NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft', 'active', 'inactive', 'deleted')),
    -- Full-text search vector (Vietnamese accents simple config)
    search_vector   tsvector GENERATED ALWAYS AS (
                        to_tsvector('simple', coalesce(name, '') || ' ' || coalesce(description, ''))
                    ) STORED,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_products_shop ON products(shop_id);
CREATE INDEX idx_products_status ON products(status);
CREATE INDEX idx_products_slug ON products(slug);
CREATE INDEX idx_products_total_sold ON products(total_sold DESC) WHERE status = 'active';
CREATE INDEX idx_products_search ON products USING GIN (search_vector);

-- =============================================================================
-- 7. PRODUCT_CATEGORIES (M2M)
-- =============================================================================
CREATE TABLE product_categories (
    product_id  UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
    is_primary  BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (product_id, category_id)
);

CREATE INDEX idx_product_categories_category ON product_categories(category_id);
-- Only one primary category per product
CREATE UNIQUE INDEX idx_product_categories_primary
    ON product_categories(product_id) WHERE is_primary = TRUE;

-- =============================================================================
-- 8. PRODUCT_VARIANTS
-- =============================================================================
CREATE TABLE product_variants (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id  UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    sku         TEXT,
    price       INTEGER NOT NULL,
    sale_price  INTEGER,
    stock       INTEGER NOT NULL DEFAULT 0,
    images      TEXT[] NOT NULL DEFAULT '{}',
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_product_variants_product ON product_variants(product_id);

-- =============================================================================
-- 9. ATTRIBUTE_TYPES / ATTRIBUTE_VALUES / VARIANT_ATTRIBUTES
-- =============================================================================
CREATE TABLE attribute_types (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        TEXT NOT NULL UNIQUE,                          -- "Color", "Size"
    sort_order  INTEGER NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE attribute_values (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    attribute_type_id   UUID NOT NULL REFERENCES attribute_types(id) ON DELETE CASCADE,
    value               TEXT NOT NULL,                         -- "Red", "M"
    display_name        TEXT,
    color_hex           TEXT,
    sort_order          INTEGER NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (attribute_type_id, value)
);

CREATE TABLE variant_attributes (
    variant_id          UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    attribute_value_id  UUID NOT NULL REFERENCES attribute_values(id) ON DELETE CASCADE,
    PRIMARY KEY (variant_id, attribute_value_id)
);

CREATE INDEX idx_variant_attributes_value ON variant_attributes(attribute_value_id);

-- =============================================================================
-- 10. VARIANT_DETAIL (read-only view used by cart.controller)
-- =============================================================================
CREATE OR REPLACE VIEW variant_detail AS
SELECT
    v.id,
    v.product_id,
    v.sku,
    v.price,
    v.sale_price,
    v.stock,
    v.images,
    v.is_active,
    COALESCE(
        (
            SELECT jsonb_agg(jsonb_build_object(
                'type', at.name,
                'value', av.value,
                'display_name', av.display_name,
                'color_hex', av.color_hex
            ) ORDER BY at.sort_order, av.sort_order)
            FROM variant_attributes va
            JOIN attribute_values av ON av.id = va.attribute_value_id
            JOIN attribute_types at ON at.id = av.attribute_type_id
            WHERE va.variant_id = v.id
        ),
        '[]'::jsonb
    ) AS attributes
FROM product_variants v;

-- =============================================================================
-- 11. LIVE_SESSIONS
-- =============================================================================
CREATE TABLE live_sessions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    seller_id           UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    title               TEXT NOT NULL,
    description         TEXT,
    cover_image_url     TEXT,
    category            TEXT,
    -- SRS stream key (called "agora_channel" for back-compat with old code)
    -- format: live_<16hex>
    agora_channel       TEXT NOT NULL UNIQUE,
    status              TEXT NOT NULL DEFAULT 'live'
                        CHECK (status IN ('scheduled', 'live', 'ended')),
    started_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at            TIMESTAMPTZ,
    viewer_count        INTEGER NOT NULL DEFAULT 0,
    like_count          INTEGER NOT NULL DEFAULT 0,
    order_count         INTEGER NOT NULL DEFAULT 0,
    revenue             INTEGER NOT NULL DEFAULT 0,
    cart_add_count      INTEGER NOT NULL DEFAULT 0,
    follow_count        INTEGER NOT NULL DEFAULT 0,
    -- VOD URLs after recording is uploaded to R2
    vod_hls_url         TEXT,
    vod_mp4_url         TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_live_sessions_seller ON live_sessions(seller_id);
CREATE INDEX idx_live_sessions_status ON live_sessions(status, started_at DESC);
CREATE INDEX idx_live_sessions_channel ON live_sessions(agora_channel);

-- =============================================================================
-- 12. LIVE_SESSION_PRODUCTS (snapshot)
-- =============================================================================
CREATE TABLE live_session_products (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id      UUID NOT NULL REFERENCES live_sessions(id) ON DELETE CASCADE,
    product_id      UUID REFERENCES products(id) ON DELETE SET NULL,  -- optional link to catalog
    product_name    TEXT NOT NULL,
    image_url       TEXT,
    original_price  NUMERIC(12,2) NOT NULL,
    sale_price      NUMERIC(12,2) NOT NULL,
    discount_pct    NUMERIC(5,2) NOT NULL DEFAULT 0,
    stock_left      INTEGER NOT NULL DEFAULT 0,
    sold_count      INTEGER NOT NULL DEFAULT 0,
    unit            TEXT NOT NULL DEFAULT 'cái',
    category        TEXT,
    sort_order      INTEGER NOT NULL DEFAULT 0,
    is_pinned       BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_live_session_products_session ON live_session_products(session_id, sort_order);

-- =============================================================================
-- 13. LIVE_VIEWERS (triggers update viewer_count)
-- =============================================================================
CREATE TABLE live_viewers (
    session_id  UUID NOT NULL REFERENCES live_sessions(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    joined_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (session_id, user_id)
);

CREATE INDEX idx_live_viewers_session ON live_viewers(session_id);

-- =============================================================================
-- 14. CHAT_MESSAGES
-- =============================================================================
CREATE TABLE chat_messages (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id  UUID NOT NULL REFERENCES live_sessions(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    username    TEXT NOT NULL,
    avatar_url  TEXT,
    message     TEXT NOT NULL,
    is_host     BOOLEAN,
    type        TEXT NOT NULL DEFAULT 'text'
                CHECK (type IN ('text', 'emoji', 'system')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_chat_messages_session_time ON chat_messages(session_id, created_at DESC);

-- =============================================================================
-- 15. COUPONS
-- =============================================================================
CREATE TABLE coupons (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code            TEXT NOT NULL UNIQUE,
    discount_type   TEXT NOT NULL
                    CHECK (discount_type IN ('percent', 'fixed')),
    discount_value  NUMERIC(12,2) NOT NULL,
    min_order_value INTEGER NOT NULL DEFAULT 0,
    max_discount    INTEGER,                                   -- cap for percent type
    max_uses        INTEGER,
    used_count      INTEGER NOT NULL DEFAULT 0,
    expires_at      TIMESTAMPTZ NOT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    session_id      UUID REFERENCES live_sessions(id) ON DELETE SET NULL,
    created_by      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_coupons_code ON coupons(code);
CREATE INDEX idx_coupons_session ON coupons(session_id) WHERE session_id IS NOT NULL;
CREATE INDEX idx_coupons_platform ON coupons(is_active, expires_at) WHERE session_id IS NULL;

-- =============================================================================
-- 16. COUPON_USAGES
-- =============================================================================
CREATE TABLE coupon_usages (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    coupon_id   UUID NOT NULL REFERENCES coupons(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    order_id    UUID,                                          -- FK added after live_orders
    used_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (coupon_id, user_id)                                -- one-use-per-user
);

CREATE INDEX idx_coupon_usages_user ON coupon_usages(user_id);

-- =============================================================================
-- 17. LIVE_ORDERS (live + cart checkout, unified table)
-- =============================================================================
CREATE TABLE live_orders (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id          UUID REFERENCES live_sessions(id) ON DELETE SET NULL,
    product_id          UUID REFERENCES live_session_products(id) ON DELETE SET NULL,
    product_name        TEXT,
    buyer_id            UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    buyer_name          TEXT,
    buyer_avatar        TEXT,
    quantity            INTEGER NOT NULL,
    unit_price          INTEGER NOT NULL,                      -- overloaded: per-item OR subtotal
    total_price         INTEGER NOT NULL,                      -- final after discount
    discount_amount     INTEGER NOT NULL DEFAULT 0,
    coupon_id           UUID REFERENCES coupons(id) ON DELETE SET NULL,
    status              TEXT NOT NULL DEFAULT 'confirmed'
                        CHECK (status IN ('confirmed', 'cancelled', 'shipping', 'delivered')),
    payment_status      TEXT NOT NULL DEFAULT 'pending'
                        CHECK (payment_status IN ('pending', 'paid', 'failed')),
    payment_method      TEXT NOT NULL DEFAULT 'cod',
    transaction_id      TEXT,
    paid_at             TIMESTAMPTZ,
    tracking_code       TEXT,
    shipped_at          TIMESTAMPTZ,
    delivered_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_live_orders_buyer ON live_orders(buyer_id, created_at DESC);
CREATE INDEX idx_live_orders_session ON live_orders(session_id) WHERE session_id IS NOT NULL;
CREATE INDEX idx_live_orders_status ON live_orders(status, payment_status);
CREATE INDEX idx_live_orders_transaction ON live_orders(transaction_id) WHERE transaction_id IS NOT NULL;

-- Now add the FK on coupon_usages -> live_orders
ALTER TABLE coupon_usages
    ADD CONSTRAINT coupon_usages_order_fk
    FOREIGN KEY (order_id) REFERENCES live_orders(id) ON DELETE SET NULL;

-- =============================================================================
-- 18. CART_ITEMS
-- =============================================================================
CREATE TABLE cart_items (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    -- variant_id holds EITHER product_variants.id OR live_session_products.id
    -- (semantic overload preserved from Node.js backend)
    variant_id      UUID NOT NULL,
    product_id      UUID,
    product_name    TEXT NOT NULL,
    shop_id         UUID,
    shop_name       TEXT,
    image_url       TEXT,
    attributes      JSONB NOT NULL DEFAULT '[]',
    unit_price      INTEGER NOT NULL,
    original_price  INTEGER NOT NULL,
    quantity        INTEGER NOT NULL CHECK (quantity > 0),
    is_selected     BOOLEAN NOT NULL DEFAULT TRUE,
    added_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, variant_id)
);

CREATE INDEX idx_cart_items_user ON cart_items(user_id);

-- =============================================================================
-- 19. RECORDINGS (DVR → R2 upload jobs)
-- =============================================================================
CREATE TABLE recordings (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id      UUID NOT NULL REFERENCES live_sessions(id) ON DELETE CASCADE,
    srs_file_path   TEXT NOT NULL,
    r2_key          TEXT,
    duration_sec    INTEGER,
    file_size_bytes BIGINT,
    status          TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'processing', 'uploaded', 'failed')),
    error_message   TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at    TIMESTAMPTZ
);

CREATE INDEX idx_recordings_session ON recordings(session_id);
CREATE INDEX idx_recordings_status ON recordings(status);

-- =============================================================================
-- TRIGGERS
-- =============================================================================

-- updated_at trigger function
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON profiles
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER shops_updated_at BEFORE UPDATE ON shops
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER categories_updated_at BEFORE UPDATE ON categories
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER products_updated_at BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER product_variants_updated_at BEFORE UPDATE ON product_variants
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER live_sessions_updated_at BEFORE UPDATE ON live_sessions
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- viewer_count trigger on live_viewers insert/delete
CREATE OR REPLACE FUNCTION update_live_viewer_count()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        UPDATE live_sessions SET viewer_count = viewer_count + 1 WHERE id = NEW.session_id;
        RETURN NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        UPDATE live_sessions SET viewer_count = GREATEST(0, viewer_count - 1) WHERE id = OLD.session_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER live_viewers_count_trigger
    AFTER INSERT OR DELETE ON live_viewers
    FOR EACH ROW EXECUTE FUNCTION update_live_viewer_count();

-- =============================================================================
-- RPC functions (preserve Node.js compatibility)
-- =============================================================================

CREATE OR REPLACE FUNCTION increment_likes(session_id UUID)
RETURNS VOID AS $$
BEGIN
    UPDATE live_sessions SET like_count = like_count + 1 WHERE id = session_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION increment_cart_add(session_id UUID)
RETURNS VOID AS $$
BEGIN
    UPDATE live_sessions SET cart_add_count = cart_add_count + 1 WHERE id = session_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION increment_follow_count(session_id UUID)
RETURNS VOID AS $$
BEGIN
    UPDATE live_sessions SET follow_count = follow_count + 1 WHERE id = session_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION increment_coupon_uses(cid UUID)
RETURNS VOID AS $$
BEGIN
    UPDATE coupons SET used_count = used_count + 1 WHERE id = cid;
END;
$$ LANGUAGE plpgsql;
