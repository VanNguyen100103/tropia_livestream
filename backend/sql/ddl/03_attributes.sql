-- =============================================================================
-- DDL 03: Attributes – Types, Values, Variant links, View
-- Nguồn: 004_product_categories_attributes.sql, 013_rls_variant_attributes.sql
-- Yêu cầu: 02_marketplace.sql đã chạy
-- =============================================================================

-- ── Attribute types (Size, Color, Weight...) ──────────────────────────────────
CREATE TABLE IF NOT EXISTS public.attribute_types (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name       TEXT NOT NULL UNIQUE,
  slug       TEXT NOT NULL UNIQUE,
  sort_order INT  NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_attr_types_slug ON public.attribute_types(slug);

-- ── Attribute values (Đỏ, S, M, 500g...) ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.attribute_values (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  attribute_type_id UUID NOT NULL REFERENCES public.attribute_types(id) ON DELETE CASCADE,
  value             TEXT NOT NULL,
  display_name      TEXT,
  color_hex         TEXT,
  sort_order        INT  NOT NULL DEFAULT 0,
  UNIQUE (attribute_type_id, value)
);

CREATE INDEX IF NOT EXISTS idx_attr_values_type ON public.attribute_values(attribute_type_id);

-- ── Variant ↔ Attribute values (many-to-many) ─────────────────────────────────
CREATE TABLE IF NOT EXISTS public.variant_attributes (
  variant_id          UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
  attribute_value_id  UUID NOT NULL REFERENCES public.attribute_values(id) ON DELETE CASCADE,
  PRIMARY KEY (variant_id, attribute_value_id)
);

CREATE INDEX IF NOT EXISTS idx_variant_attrs_variant ON public.variant_attributes(variant_id);
CREATE INDEX IF NOT EXISTS idx_variant_attrs_value   ON public.variant_attributes(attribute_value_id);

-- ── View: variant với attributes đã join ─────────────────────────────────────
CREATE OR REPLACE VIEW public.variant_detail WITH (security_barrier = true) AS
SELECT
  pv.id,
  pv.product_id,
  pv.sku,
  pv.price,
  pv.sale_price,
  pv.stock,
  pv.images,
  pv.is_active,
  pv.created_at,
  COALESCE(
    json_agg(
      json_build_object(
        'typeId',      at.id,
        'typeName',    at.name,
        'typeSlug',    at.slug,
        'valueId',     av.id,
        'value',       av.value,
        'displayName', COALESCE(av.display_name, av.value),
        'colorHex',    av.color_hex
      ) ORDER BY at.sort_order
    ) FILTER (WHERE av.id IS NOT NULL),
    '[]'
  ) AS attributes
FROM public.product_variants pv
LEFT JOIN public.variant_attributes va ON va.variant_id = pv.id
LEFT JOIN public.attribute_values   av ON av.id = va.attribute_value_id
LEFT JOIN public.attribute_types    at ON at.id = av.attribute_type_id
GROUP BY pv.id;
