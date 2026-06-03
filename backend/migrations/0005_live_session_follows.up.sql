-- Track unique followers per live session so the host overlay's
-- "Theo dõi" stat counts distinct users instead of inflating on every
-- tap (the buyer tapping the pill 7 times used to show "7 Theo dõi").
-- Mirrors the live_viewers table — composite PK gives us dedupe for
-- free, and the trigger keeps live_sessions.follow_count in sync so
-- nothing else has to change.

CREATE TABLE IF NOT EXISTS live_session_follows (
    session_id  UUID NOT NULL REFERENCES live_sessions(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    followed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (session_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_live_session_follows_session
    ON live_session_follows(session_id);

-- Recompute follow_count from the dedupe table whenever it changes.
-- Defensive GREATEST(0, ...) to mirror update_live_viewer_count.
CREATE OR REPLACE FUNCTION update_live_follow_count()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        UPDATE live_sessions SET follow_count = follow_count + 1 WHERE id = NEW.session_id;
        RETURN NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        UPDATE live_sessions SET follow_count = GREATEST(0, follow_count - 1) WHERE id = OLD.session_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS live_session_follows_count_trigger ON live_session_follows;
CREATE TRIGGER live_session_follows_count_trigger
    AFTER INSERT OR DELETE ON live_session_follows
    FOR EACH ROW EXECUTE FUNCTION update_live_follow_count();

-- Reset existing inflated counters so the new dedupe table is the
-- single source of truth from this point on.
UPDATE live_sessions SET follow_count = 0 WHERE follow_count > 0;
