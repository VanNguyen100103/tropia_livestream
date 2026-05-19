-- =============================================================================
-- SEED 03: Sản phẩm mẫu (10 sản phẩm)
-- Nguồn: 012_seed_products.sql, 015_default_variant_for_simple_products.sql
-- Yêu cầu: 01_categories.sql + 02_auto_shop.sql đã chạy
-- =============================================================================

DO $$
DECLARE
  v_shop_id       UUID;
  v_cat_thucpham  UUID; v_cat_raucu    UUID; v_cat_douong   UUID;
  v_cat_mybe      UUID; v_cat_mypham   UUID; v_cat_hatkho   UUID;
  v_attr_color    UUID; v_attr_size    UUID; v_attr_weight  UUID;
  v_val_s UUID; v_val_m UUID; v_val_l UUID;
  v_val_500g UUID; v_val_1kg UUID; v_val_5kg UUID;
  v_p1 UUID; v_p2 UUID; v_p3 UUID; v_p4 UUID; v_p5 UUID;
  v_p6 UUID; v_p7 UUID; v_p8 UUID; v_p9 UUID; v_p10 UUID;
BEGIN
  SELECT id INTO v_shop_id FROM public.shops WHERE is_active = true LIMIT 1;
  IF v_shop_id IS NULL THEN
    RAISE EXCEPTION 'Chưa có shop. Chạy seed/02_auto_shop.sql trước!';
  END IF;

  SELECT id INTO v_cat_thucpham FROM public.categories WHERE slug = 'thuc-pham';
  SELECT id INTO v_cat_raucu    FROM public.categories WHERE slug = 'rau-cu-qua';
  SELECT id INTO v_cat_douong   FROM public.categories WHERE slug = 'do-uong';
  SELECT id INTO v_cat_mybe     FROM public.categories WHERE slug = 'me-va-be';
  SELECT id INTO v_cat_mypham   FROM public.categories WHERE slug = 'my-pham';
  SELECT id INTO v_cat_hatkho   FROM public.categories WHERE slug = 'hat-kho';

  SELECT id INTO v_attr_color  FROM public.attribute_types WHERE slug = 'color';
  SELECT id INTO v_attr_size   FROM public.attribute_types WHERE slug = 'size';
  SELECT id INTO v_attr_weight FROM public.attribute_types WHERE slug = 'weight';

  INSERT INTO public.attribute_values (attribute_type_id, value, sort_order) VALUES
    (v_attr_size,   'S',     1), (v_attr_size,   'M',     2), (v_attr_size,   'L',     3),
    (v_attr_weight, '500g',  1), (v_attr_weight, '1kg',   2), (v_attr_weight, '5kg',   3),
    (v_attr_color,  'Đỏ',    1), (v_attr_color,  'Xanh',  2), (v_attr_color,  'Trắng', 3)
  ON CONFLICT (attribute_type_id, value) DO NOTHING;

  SELECT id INTO v_val_s    FROM public.attribute_values WHERE attribute_type_id = v_attr_size   AND value = 'S';
  SELECT id INTO v_val_m    FROM public.attribute_values WHERE attribute_type_id = v_attr_size   AND value = 'M';
  SELECT id INTO v_val_l    FROM public.attribute_values WHERE attribute_type_id = v_attr_size   AND value = 'L';
  SELECT id INTO v_val_500g FROM public.attribute_values WHERE attribute_type_id = v_attr_weight AND value = '500g';
  SELECT id INTO v_val_1kg  FROM public.attribute_values WHERE attribute_type_id = v_attr_weight AND value = '1kg';
  SELECT id INTO v_val_5kg  FROM public.attribute_values WHERE attribute_type_id = v_attr_weight AND value = '5kg';

  -- 1. Gạo ST25
  INSERT INTO public.products (shop_id, name, slug, description, images, base_price, sale_price, unit, status, has_variants, total_stock)
  VALUES (v_shop_id, 'Gạo ST25 Thơm Đặc Sản Sóc Trăng', 'gao-st25-thom-dac-san-soc-trang',
    'Gạo ST25 được vinh danh gạo ngon nhất thế giới, hạt dài, thơm dẻo.', '{}', 180000, 149000, 'túi', 'active', true, 0)
  RETURNING id INTO v_p1;
  INSERT INTO public.product_categories VALUES (v_p1, v_cat_thucpham, true) ON CONFLICT DO NOTHING;
  WITH v AS (INSERT INTO public.product_variants (product_id,sku,price,sale_price,stock,images) VALUES (v_p1,'ST25-500G',55000,45000,100,'{}') RETURNING id)
    INSERT INTO public.variant_attributes SELECT id, v_val_500g FROM v;
  WITH v AS (INSERT INTO public.product_variants (product_id,sku,price,sale_price,stock,images) VALUES (v_p1,'ST25-1KG',100000,85000,150,'{}') RETURNING id)
    INSERT INTO public.variant_attributes SELECT id, v_val_1kg FROM v;
  WITH v AS (INSERT INTO public.product_variants (product_id,sku,price,sale_price,stock,images) VALUES (v_p1,'ST25-5KG',450000,390000,80,'{}') RETURNING id)
    INSERT INTO public.variant_attributes SELECT id, v_val_5kg FROM v;

  -- 2. Thịt heo ba chỉ (no variant)
  INSERT INTO public.products (shop_id, name, slug, description, images, base_price, sale_price, unit, status, has_variants, total_stock)
  VALUES (v_shop_id, 'Thịt Heo Ba Chỉ Tươi Sạch', 'thit-heo-ba-chi-tuoi-sach',
    'Thịt heo ba chỉ tươi, nhập mỗi ngày, đảm bảo vệ sinh an toàn thực phẩm.', '{}', 120000, 105000, 'kg', 'active', false, 200)
  RETURNING id INTO v_p2;
  INSERT INTO public.product_categories VALUES (v_p2, v_cat_thucpham, true) ON CONFLICT DO NOTHING;

  -- 3. Trứng gà ta (no variant)
  INSERT INTO public.products (shop_id, name, slug, description, images, base_price, sale_price, unit, status, has_variants, total_stock)
  VALUES (v_shop_id, 'Trứng Gà Ta Sạch Hộp 10 Quả', 'trung-ga-ta-sach-hop-10-qua',
    'Trứng gà ta nuôi thả vườn, không chất kích thích.', '{}', 45000, 38000, 'hộp', 'active', false, 300)
  RETURNING id INTO v_p3;
  INSERT INTO public.product_categories VALUES (v_p3, v_cat_thucpham, true) ON CONFLICT DO NOTHING;

  -- 4. Bộ rau củ (no variant)
  INSERT INTO public.products (shop_id, name, slug, description, images, base_price, sale_price, unit, status, has_variants, total_stock)
  VALUES (v_shop_id, 'Bộ Rau Củ Tươi Hàng Ngày', 'bo-rau-cu-tuoi-hang-ngay',
    'Combo rau củ tươi sạch cho bữa ăn gia đình.', '{}', 85000, 69000, 'bộ', 'active', false, 150)
  RETURNING id INTO v_p4;
  INSERT INTO public.product_categories VALUES (v_p4, v_cat_raucu, true) ON CONFLICT DO NOTHING;

  -- 5. Bơ Đà Lạt (no variant)
  INSERT INTO public.products (shop_id, name, slug, description, images, base_price, sale_price, unit, status, has_variants, total_stock)
  VALUES (v_shop_id, 'Bơ Đà Lạt Booth 7 Chín Cây', 'bo-da-lat-booth-7-chin-cay',
    'Bơ Booth 7 Đà Lạt, béo mịn, trái to, thu hoạch chín cây.', '{}', 65000, 55000, 'kg', 'active', false, 100)
  RETURNING id INTO v_p5;
  INSERT INTO public.product_categories VALUES (v_p5, v_cat_raucu, true) ON CONFLICT DO NOTHING;

  -- 6. Trà sữa Thái (no variant)
  INSERT INTO public.products (shop_id, name, slug, description, images, base_price, sale_price, unit, status, has_variants, total_stock)
  VALUES (v_shop_id, 'Trà Sữa Thái Đỏ Hộp 24 Gói', 'tra-sua-thai-do-hop-24-goi',
    'Trà sữa Thái đỏ chính hãng, vị đậm đà.', '{}', 180000, 155000, 'hộp', 'active', false, 200)
  RETURNING id INTO v_p6;
  INSERT INTO public.product_categories VALUES (v_p6, v_cat_douong, true) ON CONFLICT DO NOTHING;

  -- 7. Cà phê rang xay
  INSERT INTO public.products (shop_id, name, slug, description, images, base_price, sale_price, unit, status, has_variants, total_stock)
  VALUES (v_shop_id, 'Cà Phê Rang Xay Buôn Ma Thuột', 'ca-phe-rang-xay-buon-ma-thuot',
    'Cà phê nguyên chất 100%, rang xay tại xưởng.', '{}', 120000, 99000, 'túi', 'active', true, 0)
  RETURNING id INTO v_p7;
  INSERT INTO public.product_categories VALUES (v_p7, v_cat_douong, true) ON CONFLICT DO NOTHING;
  WITH v AS (INSERT INTO public.product_variants (product_id,sku,price,sale_price,stock,images) VALUES (v_p7,'CF-500G',120000,99000,80,'{}') RETURNING id)
    INSERT INTO public.variant_attributes SELECT id, v_val_500g FROM v;
  WITH v AS (INSERT INTO public.product_variants (product_id,sku,price,sale_price,stock,images) VALUES (v_p7,'CF-1KG',220000,185000,60,'{}') RETURNING id)
    INSERT INTO public.variant_attributes SELECT id, v_val_1kg FROM v;

  -- 8. Tã Pampers
  INSERT INTO public.products (shop_id, name, slug, description, images, base_price, sale_price, unit, status, has_variants, total_stock)
  VALUES (v_shop_id, 'Tã Dán Pampers Premium Care', 'ta-dan-pampers-premium-care',
    'Tã dán Pampers Premium Care siêu mềm, thấm hút tốt.', '{}', 285000, 249000, 'gói', 'active', true, 0)
  RETURNING id INTO v_p8;
  INSERT INTO public.product_categories VALUES (v_p8, v_cat_mybe, true) ON CONFLICT DO NOTHING;
  WITH v AS (INSERT INTO public.product_variants (product_id,sku,price,sale_price,stock,images) VALUES (v_p8,'TAM-S',285000,249000,100,'{}') RETURNING id)
    INSERT INTO public.variant_attributes SELECT id, v_val_s FROM v;
  WITH v AS (INSERT INTO public.product_variants (product_id,sku,price,sale_price,stock,images) VALUES (v_p8,'TAM-M',299000,265000,120,'{}') RETURNING id)
    INSERT INTO public.variant_attributes SELECT id, v_val_m FROM v;
  WITH v AS (INSERT INTO public.product_variants (product_id,sku,price,sale_price,stock,images) VALUES (v_p8,'TAM-L',315000,279000,80,'{}') RETURNING id)
    INSERT INTO public.variant_attributes SELECT id, v_val_l FROM v;

  -- 9. Kem chống nắng (no variant)
  INSERT INTO public.products (shop_id, name, slug, description, images, base_price, sale_price, unit, status, has_variants, total_stock)
  VALUES (v_shop_id, 'Kem Chống Nắng Anessa SPF50+', 'kem-chong-nang-anessa-spf50',
    'Kem chống nắng Anessa Perfect UV SPF50+ PA++++.', '{}', 580000, 489000, 'tuýp', 'active', false, 50)
  RETURNING id INTO v_p9;
  INSERT INTO public.product_categories VALUES (v_p9, v_cat_mypham, true) ON CONFLICT DO NOTHING;

  -- 10. Hạt điều rang muối
  INSERT INTO public.products (shop_id, name, slug, description, images, base_price, sale_price, unit, status, has_variants, total_stock)
  VALUES (v_shop_id, 'Hạt Điều Rang Muối Bình Phước', 'hat-dieu-rang-muoi-binh-phuoc',
    'Hạt điều Bình Phước loại 1, rang muối vừa, giòn thơm.', '{}', 220000, 185000, 'túi', 'active', true, 0)
  RETURNING id INTO v_p10;
  INSERT INTO public.product_categories VALUES (v_p10, v_cat_hatkho, true) ON CONFLICT DO NOTHING;
  WITH v AS (INSERT INTO public.product_variants (product_id,sku,price,sale_price,stock,images) VALUES (v_p10,'DIEU-500G',220000,185000,120,'{}') RETURNING id)
    INSERT INTO public.variant_attributes SELECT id, v_val_500g FROM v;
  WITH v AS (INSERT INTO public.product_variants (product_id,sku,price,sale_price,stock,images) VALUES (v_p10,'DIEU-1KG',410000,350000,80,'{}') RETURNING id)
    INSERT INTO public.variant_attributes SELECT id, v_val_1kg FROM v;

  -- Cập nhật total_stock
  UPDATE public.products SET total_stock = (
    SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE product_id = products.id
  ) WHERE has_variants = true;

  -- Tạo default variant cho sản phẩm không có variant (migration 015)
  INSERT INTO public.product_variants (product_id, sku, price, sale_price, stock, images, is_active)
  SELECT p.id, 'DEFAULT-' || substring(p.id::text, 1, 8),
    p.base_price, COALESCE(p.sale_price, p.base_price), p.total_stock, p.images, true
  FROM public.products p
  WHERE p.has_variants = false
    AND NOT EXISTS (SELECT 1 FROM public.product_variants pv WHERE pv.product_id = p.id);

  RAISE NOTICE 'Đã seed 10 sản phẩm mẫu vào shop: %', v_shop_id;
END $$;
