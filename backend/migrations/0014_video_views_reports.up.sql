-- =============================================================================
-- 0014: video_views (dedupe view counting) + video_reports (moderation).
-- =============================================================================
-- view dedup: a logged-in user counts at most once per video (anonymous views
-- still increment via the rate-limited endpoint). Mitigates view-count inflation
-- beyond the per-IP rate limit + client per-session dedupe.
--
-- reports: viewer-submitted report + admin takedown. Posting is already gated to
-- shop owner / approved member / admin, so this is a lightweight accountability
-- layer (report → admin reviews → soft-delete), not a full content-moderation
-- pipeline.
-- =============================================================================

CREATE TABLE video_views (
    video_id   UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (video_id, user_id)
);

CREATE INDEX idx_video_views_user ON video_views(user_id);

CREATE TABLE video_reports (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    video_id    UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    reporter_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    reason      TEXT NOT NULL,
    status      TEXT NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'resolved', 'dismissed')),
    action      TEXT,                                  -- 'takedown' | 'dismiss' once resolved
    resolved_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
    resolved_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- One open report per (video, reporter) — re-reporting updates the reason.
    UNIQUE (video_id, reporter_id)
);

-- Admin queue: pending reports newest-first.
CREATE INDEX idx_video_reports_status ON video_reports(status, created_at DESC);
CREATE INDEX idx_video_reports_video ON video_reports(video_id);
