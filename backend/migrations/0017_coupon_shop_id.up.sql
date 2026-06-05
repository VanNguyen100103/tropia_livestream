-- =============================================================================
-- 0017: coupons.shop_id — seller-owned shop vouchers ("Mua với Voucher").
-- =============================================================================
-- Until now a coupon was either platform-wide (session_id IS NULL) or tied to a
-- live session (shop ownership resolved via live_sessions.seller_id). That left
-- no way for a seller to create a standing SHOP voucher independent of a live
-- broadcast. shop_id makes shop vouchers first-class: a seller creates one for
-- their shop, it surfaces on the shop's video cards ("Mua với Voucher") and in
-- the cart's "Voucher của Shop" row, and applies at checkout via the existing
-- order-level coupon mechanism.
--
-- Nullable: platform coupons (shop_id IS NULL, session_id IS NULL) and legacy
-- live-session coupons (session_id set, shop_id NULL) are unchanged.
-- =============================================================================

ALTER TABLE coupons ADD COLUMN shop_id UUID REFERENCES shops(id) ON DELETE CASCADE;

-- "Active vouchers for this shop" lookup (video card flag + cart voucher row).
CREATE INDEX idx_coupons_shop ON coupons(shop_id) WHERE shop_id IS NOT NULL;
