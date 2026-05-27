-- Host can toggle DeepSeek auto-reply for viewer comments during a stream.
-- When TRUE, the worker picks up chat.created events and posts a bot reply
-- if the comment looks like a product question.
ALTER TABLE live_sessions
    ADD COLUMN ai_bot_enabled BOOLEAN NOT NULL DEFAULT FALSE;
