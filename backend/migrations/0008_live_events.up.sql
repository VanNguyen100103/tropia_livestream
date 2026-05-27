-- Timeline of host actions during a live session, used to re-create the
-- live UI overlay (pinned product, bot toggle, coupon announcement,
-- product spotlight changes) when replaying the recorded VOD.
--
-- Chat is NOT duplicated here — chat_messages.created_at is the source
-- of truth for chat replay; the /timeline endpoint merges both tables.
--
-- stream_offset_ms is computed at write-time as (NOW() - sessions.started_at)
-- in milliseconds, so the replay player can sync events to the MP4 timeline
-- without needing wall-clock conversion. Stored as BIGINT to comfortably
-- hold multi-hour sessions.

CREATE TABLE live_events (
    id              BIGSERIAL    PRIMARY KEY,
    session_id      uuid         NOT NULL REFERENCES live_sessions(id) ON DELETE CASCADE,
    event_type      varchar(32)  NOT NULL,
    payload         jsonb        NOT NULL DEFAULT '{}'::jsonb,
    stream_offset_ms bigint      NOT NULL,
    created_at      timestamptz  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_live_events_session_offset
    ON live_events (session_id, stream_offset_ms);
