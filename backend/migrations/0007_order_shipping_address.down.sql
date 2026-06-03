ALTER TABLE live_orders
    DROP COLUMN IF EXISTS shipping_name,
    DROP COLUMN IF EXISTS shipping_phone,
    DROP COLUMN IF EXISTS shipping_address;
