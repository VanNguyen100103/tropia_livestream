-- Add Shopee Live-style "pinned product" highlight to live sessions.
--
-- A host can pin ONE product at a time during a live to draw viewer
-- attention to it (e.g. "we're talking about this right now"). The
-- pin is independent of the session product list — it just marks
-- which of the already-added products is currently being featured.
--
-- Nullable: most sessions don't have a pinned product (set explicitly
-- when host taps "GẶP LÊN" in the pin sheet). FK references
-- live_session_products.id rather than products.id so we automatically
-- clear the pin if the host unpins/removes that product from the
-- session (ON DELETE SET NULL).

ALTER TABLE live_sessions
    ADD COLUMN pinned_product_id uuid NULL
        REFERENCES live_session_products(id) ON DELETE SET NULL;
