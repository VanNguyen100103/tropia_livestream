-- =============================================================================
-- 0012: recordings.status += 'expired'
-- =============================================================================
-- VOD retention: recordings on Cloudflare R2 are kept for 30 days, then the
-- worker deletes the R2 object and marks the row 'expired' (r2_key cleared).
-- =============================================================================

ALTER TABLE recordings DROP CONSTRAINT IF EXISTS recordings_status_check;
ALTER TABLE recordings
    ADD CONSTRAINT recordings_status_check
    CHECK (status IN ('pending', 'processing', 'uploaded', 'failed', 'expired'));
