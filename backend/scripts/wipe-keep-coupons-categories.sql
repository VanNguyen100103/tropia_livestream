-- =============================================================================
-- wipe-keep-coupons-categories.sql
-- =============================================================================
-- Xoá toàn bộ dữ liệu giao dịch / live / user-generated KHỎI database,
-- CHỪA LẠI:
--   - categories                              (seed reference data)
--   - coupons WHERE session_id IS NULL        (platform-wide coupons)
--   - profiles role='admin'                   (admin accounts giữ lại)
--   - profiles của những người tạo platform coupon (vì coupons.created_by
--     FK CASCADE — xoá profile → mất coupon)
--
-- Chạy:
--   docker compose -f infra/docker-compose.yml exec -T postgres \
--     psql -U postgres -d tropia -f /dev/stdin \
--     < backend/scripts/wipe-keep-coupons-categories.sql
--
-- Hoặc trực tiếp:
--   psql "postgres://postgres:postgres@localhost:5433/tropia" \
--     -f backend/scripts/wipe-keep-coupons-categories.sql
--
-- DRY-RUN: đổi COMMIT cuối thành ROLLBACK để xem kết quả trước khi áp dụng.
-- =============================================================================

BEGIN;

-- ── Counts BEFORE ─────────────────────────────────────────────────────────
\echo '─── Counts BEFORE ───'
SELECT 'profiles'              AS table, COUNT(*) FROM profiles
UNION ALL SELECT 'shops',                COUNT(*) FROM shops
UNION ALL SELECT 'products',             COUNT(*) FROM products
UNION ALL SELECT 'live_sessions',        COUNT(*) FROM live_sessions
UNION ALL SELECT 'live_orders',          COUNT(*) FROM live_orders
UNION ALL SELECT 'cart_items',           COUNT(*) FROM cart_items
UNION ALL SELECT 'chat_messages',        COUNT(*) FROM chat_messages
UNION ALL SELECT 'coupons (all)',        COUNT(*) FROM coupons
UNION ALL SELECT 'coupons (platform)',   COUNT(*) FROM coupons WHERE session_id IS NULL
UNION ALL SELECT 'coupons (session)',    COUNT(*) FROM coupons WHERE session_id IS NOT NULL
UNION ALL SELECT 'categories (KEEP)',    COUNT(*) FROM categories;

-- ── Delete ordering: children before parents ──────────────────────────────
-- Junction / event tables first (no incoming FKs)
DELETE FROM coupon_usages;
DELETE FROM recordings;
DELETE FROM live_events;
DELETE FROM live_viewers;
DELETE FROM chat_messages;
DELETE FROM cart_items;
DELETE FROM live_orders;
DELETE FROM live_session_products;
DELETE FROM live_session_follows;

-- Session-scoped coupons MUST be deleted before live_sessions:
-- coupons.session_id has ON DELETE SET NULL, so dropping the session
-- first would null the column → turn every session coupon into a
-- "platform" coupon → our `WHERE session_id IS NOT NULL` filter below
-- would match nothing and the session coupons would survive incorrectly.
DELETE FROM coupons WHERE session_id IS NOT NULL;

DELETE FROM live_sessions;

-- Product graph
DELETE FROM variant_attributes;
DELETE FROM product_variants;
DELETE FROM product_categories;        -- junction; categories rows preserved
DELETE FROM products;

-- Attribute dictionary (not in keep-list)
DELETE FROM attribute_values;
DELETE FROM attribute_types;

-- Shop graph
DELETE FROM shop_follows;
DELETE FROM shops;

-- Sessions tokens
DELETE FROM refresh_tokens;

-- Profiles — keep admins + những người tạo surviving platform coupons.
-- coupons.created_by has ON DELETE CASCADE, so deleting their creator
-- would wipe the platform coupon. Skip those rows.
DELETE FROM profiles
WHERE role <> 'admin'
  AND id NOT IN (SELECT created_by FROM coupons);

-- ── Counts AFTER ──────────────────────────────────────────────────────────
\echo '─── Counts AFTER ───'
SELECT 'profiles'              AS table, COUNT(*) FROM profiles
UNION ALL SELECT 'shops',                COUNT(*) FROM shops
UNION ALL SELECT 'products',             COUNT(*) FROM products
UNION ALL SELECT 'live_sessions',        COUNT(*) FROM live_sessions
UNION ALL SELECT 'live_orders',          COUNT(*) FROM live_orders
UNION ALL SELECT 'cart_items',           COUNT(*) FROM cart_items
UNION ALL SELECT 'chat_messages',        COUNT(*) FROM chat_messages
UNION ALL SELECT 'coupons (all)',        COUNT(*) FROM coupons
UNION ALL SELECT 'coupons (platform)',   COUNT(*) FROM coupons WHERE session_id IS NULL
UNION ALL SELECT 'coupons (session)',    COUNT(*) FROM coupons WHERE session_id IS NOT NULL
UNION ALL SELECT 'categories (KEEP)',    COUNT(*) FROM categories;

-- Change to ROLLBACK if dry-running.
COMMIT;
