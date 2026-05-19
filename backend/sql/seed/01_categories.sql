-- =============================================================================
-- SEED 01: Categories mặc định + Attribute types
-- Nguồn: 011_seed_categories_and_shop.sql, 004_product_categories_attributes.sql
-- Idempotent: ON CONFLICT DO NOTHING
-- =============================================================================

-- ── Categories ────────────────────────────────────────────────────────────────
INSERT INTO public.categories (name, slug, sort_order) VALUES
  ('Thực phẩm',  'thuc-pham',  1),
  ('Rau củ quả', 'rau-cu-qua', 2),
  ('Đồ uống',    'do-uong',    3),
  ('Mẹ & Bé',    'me-va-be',   4),
  ('Thời trang', 'thoi-trang', 5),
  ('Giày dép',   'giay-dep',   6),
  ('Mỹ phẩm',    'my-pham',    7),
  ('Hạt khô',    'hat-kho',    8),
  ('Gia dụng',   'gia-dung',   9),
  ('Điện tử',    'dien-tu',    10)
ON CONFLICT (slug) DO NOTHING;

-- ── Attribute types ───────────────────────────────────────────────────────────
INSERT INTO public.attribute_types (name, slug, sort_order) VALUES
  ('Màu sắc',    'color',    1),
  ('Kích thước', 'size',     2),
  ('Khối lượng', 'weight',   3),
  ('Chất liệu',  'material', 4)
ON CONFLICT (slug) DO NOTHING;
