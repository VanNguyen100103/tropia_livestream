-- =============================================================================
-- RLS 01: Row Level Security cho Core tables
-- Nguồn: 000_initial_schema.sql, 011_seed_categories_and_shop.sql
-- Backend dùng service_role key → bypass RLS hoàn toàn
-- =============================================================================

-- ── Profiles ──────────────────────────────────────────────────────────────────
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "profiles_public_read" ON public.profiles FOR SELECT USING (true);

-- ── Refresh tokens (backend only) ─────────────────────────────────────────────
ALTER TABLE public.refresh_tokens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "refresh_tokens_deny_all" ON public.refresh_tokens USING (false);

-- ── Live sessions ─────────────────────────────────────────────────────────────
ALTER TABLE public.live_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sessions_public_read"  ON public.live_sessions FOR SELECT USING (true);
CREATE POLICY "sessions_seller_write" ON public.live_sessions FOR ALL
  USING (auth.uid() = seller_id);

-- ── Live session products ─────────────────────────────────────────────────────
ALTER TABLE public.live_session_products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "lsp_public_read"  ON public.live_session_products FOR SELECT USING (true);
CREATE POLICY "lsp_seller_write" ON public.live_session_products FOR ALL
  USING (
    auth.uid() = (
      SELECT seller_id FROM public.live_sessions WHERE id = session_id LIMIT 1
    )
  );

-- ── Chat messages ─────────────────────────────────────────────────────────────
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "chat_public_read" ON public.chat_messages FOR SELECT USING (true);
CREATE POLICY "chat_auth_insert" ON public.chat_messages FOR INSERT
  WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

-- ── Live orders ───────────────────────────────────────────────────────────────
ALTER TABLE public.live_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "orders_buyer_read"  ON public.live_orders FOR SELECT
  USING (auth.uid() = buyer_id);
CREATE POLICY "orders_seller_read" ON public.live_orders FOR SELECT
  USING (
    auth.uid() = (
      SELECT seller_id FROM public.live_sessions WHERE id = session_id LIMIT 1
    )
  );
CREATE POLICY "orders_auth_insert" ON public.live_orders FOR INSERT
  WITH CHECK (auth.uid() = buyer_id);

-- ── Live viewers ──────────────────────────────────────────────────────────────
ALTER TABLE public.live_viewers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "viewers_public_read" ON public.live_viewers FOR SELECT USING (true);
CREATE POLICY "viewers_auth_write"  ON public.live_viewers FOR ALL
  USING (auth.uid() = user_id);
