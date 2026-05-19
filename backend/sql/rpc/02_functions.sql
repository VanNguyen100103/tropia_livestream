-- =============================================================================
-- RPC 02: Atomic increment functions + cleanup
-- Nguồn: 000_initial_schema.sql, 003_coupons.sql, 009_guest_viewer_count.sql,
--        020_atomic_increment_rpcs.sql
-- =============================================================================

-- ── Xóa hàm cũ không dùng ────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.adjust_viewer_count(uuid, int);

-- ── Likes ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.increment_likes(session_id UUID)
RETURNS VOID LANGUAGE SQL SECURITY DEFINER AS $$
  UPDATE public.live_sessions
  SET like_count = like_count + 1
  WHERE id = session_id;
$$;

-- ── Coupon used_count ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.increment_coupon_uses(cid UUID)
RETURNS VOID LANGUAGE SQL SECURITY DEFINER AS $$
  UPDATE public.coupons SET used_count = used_count + 1 WHERE id = cid;
$$;

-- ── Cart add count ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.increment_cart_add(session_id UUID)
RETURNS VOID LANGUAGE SQL SECURITY DEFINER AS $$
  UPDATE public.live_sessions
  SET cart_add_count = COALESCE(cart_add_count, 0) + 1
  WHERE id = session_id;
$$;

-- ── Follow count ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.increment_follow_count(session_id UUID)
RETURNS VOID LANGUAGE SQL SECURITY DEFINER AS $$
  UPDATE public.live_sessions
  SET follow_count = COALESCE(follow_count, 0) + 1
  WHERE id = session_id;
$$;
