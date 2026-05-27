-- Rollback rename.
ALTER TABLE live_sessions
    RENAME CONSTRAINT live_sessions_stream_key_key TO live_sessions_agora_channel_key;
ALTER INDEX idx_live_sessions_stream_key RENAME TO idx_live_sessions_channel;
ALTER TABLE live_sessions RENAME COLUMN stream_key TO agora_channel;
