-- Capture the delivery address the buyer entered at checkout so the
-- receipt email and shipping operations can reference it. Before this,
-- the address dialog in the Flutter checkout screen collected name /
-- phone / address purely client-side and the data was discarded — the
-- buyer had no record of where the order would actually be shipped.
--
-- All three columns are nullable so existing orders (pre-migration) and
-- legacy COD flows that never collected an address still load cleanly.

ALTER TABLE live_orders
    ADD COLUMN shipping_name    TEXT NULL,
    ADD COLUMN shipping_phone   TEXT NULL,
    ADD COLUMN shipping_address TEXT NULL;
