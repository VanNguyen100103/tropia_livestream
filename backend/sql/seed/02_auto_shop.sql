-- =============================================================================
-- SEED 02: Tự động tạo shop cho seller chưa có shop
-- Nguồn: 011_seed_categories_and_shop.sql
-- Idempotent: ON CONFLICT (seller_id) DO NOTHING
-- Chạy sau khi đã có seller account trong profiles
-- =============================================================================

INSERT INTO public.shops (seller_id, name, slug, description, is_active)
SELECT
  p.id,
  COALESCE(NULLIF(TRIM(p.shop_name), ''), p.name || '''s Shop'),
  lower(regexp_replace(
    COALESCE(NULLIF(TRIM(p.shop_name), ''), p.name),
    '[^a-z0-9]+', '-', 'g'
  )) || '-' || substring(p.id::text, 1, 8),
  'Shop của ' || COALESCE(NULLIF(TRIM(p.shop_name), ''), p.name),
  true
FROM public.profiles p
WHERE p.role = 'seller'
  AND NOT EXISTS (
    SELECT 1 FROM public.shops s WHERE s.seller_id = p.id
  )
ON CONFLICT (seller_id) DO NOTHING;
