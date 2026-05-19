-- =============================================================================
-- ALTER 01: Thêm cột thanh toán vào live_orders
-- Nguồn: 002_payment_columns.sql
-- Chạy NẾU bảng live_orders đã tồn tại và thiếu các cột này
-- =============================================================================

ALTER TABLE public.live_orders
  ADD COLUMN IF NOT EXISTS payment_method  TEXT    DEFAULT 'cod',
  ADD COLUMN IF NOT EXISTS payment_status  TEXT    DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS transaction_id  TEXT,
  ADD COLUMN IF NOT EXISTS paid_at         TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS discount_amount NUMERIC(14,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS coupon_id       UUID    REFERENCES public.coupons(id),
  ADD COLUMN IF NOT EXISTS buyer_avatar    TEXT,
  ADD COLUMN IF NOT EXISTS product_name    TEXT;

-- Bỏ NOT NULL trên session_id và product_id (cart orders không có live session)
ALTER TABLE public.live_orders ALTER COLUMN session_id DROP NOT NULL;
ALTER TABLE public.live_orders ALTER COLUMN product_id DROP NOT NULL;

CREATE INDEX IF NOT EXISTS idx_live_orders_payment_status ON public.live_orders(payment_status);
