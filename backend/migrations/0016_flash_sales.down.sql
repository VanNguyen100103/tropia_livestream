-- Rollback 0016: drop flash sale tables (products cascade with the parent).
DROP TABLE IF EXISTS flash_sale_products CASCADE;
DROP TABLE IF EXISTS flash_sales CASCADE;
