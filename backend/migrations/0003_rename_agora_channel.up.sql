-- =============================================================================
-- 0003: rename live_sessions.agora_channel → stream_key
-- =============================================================================
-- Historical name from the original Agora-based prototype. Stack moved to
-- SRS during Phase 16; the column has always held the SRS stream key —
-- only the name was stale. Renaming for clarity.
-- =============================================================================

ALTER TABLE live_sessions RENAME COLUMN agora_channel TO stream_key;

-- Index + UNIQUE constraint names also reference the old term; rename
-- so DDL queries stay consistent.
ALTER INDEX idx_live_sessions_channel RENAME TO idx_live_sessions_stream_key;
ALTER TABLE live_sessions
    RENAME CONSTRAINT live_sessions_agora_channel_key TO live_sessions_stream_key_key;
