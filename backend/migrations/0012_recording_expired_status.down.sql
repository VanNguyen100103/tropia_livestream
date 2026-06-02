-- Reverse 0012.
ALTER TABLE recordings DROP CONSTRAINT IF EXISTS recordings_status_check;
ALTER TABLE recordings
    ADD CONSTRAINT recordings_status_check
    CHECK (status IN ('pending', 'processing', 'uploaded', 'failed'));
