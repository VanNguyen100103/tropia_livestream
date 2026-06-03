-- =============================================================================
-- 0011: shop_live_permissions — who may livestream for a shop.
-- =============================================================================
-- Platform differentiator (per product owner): unlike Shopee, NOT everyone can
-- go live. Only:
--   1. the shop owner (shops.seller_id),
--   2. staff the owner granted live permission to, or
--   3. a collaborator (CTV) the owner has approved.
-- This table backs (2) and (3); (1) is derived from the shops table.
--
-- The shop owner is the sole approver (their shop, their call). A member row
-- is only effective when status='approved' AND can_live=true.
-- =============================================================================

CREATE TABLE shop_live_permissions (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id     UUID NOT NULL REFERENCES shops(id)     ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES profiles(id)  ON DELETE CASCADE,
    member_type TEXT NOT NULL DEFAULT 'collaborator'
                CHECK (member_type IN ('staff', 'collaborator')),
    can_live    BOOLEAN NOT NULL DEFAULT TRUE,
    status      TEXT NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'approved', 'rejected')),
    invited_by  UUID REFERENCES profiles(id) ON DELETE SET NULL,
    approved_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
    approved_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- One membership row per (shop, user).
    UNIQUE (shop_id, user_id)
);

-- Fast "can this user live?" lookup (the live-permission gate hits this on
-- every live/start). Partial index on the only rows that grant access.
CREATE INDEX idx_shop_live_perms_user_active
    ON shop_live_permissions (user_id)
    WHERE status = 'approved' AND can_live = TRUE;

CREATE INDEX idx_shop_live_perms_shop ON shop_live_permissions (shop_id);
