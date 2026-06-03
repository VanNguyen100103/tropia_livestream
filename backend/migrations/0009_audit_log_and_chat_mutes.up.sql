-- =============================================================================
-- Migration 0002 — audit_log + chat_mutes
--
-- Closes the last three gaps in the 9-threat security baseline:
--   - audit_log:  per-action trail for sensitive endpoints (threat 6 —
--                 insider threat / post-incident forensics).
--   - chat_mutes: host-driven and auto-driven moderation state for
--                 live chat (threat 9 — chat manipulation).
-- =============================================================================

-- ─── audit_log ──────────────────────────────────────────────────────────────
-- One row per sensitive action. We deliberately denormalise actor /
-- target details (snapshot at action time) so a later rename / delete
-- doesn't make the audit trail unreadable.
CREATE TABLE audit_log (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    actor_id     UUID,                                 -- profiles(id); nullable for system actions
    actor_role   TEXT,                                 -- "admin" / "seller" / "buyer" at action time
    actor_ip     TEXT,                                 -- request IP (capped at 45 chars for IPv6)
    action       TEXT NOT NULL,                        -- e.g. "live.session.create", "coupon.publish"
    target_type  TEXT,                                 -- e.g. "live_session", "coupon", "user"
    target_id    TEXT,                                 -- UUID or other identifier; TEXT to support non-UUID targets
    payload      JSONB NOT NULL DEFAULT '{}'::jsonb,   -- action-specific context
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Most queries are "what did this actor do recently" or "what touched
-- this target". Compound index over (action, created_at DESC) covers
-- the dashboard-style "show me last N coupon.publish events"; partial
-- index on actor_id and target_id covers point lookups.
CREATE INDEX idx_audit_log_action_time  ON audit_log (action, created_at DESC);
CREATE INDEX idx_audit_log_actor_time   ON audit_log (actor_id, created_at DESC) WHERE actor_id IS NOT NULL;
CREATE INDEX idx_audit_log_target       ON audit_log (target_type, target_id) WHERE target_id IS NOT NULL;

COMMENT ON TABLE  audit_log IS 'Sensitive-action trail. Append-only. Never UPDATE / DELETE — for incident response, regulatory audit, abuse investigation.';
COMMENT ON COLUMN audit_log.payload IS 'Action-specific context. Avoid PII; redact tokens / secrets before logging.';

-- ─── chat_mutes ─────────────────────────────────────────────────────────────
-- A mute exists either because the host pressed the mute button or
-- because the chat filter caught the user three times in 10 minutes.
-- One active mute per (session, user) — re-muting an already-muted
-- user extends the duration rather than stacking rows.
CREATE TABLE chat_mutes (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id   UUID NOT NULL REFERENCES live_sessions(id) ON DELETE CASCADE,
    user_id      UUID NOT NULL REFERENCES profiles(id)      ON DELETE CASCADE,
    muted_until  TIMESTAMPTZ NOT NULL,                  -- when the mute expires (NULL = forever was rejected — we always pick an explicit end so a stale mute doesn't outlive the session)
    reason       TEXT NOT NULL,                          -- "host_action", "auto_filter:url", "auto_filter:scam_phrase"
    muted_by     UUID,                                   -- profiles(id) — host who muted, NULL if auto
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (session_id, user_id)
);

-- Postgres rejects NOW() in a partial-index predicate (it's not
-- IMMUTABLE), so this is a plain composite covering the chat-post
-- hot-path lookup pattern (`WHERE session_id=$1 AND user_id=$2 AND
-- muted_until > NOW()`). The UNIQUE(session_id, user_id) constraint
-- above already gives us a unique-row guarantee.
CREATE INDEX idx_chat_mutes_lookup ON chat_mutes (session_id, user_id, muted_until DESC);
