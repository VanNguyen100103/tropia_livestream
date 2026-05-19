-- =============================================================================
-- SEED 04: Coupon mẫu
-- Nguồn: 014_seed_coupons.sql
-- Idempotent: ON CONFLICT (code) DO UPDATE
-- =============================================================================

INSERT INTO public.coupons (code, discount_type, discount_value, min_order_value, max_discount, max_uses, expires_at, is_active)
VALUES
  -- Giảm % có giới hạn tối đa
  ('WELCOME10', 'percent', 10,  0,       50000,  1000, now() + interval '90 days', true),
  ('SALE20',    'percent', 20,  200000,  100000, 500,  now() + interval '30 days', true),
  ('FLASH50',   'percent', 50,  500000,  200000, 100,  now() + interval '3 days',  true),
  ('TROPIA15',  'percent', 15,  100000,  75000,  null, now() + interval '60 days', true),

  -- Giảm tiền cố định
  ('GIAM30K',   'fixed',   30000,  150000, null, 200, now() + interval '30 days', true),
  ('GIAM50K',   'fixed',   50000,  300000, null, 100, now() + interval '30 days', true),
  ('GIAM100K',  'fixed',   100000, 600000, null, 50,  now() + interval '15 days', true),

  -- Voucher không giới hạn lượt
  ('FREESHIP',  'fixed',   20000,  0,     null, null, now() + interval '60 days', true),
  ('NEWUSER',   'percent', 25,     50000, 80000, null, now() + interval '7 days',  true)

ON CONFLICT (code) DO UPDATE SET
  expires_at     = EXCLUDED.expires_at,
  is_active      = EXCLUDED.is_active,
  max_uses       = EXCLUDED.max_uses,
  discount_value = EXCLUDED.discount_value;
