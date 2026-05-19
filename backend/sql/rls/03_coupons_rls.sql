-- =============================================================================
-- RLS 03: Row Level Security cho Coupons
-- Nguồn: 003_coupons.sql, 017_coupons_add_session_id.sql, 018_coupons_session_rls_fix.sql
-- =============================================================================

ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coupon_usages ENABLE ROW LEVEL SECURITY;

-- ── Coupons: đọc theo loại ────────────────────────────────────────────────────

-- Platform coupon (session_id IS NULL): phải active + chưa hết hạn
DROP POLICY IF EXISTS "coupons_platform_read" ON public.coupons;
CREATE POLICY "coupons_platform_read" ON public.coupons
  FOR SELECT USING (
    session_id IS NULL
    AND is_active = true
    AND expires_at > now()
  );

-- Shop/Live coupon (session_id IS NOT NULL): chỉ cần active
DROP POLICY IF EXISTS "coupons_session_read" ON public.coupons;
CREATE POLICY "coupons_session_read" ON public.coupons
  FOR SELECT USING (
    session_id IS NOT NULL
    AND is_active = true
  );

-- Seller đọc tất cả coupon do mình tạo
DROP POLICY IF EXISTS "coupons_owner_read" ON public.coupons;
CREATE POLICY "coupons_owner_read" ON public.coupons
  FOR SELECT USING (auth.uid() = created_by);

-- Seller tạo coupon cho buổi live của mình
DROP POLICY IF EXISTS "coupons_seller_insert" ON public.coupons;
CREATE POLICY "coupons_seller_insert" ON public.coupons
  FOR INSERT WITH CHECK (auth.uid() = created_by);

-- ── Coupon usages ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "coupon_usages_owner_read" ON public.coupon_usages;
CREATE POLICY "coupon_usages_owner_read" ON public.coupon_usages
  FOR SELECT USING (auth.uid() = user_id);
