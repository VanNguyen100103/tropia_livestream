-- =============================================================================
-- RLS 02: Row Level Security cho Marketplace tables
-- Nguồn: 011_seed_categories_and_shop.sql, 013_rls_variant_attributes.sql
-- =============================================================================

-- ── Categories ────────────────────────────────────────────────────────────────
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "categories_public_read" ON public.categories;
CREATE POLICY "categories_public_read" ON public.categories
  FOR SELECT USING (is_active = true);

-- ── Shops ─────────────────────────────────────────────────────────────────────
ALTER TABLE public.shops ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "shops_public_read"   ON public.shops;
DROP POLICY IF EXISTS "shops_seller_update" ON public.shops;
CREATE POLICY "shops_public_read"   ON public.shops FOR SELECT USING (is_active = true);
CREATE POLICY "shops_seller_update" ON public.shops FOR UPDATE USING (seller_id = auth.uid());

-- ── Products ──────────────────────────────────────────────────────────────────
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "products_public_read" ON public.products;
DROP POLICY IF EXISTS "products_seller_all"  ON public.products;
CREATE POLICY "products_public_read" ON public.products
  FOR SELECT USING (status IN ('active', 'inactive'));
CREATE POLICY "products_seller_all"  ON public.products
  FOR ALL USING (
    shop_id IN (SELECT id FROM public.shops WHERE seller_id = auth.uid())
  );

-- ── Product variants ──────────────────────────────────────────────────────────
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "variants_public_read" ON public.product_variants;
DROP POLICY IF EXISTS "variants_seller_all"  ON public.product_variants;
CREATE POLICY "variants_public_read" ON public.product_variants
  FOR SELECT USING (
    product_id IN (SELECT id FROM public.products WHERE status IN ('active','inactive'))
  );
CREATE POLICY "variants_seller_all" ON public.product_variants
  FOR ALL USING (
    product_id IN (
      SELECT p.id FROM public.products p
      JOIN public.shops s ON s.id = p.shop_id
      WHERE s.seller_id = auth.uid()
    )
  );

-- ── Product categories ────────────────────────────────────────────────────────
ALTER TABLE public.product_categories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "product_categories_public_read" ON public.product_categories;
DROP POLICY IF EXISTS "product_categories_seller_all"  ON public.product_categories;
CREATE POLICY "product_categories_public_read" ON public.product_categories
  FOR SELECT USING (true);
CREATE POLICY "product_categories_seller_all"  ON public.product_categories
  FOR ALL USING (
    product_id IN (
      SELECT p.id FROM public.products p
      JOIN public.shops s ON s.id = p.shop_id
      WHERE s.seller_id = auth.uid()
    )
  );

-- ── Attribute types & values (public read) ────────────────────────────────────
ALTER TABLE public.attribute_types ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "attr_types_public_read" ON public.attribute_types;
CREATE POLICY "attr_types_public_read" ON public.attribute_types FOR SELECT USING (true);

ALTER TABLE public.attribute_values ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "attr_values_public_read" ON public.attribute_values;
CREATE POLICY "attr_values_public_read" ON public.attribute_values FOR SELECT USING (true);

-- ── Variant attributes ────────────────────────────────────────────────────────
ALTER TABLE public.variant_attributes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "variant_attrs_public_read" ON public.variant_attributes;
DROP POLICY IF EXISTS "variant_attrs_seller_all"  ON public.variant_attributes;
CREATE POLICY "variant_attrs_public_read" ON public.variant_attributes
  FOR SELECT USING (
    variant_id IN (
      SELECT pv.id FROM public.product_variants pv
      JOIN public.products p ON p.id = pv.product_id
      WHERE p.status IN ('active', 'inactive')
    )
  );
CREATE POLICY "variant_attrs_seller_all" ON public.variant_attributes
  FOR ALL USING (
    variant_id IN (
      SELECT pv.id FROM public.product_variants pv
      JOIN public.products p ON p.id = pv.product_id
      JOIN public.shops s ON s.id = p.shop_id
      WHERE s.seller_id = auth.uid()
    )
  );

-- ── Cart items & Shop follows ─────────────────────────────────────────────────
ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "cart_owner_only" ON public.cart_items;
CREATE POLICY "cart_owner_only" ON public.cart_items
  USING (auth.uid() = user_id);

ALTER TABLE public.shop_follows ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "shop_follows_owner" ON public.shop_follows;
CREATE POLICY "shop_follows_owner" ON public.shop_follows
  USING (auth.uid() = user_id);
