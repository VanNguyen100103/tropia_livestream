-- =============================================================================
-- ALTER 03: Thêm stats columns vào live_sessions + product_id vào live_session_products
-- Nguồn: sql/add_live_session_stats.sql, 016_live_session_products_add_product_id.sql
-- =============================================================================

ALTER TABLE public.live_sessions
  ADD COLUMN IF NOT EXISTS cart_add_count  INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS follow_count    INTEGER NOT NULL DEFAULT 0;

ALTER TABLE public.live_session_products
  ADD COLUMN IF NOT EXISTS product_id UUID REFERENCES public.products(id) ON DELETE SET NULL;
