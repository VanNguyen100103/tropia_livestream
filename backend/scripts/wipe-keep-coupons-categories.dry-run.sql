-- DRY-RUN version: chạy y hệt script wipe nhưng ROLLBACK ở cuối,
-- nên không thay đổi gì trong DB. Dùng để xem counts before/after.

BEGIN;

\echo '─── Counts BEFORE ───'
SELECT 'profiles'              AS table, COUNT(*) FROM profiles
UNION ALL SELECT 'shops',                COUNT(*) FROM shops
UNION ALL SELECT 'products',             COUNT(*) FROM products
UNION ALL SELECT 'product_variants',     COUNT(*) FROM product_variants
UNION ALL SELECT 'product_categories',   COUNT(*) FROM product_categories
UNION ALL SELECT 'attribute_types',      COUNT(*) FROM attribute_types
UNION ALL SELECT 'attribute_values',     COUNT(*) FROM attribute_values
UNION ALL SELECT 'variant_attributes',   COUNT(*) FROM variant_attributes
UNION ALL SELECT 'shop_follows',         COUNT(*) FROM shop_follows
UNION ALL SELECT 'refresh_tokens',       COUNT(*) FROM refresh_tokens
UNION ALL SELECT 'live_sessions',        COUNT(*) FROM live_sessions
UNION ALL SELECT 'live_session_products', COUNT(*) FROM live_session_products
UNION ALL SELECT 'live_session_follows', COUNT(*) FROM live_session_follows
UNION ALL SELECT 'live_viewers',         COUNT(*) FROM live_viewers
UNION ALL SELECT 'live_events',          COUNT(*) FROM live_events
UNION ALL SELECT 'live_orders',          COUNT(*) FROM live_orders
UNION ALL SELECT 'cart_items',           COUNT(*) FROM cart_items
UNION ALL SELECT 'chat_messages',        COUNT(*) FROM chat_messages
UNION ALL SELECT 'recordings',           COUNT(*) FROM recordings
UNION ALL SELECT 'coupons (all)',        COUNT(*) FROM coupons
UNION ALL SELECT 'coupons (platform)',   COUNT(*) FROM coupons WHERE session_id IS NULL
UNION ALL SELECT 'coupons (session)',    COUNT(*) FROM coupons WHERE session_id IS NOT NULL
UNION ALL SELECT 'coupon_usages',        COUNT(*) FROM coupon_usages
UNION ALL SELECT 'categories (KEEP)',    COUNT(*) FROM categories
ORDER BY 1;

DELETE FROM coupon_usages;
DELETE FROM recordings;
DELETE FROM live_events;
DELETE FROM live_viewers;
DELETE FROM chat_messages;
DELETE FROM cart_items;
DELETE FROM live_orders;
DELETE FROM live_session_products;
DELETE FROM live_session_follows;
DELETE FROM coupons WHERE session_id IS NOT NULL;  -- must run BEFORE live_sessions
DELETE FROM live_sessions;
DELETE FROM variant_attributes;
DELETE FROM product_variants;
DELETE FROM product_categories;
DELETE FROM products;
DELETE FROM attribute_values;
DELETE FROM attribute_types;
DELETE FROM shop_follows;
DELETE FROM shops;
DELETE FROM refresh_tokens;
DELETE FROM profiles
WHERE role <> 'admin'
  AND id NOT IN (SELECT created_by FROM coupons);

\echo '─── Counts AFTER (DRY-RUN, will rollback) ───'
SELECT 'profiles'              AS table, COUNT(*) FROM profiles
UNION ALL SELECT 'shops',                COUNT(*) FROM shops
UNION ALL SELECT 'products',             COUNT(*) FROM products
UNION ALL SELECT 'product_variants',     COUNT(*) FROM product_variants
UNION ALL SELECT 'product_categories',   COUNT(*) FROM product_categories
UNION ALL SELECT 'attribute_types',      COUNT(*) FROM attribute_types
UNION ALL SELECT 'attribute_values',     COUNT(*) FROM attribute_values
UNION ALL SELECT 'variant_attributes',   COUNT(*) FROM variant_attributes
UNION ALL SELECT 'shop_follows',         COUNT(*) FROM shop_follows
UNION ALL SELECT 'refresh_tokens',       COUNT(*) FROM refresh_tokens
UNION ALL SELECT 'live_sessions',        COUNT(*) FROM live_sessions
UNION ALL SELECT 'live_session_products', COUNT(*) FROM live_session_products
UNION ALL SELECT 'live_session_follows', COUNT(*) FROM live_session_follows
UNION ALL SELECT 'live_viewers',         COUNT(*) FROM live_viewers
UNION ALL SELECT 'live_events',          COUNT(*) FROM live_events
UNION ALL SELECT 'live_orders',          COUNT(*) FROM live_orders
UNION ALL SELECT 'cart_items',           COUNT(*) FROM cart_items
UNION ALL SELECT 'chat_messages',        COUNT(*) FROM chat_messages
UNION ALL SELECT 'recordings',           COUNT(*) FROM recordings
UNION ALL SELECT 'coupons (all)',        COUNT(*) FROM coupons
UNION ALL SELECT 'coupons (platform)',   COUNT(*) FROM coupons WHERE session_id IS NULL
UNION ALL SELECT 'coupons (session)',    COUNT(*) FROM coupons WHERE session_id IS NOT NULL
UNION ALL SELECT 'coupon_usages',        COUNT(*) FROM coupon_usages
UNION ALL SELECT 'categories (KEEP)',    COUNT(*) FROM categories
ORDER BY 1;

ROLLBACK;
