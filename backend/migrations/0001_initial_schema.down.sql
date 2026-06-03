-- Rollback for 0001_initial_schema.up.sql
-- Drops everything created by the initial schema, in reverse dependency order.

-- RPC functions
DROP FUNCTION IF EXISTS increment_coupon_uses(UUID);
DROP FUNCTION IF EXISTS increment_follow_count(UUID);
DROP FUNCTION IF EXISTS increment_cart_add(UUID);
DROP FUNCTION IF EXISTS increment_likes(UUID);

-- Triggers (dropped automatically when tables drop, but be explicit)
DROP TRIGGER IF EXISTS live_viewers_count_trigger ON live_viewers;
DROP FUNCTION IF EXISTS update_live_viewer_count();

DROP TRIGGER IF EXISTS live_sessions_updated_at ON live_sessions;
DROP TRIGGER IF EXISTS product_variants_updated_at ON product_variants;
DROP TRIGGER IF EXISTS products_updated_at ON products;
DROP TRIGGER IF EXISTS categories_updated_at ON categories;
DROP TRIGGER IF EXISTS shops_updated_at ON shops;
DROP TRIGGER IF EXISTS profiles_updated_at ON profiles;
DROP FUNCTION IF EXISTS set_updated_at();

-- View
DROP VIEW IF EXISTS variant_detail;

-- Tables (reverse FK dependency order)
DROP TABLE IF EXISTS recordings CASCADE;
DROP TABLE IF EXISTS cart_items CASCADE;
DROP TABLE IF EXISTS live_orders CASCADE;
DROP TABLE IF EXISTS coupon_usages CASCADE;
DROP TABLE IF EXISTS coupons CASCADE;
DROP TABLE IF EXISTS chat_messages CASCADE;
DROP TABLE IF EXISTS live_viewers CASCADE;
DROP TABLE IF EXISTS live_session_products CASCADE;
DROP TABLE IF EXISTS live_sessions CASCADE;
DROP TABLE IF EXISTS variant_attributes CASCADE;
DROP TABLE IF EXISTS attribute_values CASCADE;
DROP TABLE IF EXISTS attribute_types CASCADE;
DROP TABLE IF EXISTS product_variants CASCADE;
DROP TABLE IF EXISTS product_categories CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
DROP TABLE IF EXISTS shop_follows CASCADE;
DROP TABLE IF EXISTS shops CASCADE;
DROP TABLE IF EXISTS refresh_tokens CASCADE;
DROP TABLE IF EXISTS profiles CASCADE;

-- Extensions (only drop if nothing else uses them)
-- DROP EXTENSION IF EXISTS "pgcrypto";
-- DROP EXTENSION IF EXISTS "uuid-ossp";
