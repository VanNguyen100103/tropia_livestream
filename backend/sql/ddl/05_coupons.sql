-- =============================================================================
-- DDL 05: Coupons + Coupon usages
-- Nguồn: 003_coupons.sql, 017_coupons_add_session_id.sql
-- Yêu cầu: 01_core.sql đã chạy
-- =============================================================================

-- ── Coupons ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.coupons (
  id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  code            TEXT        NOT NULL UNIQUE,
  discount_type   TEXT        NOT NULL DEFAULT 'percent'
                    CHECK (discount_type IN ('percent', 'fixed')),
  discount_value  NUMERIC(14,2) NOT NULL CHECK (discount_value > 0),
  min_order_value NUMERIC(14,2) DEFAULT 0,
  max_discount    NUMERIC(14,2),           -- giảm tối đa (áp dụng với percent)
  max_uses        INT         DEFAULT NULL, -- NULL = không giới hạn
  used_count      INT         NOT NULL DEFAULT 0,
  expires_at      TIMESTAMPTZ NOT NULL,
  is_active       BOOL        NOT NULL DEFAULT TRUE,
  -- liên kết buổi live (migration 017): NULL = platform coupon
  session_id      UUID        REFERENCES public.live_sessions(id) ON DELETE CASCADE,
  created_by      UUID        REFERENCES public.profiles(id),
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_coupons_code       ON public.coupons(code);
CREATE INDEX IF NOT EXISTS idx_coupons_expires    ON public.coupons(expires_at) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_coupons_session_id ON public.coupons(session_id) WHERE session_id IS NOT NULL;

-- ── Coupon usages (1 user dùng 1 code tối đa 1 lần) ──────────────────────────
CREATE TABLE IF NOT EXISTS public.coupon_usages (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  coupon_id   UUID        NOT NULL REFERENCES public.coupons(id)     ON DELETE CASCADE,
  user_id     UUID        NOT NULL REFERENCES public.profiles(id)    ON DELETE CASCADE,
  order_id    UUID        REFERENCES public.live_orders(id),
  used_at     TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (coupon_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_coupon_usages_user ON public.coupon_usages(user_id);

-- ── FK ngược: live_orders.coupon_id → coupons ────────────────────────────────
ALTER TABLE public.live_orders
  ADD CONSTRAINT fk_live_orders_coupon
  FOREIGN KEY (coupon_id) REFERENCES public.coupons(id)
  NOT VALID;   -- NOT VALID: không re-check dữ liệu cũ, chỉ enforce insert mới
