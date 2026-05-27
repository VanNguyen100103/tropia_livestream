-- Revert chat_messages.type back to the original three-value enum.
-- Any existing bot/bot_error rows must be cleaned up first or the new
-- constraint will refuse to install.

DELETE FROM chat_messages WHERE type IN ('bot', 'bot_error');

ALTER TABLE chat_messages
    DROP CONSTRAINT chat_messages_type_check;

ALTER TABLE chat_messages
    ADD CONSTRAINT chat_messages_type_check
    CHECK (type = ANY (ARRAY['text'::text, 'emoji'::text, 'system'::text]));
