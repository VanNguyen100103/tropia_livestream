-- 0019: store an overlay-baked copy of each short-form video.
--
-- The feed keeps playing videos.video_url (the RAW clip) so the live Flutter
-- overlay stays interactive — like/comment counts update, the flash-sale
-- countdown ticks, and the "Mua với Voucher" / "Xem sản phẩm" buttons stay
-- tappable. None of that can be burned into a static file.
--
-- Separately, the background worker bakes a STATIC-overlay copy (shop handle +
-- caption + product card + voucher badge + Tropia watermark) for download /
-- sharing the clip outside the app. That copy's URL lands in overlay_url.
--
--   overlay_status: pending → processing → ready | failed | skipped
--     skipped = R2/worker not available (local dev) — no bake attempted.
ALTER TABLE videos
    ADD COLUMN overlay_url    TEXT,
    ADD COLUMN overlay_status TEXT NOT NULL DEFAULT 'pending';

-- Rows that already existed were never queued for a bake — mark them skipped so
-- a future "reprocess pending" sweep doesn't pick them up.
UPDATE videos SET overlay_status = 'skipped';
