-- =============================================================================
-- 0013: videos — short-form video feed (Shopee Video / TikTok style).
-- =============================================================================
-- Separate from live_sessions: these are uploaded MP4 clips that play in a
-- vertical "for you" feed, not RTMP/HLS broadcasts.
--
-- Who may POST a video is gated the same way as livestreaming (shop owner /
-- approved member with can_live / admin) — enforced in the API layer via
-- live.RequireLivePermission. Anyone may WATCH the feed (no auth).
--
-- Counters (view/like/comment/share) are denormalised onto `videos` and kept
-- in sync with the join tables by the repository (UPDATE ... SET x = x + 1),
-- mirroring how live_sessions tracks like_count etc.
-- =============================================================================

-- =============================================================================
-- 1. VIDEOS
-- =============================================================================
CREATE TABLE videos (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    -- Shop the clip is attributed to (resolved from the poster's live
    -- permission at create time). NULL for admin posters with no shop.
    shop_id         UUID REFERENCES shops(id) ON DELETE SET NULL,
    video_url       TEXT NOT NULL,                  -- absolute (R2) or "/uploads/..." path
    thumbnail_url   TEXT,                           -- optional cover image
    caption         TEXT,
    hashtags        TEXT[] NOT NULL DEFAULT '{}',
    duration_sec    INTEGER NOT NULL DEFAULT 0,
    width           INTEGER NOT NULL DEFAULT 0,
    height          INTEGER NOT NULL DEFAULT 0,
    allow_reuse     BOOLEAN NOT NULL DEFAULT TRUE,  -- "Cho phép sử dụng lại nội dung"
    status          TEXT NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active', 'deleted')),
    view_count      INTEGER NOT NULL DEFAULT 0,
    like_count      INTEGER NOT NULL DEFAULT 0,
    comment_count   INTEGER NOT NULL DEFAULT 0,
    share_count     INTEGER NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Feed ordering (recency) + per-creator profile grid.
CREATE INDEX idx_videos_active_recent ON videos(created_at DESC) WHERE status = 'active';
CREATE INDEX idx_videos_user ON videos(user_id, created_at DESC);
-- Hashtag search ("#linhtran").
CREATE INDEX idx_videos_hashtags ON videos USING GIN (hashtags);

CREATE TRIGGER videos_updated_at BEFORE UPDATE ON videos
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =============================================================================
-- 2. VIDEO_LIKES (one row per (video, user))
-- =============================================================================
CREATE TABLE video_likes (
    video_id    UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (video_id, user_id)
);

CREATE INDEX idx_video_likes_user ON video_likes(user_id);

-- =============================================================================
-- 3. VIDEO_COMMENTS
-- =============================================================================
CREATE TABLE video_comments (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    video_id    UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    content     TEXT NOT NULL,
    like_count  INTEGER NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_video_comments_video ON video_comments(video_id, created_at DESC);

-- =============================================================================
-- 4. USER_FOLLOWS (follow a creator — distinct from shop_follows)
-- =============================================================================
CREATE TABLE user_follows (
    follower_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    followee_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (follower_id, followee_id),
    -- A user can't follow themselves.
    CHECK (follower_id <> followee_id)
);

CREATE INDEX idx_user_follows_followee ON user_follows(followee_id);
