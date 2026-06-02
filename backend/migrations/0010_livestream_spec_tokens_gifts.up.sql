-- =============================================================================
-- 0010: LIVESTREAM_API.md alignment — integer ids, publish tokens, gifts,
--        loyalty points, chat gift messages.
-- =============================================================================
-- The mobile API contract (docs LIVESTREAM_API.md) exposes:
--   * integer ids for sessions, chat messages, gifts (the app paginates
--     chat with before_id:int) — our PKs are UUID, so we add a BIGSERIAL
--     `seq` column to surface a stable integer id without rewriting FKs.
--   * a per-session `publish_token` (?token=… on the RTMP URL) validated by
--     SRS on_publish, with an expiry.
--   * a gift catalog + sent-gift log + loyalty point balance.
--   * chat messages of type 'gift' carrying a gift_id.
-- =============================================================================

-- ── profiles: stable integer id for the spec (host.id, chat user_id) ───────
ALTER TABLE profiles ADD COLUMN seq BIGSERIAL;
CREATE UNIQUE INDEX idx_profiles_seq ON profiles(seq);

-- ── live_sessions: integer id + publish token ──────────────────────────────
ALTER TABLE live_sessions ADD COLUMN seq BIGSERIAL;
ALTER TABLE live_sessions ADD COLUMN publish_token TEXT;
ALTER TABLE live_sessions ADD COLUMN publish_token_expires_at TIMESTAMPTZ;
CREATE UNIQUE INDEX idx_live_sessions_seq ON live_sessions(seq);

-- The spec uses 'ready' (created, awaiting RTMP push) and 'offline' (ended)
-- in addition to 'live'. Widen the status check to accept them alongside the
-- existing values so the in-tree code can move sessions through the spec
-- lifecycle without tripping the constraint.
ALTER TABLE live_sessions DROP CONSTRAINT IF EXISTS live_sessions_status_check;
ALTER TABLE live_sessions
    ADD CONSTRAINT live_sessions_status_check
    CHECK (status = ANY (ARRAY[
        'scheduled'::text, 'ready'::text, 'live'::text,
        'ended'::text, 'offline'::text
    ]));

-- ── chat_messages: integer id + gift messages ──────────────────────────────
ALTER TABLE chat_messages ADD COLUMN seq BIGSERIAL;
ALTER TABLE chat_messages ADD COLUMN gift_id BIGINT;
CREATE UNIQUE INDEX idx_chat_messages_seq ON chat_messages(seq);
CREATE INDEX idx_chat_messages_session_seq ON chat_messages(session_id, seq DESC);

ALTER TABLE chat_messages DROP CONSTRAINT chat_messages_type_check;
ALTER TABLE chat_messages
    ADD CONSTRAINT chat_messages_type_check
    CHECK (type = ANY (ARRAY[
        'text'::text, 'emoji'::text, 'system'::text,
        'bot'::text, 'bot_error'::text, 'gift'::text
    ]));

-- ── live_gift_catalog: the purchasable gift types ──────────────────────────
CREATE TABLE live_gift_catalog (
    id            BIGSERIAL PRIMARY KEY,
    code          TEXT NOT NULL UNIQUE,
    name          TEXT NOT NULL,
    icon_url      TEXT,
    point_cost    INTEGER NOT NULL CHECK (point_cost > 0),
    display_value INTEGER NOT NULL DEFAULT 0,
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order    INTEGER NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO live_gift_catalog (code, name, point_cost, display_value, sort_order) VALUES
    ('rose',   'Hoa hồng',    10,   10,   1),
    ('heart',  'Trái tim',    50,   50,   2),
    ('star',   'Ngôi sao',    100,  100,  3),
    ('rocket', 'Tên lửa',     500,  500,  4),
    ('crown',  'Vương miện',  1000, 1000, 5);

-- ── live_gifts: every gift sent on a stream ────────────────────────────────
CREATE TABLE live_gifts (
    id             BIGSERIAL PRIMARY KEY,
    session_id     UUID NOT NULL REFERENCES live_sessions(id) ON DELETE CASCADE,
    stream_key     TEXT NOT NULL,
    sender_user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    gift_id        BIGINT NOT NULL REFERENCES live_gift_catalog(id),
    quantity       INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    total_points   INTEGER NOT NULL,
    display_value  INTEGER NOT NULL DEFAULT 0,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_live_gifts_session_time ON live_gifts(session_id, created_at DESC);
CREATE INDEX idx_live_gifts_stream_key   ON live_gifts(stream_key, id DESC);

-- ── user_loyalty: point balance gifts are charged against ──────────────────
CREATE TABLE user_loyalty (
    user_id    UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
    points     INTEGER NOT NULL DEFAULT 0 CHECK (points >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
