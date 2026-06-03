-- Allow bot replies in chat_messages.
--
-- The DeepSeek auto-reply path (handler.maybeBotReply) inserts rows with
-- type='bot' (success) or type='bot_error' (DeepSeek failure surfaced into
-- the chat stream for debugging). Both were rejected by the old constraint
-- which only allowed text|emoji|system, so bot replies silently failed
-- with SQLSTATE 23514 — they never reached viewers even though DeepSeek
-- returned 200 OK.

ALTER TABLE chat_messages
    DROP CONSTRAINT chat_messages_type_check;

ALTER TABLE chat_messages
    ADD CONSTRAINT chat_messages_type_check
    CHECK (type = ANY (ARRAY['text'::text, 'emoji'::text, 'system'::text, 'bot'::text, 'bot_error'::text]));
