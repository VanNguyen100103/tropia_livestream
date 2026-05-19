-- =============================================================================
-- DDL 01: Core tables – Auth, Live sessions, Orders
-- Nguồn: 000_initial_schema.sql
-- Chạy trước tất cả các file khác
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ── Profiles ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.profiles (
  id                      UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  email                   TEXT        NOT NULL UNIQUE,
  password_hash           TEXT        NOT NULL,
  name                    TEXT        NOT NULL,
  phone                   TEXT,
  avatar_url              TEXT,
  role                    TEXT        NOT NULL DEFAULT 'buyer'
                            CHECK (role IN ('buyer','seller','admin')),
  status                  TEXT        NOT NULL DEFAULT 'active'
                            CHECK (status IN ('active','suspended','deleted')),
  shop_name               TEXT,
  failed_login_attempts   INT         DEFAULT 0,
  locked_until            TIMESTAMPTZ,
  -- password reset (migration 005)
  password_reset_token    TEXT,
  password_reset_expires  TIMESTAMPTZ,
  -- email verification (migration 008)
  email_verified          BOOL        NOT NULL DEFAULT FALSE,
  verify_token            TEXT,
  verify_token_expires    TIMESTAMPTZ,
  created_at              TIMESTAMPTZ DEFAULT NOW(),
  updated_at              TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_profiles_email               ON public.profiles(email);
CREATE INDEX IF NOT EXISTS idx_profiles_password_reset_token ON public.profiles(password_reset_token)
  WHERE password_reset_token IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_profiles_verify_token        ON public.profiles(verify_token)
  WHERE verify_token IS NOT NULL;

-- ── Refresh tokens ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.refresh_tokens (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  token_hash  TEXT        NOT NULL UNIQUE,
  family      TEXT        NOT NULL,
  revoked     BOOL        NOT NULL DEFAULT FALSE,
  user_agent  TEXT,
  ip_address  TEXT,
  expires_at  TIMESTAMPTZ NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user   ON public.refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_hash   ON public.refresh_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_family ON public.refresh_tokens(family);

-- ── Live sessions ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.live_sessions (
  id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  seller_id       UUID        NOT NULL REFERENCES public.profiles(id),
  title           TEXT        NOT NULL,
  category        TEXT        NOT NULL,
  status          TEXT        NOT NULL DEFAULT 'live'
                    CHECK (status IN ('live','ended')),
  agora_channel   TEXT        NOT NULL,
  viewer_count    INT         DEFAULT 0,
  like_count      INT         DEFAULT 0,
  order_count     INT         DEFAULT 0,
  revenue         NUMERIC(14,2) DEFAULT 0,
  -- stats (sql/add_live_session_stats.sql)
  cart_add_count  INT         NOT NULL DEFAULT 0,
  follow_count    INT         NOT NULL DEFAULT 0,
  started_at      TIMESTAMPTZ DEFAULT NOW(),
  ended_at        TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_live_sessions_status ON public.live_sessions(status);
CREATE INDEX IF NOT EXISTS idx_live_sessions_seller ON public.live_sessions(seller_id);

-- ── Live session products ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.live_session_products (
  id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id      UUID        NOT NULL REFERENCES public.live_sessions(id) ON DELETE CASCADE,
  -- link về products table (migration 016)
  product_id      UUID        REFERENCES public.products(id) ON DELETE SET NULL,
  product_name    TEXT        NOT NULL,
  image_url       TEXT,
  original_price  NUMERIC(14,2) NOT NULL,
  sale_price      NUMERIC(14,2) NOT NULL,
  discount_pct    INT         DEFAULT 0,
  stock_left      INT         DEFAULT 0,
  sold_count      INT         DEFAULT 0,
  unit            TEXT        DEFAULT 'cái',
  category        TEXT,
  sort_order      INT         DEFAULT 0
);

-- ── Chat messages ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.chat_messages (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id  UUID        NOT NULL REFERENCES public.live_sessions(id) ON DELETE CASCADE,
  user_id     UUID        REFERENCES public.profiles(id),
  username    TEXT        NOT NULL,
  avatar_url  TEXT,
  message     TEXT        NOT NULL,
  -- is_host (sql/add_chat_is_host.sql)
  is_host     BOOL        NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_session ON public.chat_messages(session_id, created_at DESC);

-- ── Live orders ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.live_orders (
  id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  -- session_id / product_id nullable: cart orders không có live session (migration 010)
  session_id      UUID        REFERENCES public.live_sessions(id),
  product_id      UUID        REFERENCES public.live_session_products(id),
  buyer_id        UUID        REFERENCES public.profiles(id),
  buyer_name      TEXT        NOT NULL,
  buyer_avatar    TEXT,
  quantity        INT         NOT NULL DEFAULT 1,
  unit_price      NUMERIC(14,2) NOT NULL,
  total_price     NUMERIC(14,2) NOT NULL,
  discount_amount NUMERIC(14,2) DEFAULT 0,
  coupon_id       UUID,       -- FK thêm sau khi bảng coupons tạo
  product_name    TEXT,
  status          TEXT        DEFAULT 'confirmed'
                    CHECK (status IN ('pending','confirmed','cancelled')),
  -- payment columns (migration 002)
  payment_method  TEXT        DEFAULT 'cod',
  payment_status  TEXT        DEFAULT 'pending',
  transaction_id  TEXT,
  paid_at         TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_live_orders_session        ON public.live_orders(session_id);
CREATE INDEX IF NOT EXISTS idx_live_orders_buyer          ON public.live_orders(buyer_id);
CREATE INDEX IF NOT EXISTS idx_live_orders_payment_status ON public.live_orders(payment_status);

-- ── Live viewers ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.live_viewers (
  session_id  UUID        NOT NULL REFERENCES public.live_sessions(id) ON DELETE CASCADE,
  user_id     UUID        NOT NULL,
  joined_at   TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (session_id, user_id)
);

-- ── Realtime publications ─────────────────────────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE public.live_sessions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.live_orders;
ALTER PUBLICATION supabase_realtime ADD TABLE public.live_session_products;
ALTER PUBLICATION supabase_realtime ADD TABLE public.live_viewers;
