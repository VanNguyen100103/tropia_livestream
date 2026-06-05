-- Rollback 0017: drop the shop voucher column + its index.
DROP INDEX IF EXISTS idx_coupons_shop;
ALTER TABLE coupons DROP COLUMN IF EXISTS shop_id;
