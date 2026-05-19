-- =============================================================================
-- ALTER 04: Cart items – bỏ FK để hỗ trợ live products + fix shop_id
-- Nguồn: 010_cart_live_support.sql, 019_fix_cart_items_shop_id.sql
-- Chạy NẾU cart_items đã tồn tại với FK constraints cũ
-- =============================================================================

-- Bỏ FK trên variant_id (live products không có record trong product_variants)
ALTER TABLE public.cart_items
  DROP CONSTRAINT IF EXISTS cart_items_variant_id_fkey;

-- Bỏ FK trên shop_id (live sessions dùng seller_id, không phải shops.id)
ALTER TABLE public.cart_items
  DROP CONSTRAINT IF EXISTS cart_items_shop_id_fkey;

-- Cho phép shop_id nullable
ALTER TABLE public.cart_items
  ALTER COLUMN shop_id DROP NOT NULL;

-- Fix dữ liệu cũ: shop_id đang lưu seller_id → đổi sang shops.id đúng
UPDATE public.cart_items ci
SET shop_id = s.id
FROM public.shops s
WHERE ci.shop_id::TEXT = s.seller_id::TEXT
  AND ci.shop_id != s.id;
