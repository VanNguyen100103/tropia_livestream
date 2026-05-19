-- =============================================================================
-- RPC 01: Triggers & Functions tự động
-- Nguồn: 000_initial_schema.sql, 001_marketplace_schema.sql, 007_follow_and_cart.sql
-- =============================================================================

-- ── Helper: updated_at tự động ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

DROP TRIGGER IF EXISTS trg_products_updated_at   ON public.products;
CREATE TRIGGER trg_products_updated_at
  BEFORE UPDATE ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_shops_updated_at      ON public.shops;
CREATE TRIGGER trg_shops_updated_at
  BEFORE UPDATE ON public.shops
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_cart_items_updated_at ON public.cart_items;
CREATE TRIGGER trg_cart_items_updated_at
  BEFORE UPDATE ON public.cart_items
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── Viewer count (live_viewers INSERT/DELETE) ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_viewer_count()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.live_sessions
  SET viewer_count = (
    SELECT COUNT(*) FROM public.live_viewers
    WHERE session_id = COALESCE(NEW.session_id, OLD.session_id)
  )
  WHERE id = COALESCE(NEW.session_id, OLD.session_id);
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_viewer_count_insert ON public.live_viewers;
CREATE TRIGGER trg_viewer_count_insert
  AFTER INSERT ON public.live_viewers
  FOR EACH ROW EXECUTE FUNCTION public.update_viewer_count();

DROP TRIGGER IF EXISTS trg_viewer_count_delete ON public.live_viewers;
CREATE TRIGGER trg_viewer_count_delete
  AFTER DELETE ON public.live_viewers
  FOR EACH ROW EXECUTE FUNCTION public.update_viewer_count();

-- ── Session stats: order_count, revenue, sold_count ──────────────────────────
CREATE OR REPLACE FUNCTION public.update_session_stats()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.session_id IS NOT NULL THEN
    UPDATE public.live_sessions
    SET
      order_count = (
        SELECT COUNT(*) FROM public.live_orders
        WHERE session_id = NEW.session_id AND status != 'cancelled'
      ),
      revenue = (
        SELECT COALESCE(SUM(total_price), 0) FROM public.live_orders
        WHERE session_id = NEW.session_id AND status != 'cancelled'
      )
    WHERE id = NEW.session_id;
  END IF;
  IF NEW.product_id IS NOT NULL THEN
    UPDATE public.live_session_products
    SET
      stock_left = GREATEST(0, stock_left - NEW.quantity),
      sold_count = sold_count + NEW.quantity
    WHERE id = NEW.product_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_session_stats ON public.live_orders;
CREATE TRIGGER trg_session_stats
  AFTER INSERT ON public.live_orders
  FOR EACH ROW EXECUTE FUNCTION public.update_session_stats();

-- ── Product total_stock từ variants ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sync_product_stock()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.products
  SET
    total_stock = (
      SELECT COALESCE(SUM(stock), 0) FROM public.product_variants
      WHERE product_id = COALESCE(NEW.product_id, OLD.product_id)
        AND is_active = TRUE
    ),
    updated_at = NOW()
  WHERE id = COALESCE(NEW.product_id, OLD.product_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_product_stock ON public.product_variants;
CREATE TRIGGER trg_sync_product_stock
  AFTER INSERT OR UPDATE OR DELETE ON public.product_variants
  FOR EACH ROW EXECUTE FUNCTION public.sync_product_stock();

-- ── Shop follower_count ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sync_shop_follower_count()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.shops
  SET follower_count = (
    SELECT COUNT(*) FROM public.shop_follows
    WHERE shop_id = COALESCE(NEW.shop_id, OLD.shop_id)
  )
  WHERE id = COALESCE(NEW.shop_id, OLD.shop_id);
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_shop_follower_count ON public.shop_follows;
CREATE TRIGGER trg_shop_follower_count
  AFTER INSERT OR DELETE ON public.shop_follows
  FOR EACH ROW EXECUTE FUNCTION public.sync_shop_follower_count();
