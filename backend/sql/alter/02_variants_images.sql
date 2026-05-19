-- =============================================================================
-- ALTER 02: Đổi product_variants.image_url (single) → images (array)
-- Nguồn: 006_variant_multi_images.sql
-- Chạy NẾU cột image_url vẫn còn tồn tại trong product_variants
-- =============================================================================

-- Cần drop view trước vì view phụ thuộc vào cột image_url
DROP VIEW IF EXISTS public.variant_detail;

ALTER TABLE public.product_variants
  ADD COLUMN IF NOT EXISTS images TEXT[] NOT NULL DEFAULT '{}';

-- Migrate dữ liệu cũ
UPDATE public.product_variants
  SET images = ARRAY[image_url]
  WHERE image_url IS NOT NULL AND images = '{}';

ALTER TABLE public.product_variants DROP COLUMN IF EXISTS image_url;

-- Recreate view (xem ddl/03_attributes.sql để lấy lại định nghĩa đầy đủ)
CREATE OR REPLACE VIEW public.variant_detail WITH (security_barrier = true) AS
SELECT
  pv.id, pv.product_id, pv.sku, pv.price, pv.sale_price,
  pv.stock, pv.images, pv.is_active, pv.created_at,
  COALESCE(
    json_agg(
      json_build_object(
        'typeId',      at.id,    'typeName',    at.name,    'typeSlug',    at.slug,
        'valueId',     av.id,    'value',       av.value,
        'displayName', COALESCE(av.display_name, av.value), 'colorHex',    av.color_hex
      ) ORDER BY at.sort_order
    ) FILTER (WHERE av.id IS NOT NULL),
    '[]'
  ) AS attributes
FROM public.product_variants pv
LEFT JOIN public.variant_attributes va ON va.variant_id = pv.id
LEFT JOIN public.attribute_values   av ON av.id = va.attribute_value_id
LEFT JOIN public.attribute_types    at ON at.id = av.attribute_type_id
GROUP BY pv.id;
