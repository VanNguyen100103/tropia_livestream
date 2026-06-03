-- Reverse 0010.

DROP TABLE IF EXISTS user_loyalty;
DROP TABLE IF EXISTS live_gifts;
DROP TABLE IF EXISTS live_gift_catalog;

DROP INDEX IF EXISTS idx_chat_messages_session_seq;
DROP INDEX IF EXISTS idx_chat_messages_seq;
ALTER TABLE chat_messages DROP COLUMN IF EXISTS gift_id;
ALTER TABLE chat_messages DROP COLUMN IF EXISTS seq;
ALTER TABLE chat_messages DROP CONSTRAINT IF EXISTS chat_messages_type_check;
ALTER TABLE chat_messages
    ADD CONSTRAINT chat_messages_type_check
    CHECK (type = ANY (ARRAY['text'::text, 'emoji'::text, 'system'::text, 'bot'::text, 'bot_error'::text]));

DROP INDEX IF EXISTS idx_live_sessions_seq;
ALTER TABLE live_sessions DROP COLUMN IF EXISTS publish_token_expires_at;
ALTER TABLE live_sessions DROP COLUMN IF EXISTS publish_token;
ALTER TABLE live_sessions DROP COLUMN IF EXISTS seq;
ALTER TABLE live_sessions DROP CONSTRAINT IF EXISTS live_sessions_status_check;
ALTER TABLE live_sessions
    ADD CONSTRAINT live_sessions_status_check
    CHECK (status IN ('scheduled', 'live', 'ended'));

DROP INDEX IF EXISTS idx_profiles_seq;
ALTER TABLE profiles DROP COLUMN IF EXISTS seq;
