-- =============================================================================
-- ALTER 05: Thêm is_host vào chat_messages
-- Nguồn: sql/add_chat_is_host.sql
-- =============================================================================

ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS is_host BOOLEAN NOT NULL DEFAULT FALSE;
