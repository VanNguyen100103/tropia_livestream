'use strict';

const supabase = require('../lib/supabase');

// ── Browse / list ─────────────────────────────────────────────────────────────

async function browseProducts({ offset, limit, category, shop, search, sort, min_price, max_price }) {
  let query = supabase
    .from('products')
    .select(`
      id, name, slug, images, base_price, sale_price, unit,
      rating, review_count, total_sold, total_stock,
      shops(id, name, slug, logo_url),
      product_categories!inner(category_id, is_primary,
        categories(id, name, slug)
      )
    `, { count: 'exact' })
    .eq('status', 'active');

  // Lọc theo category (any của nhiều danh mục)
  if (category) {
    query = query.eq('product_categories.category_id', category);
  }
  if (shop)      query = query.eq('shop_id', shop);
  if (min_price) query = query.gte('sale_price', parseInt(min_price, 10));
  if (max_price) query = query.lte('sale_price', parseInt(max_price, 10));
  if (search)    query = query.textSearch('name', search, { type: 'plain', config: 'simple' });

  switch (sort) {
    case 'price_asc':  query = query.order('sale_price', { ascending: true });  break;
    case 'price_desc': query = query.order('sale_price', { ascending: false }); break;
    case 'newest':     query = query.order('created_at', { ascending: false }); break;
    case 'rating':     query = query.order('rating',     { ascending: false }); break;
    default:           query = query.order('total_sold', { ascending: false });
  }

  const { data, error, count } = await query.range(offset, offset + limit - 1);
  if (error) throw error;
  return { data, count };
}

async function findProductBySlug(slug) {
  const { data, error } = await supabase
    .from('products')
    .select(`
      *,
      shops(id, name, slug, logo_url, rating, total_sales),
      product_categories(
        is_primary,
        categories(id, name, slug, parent_id)
      ),
      variant_detail(*)
    `)
    .eq('slug', slug)
    .eq('status', 'active')
    .single();
  if (error || !data) return null;
  return data;
}

async function findProductsByShop({ shopId, offset, limit }) {
  const { data, error, count } = await supabase
    .from('products')
    .select('id, name, slug, images, base_price, sale_price, unit, rating, total_sold, total_stock', { count: 'exact' })
    .eq('shop_id', shopId)
    .eq('status', 'active')
    .order('created_at', { ascending: false })
    .range(offset, offset + limit - 1);
  if (error) throw error;
  return { data, count };
}

// ── Helpers ───────────────────────────────────────────────────────────────────

async function slugExists(slug, excludeId) {
  let query = supabase.from('products').select('id').eq('slug', slug);
  if (excludeId) query = query.neq('id', excludeId);
  const { data } = await query.maybeSingle();
  return !!data;
}

async function assertProductOwner(productId) {
  const { data } = await supabase
    .from('products')
    .select('id, shop_id, shops!inner(seller_id)')
    .eq('id', productId)
    .single();
  return data;
}

// ── Create ────────────────────────────────────────────────────────────────────

async function createProduct(productData) {
  const { data, error } = await supabase
    .from('products')
    .insert(productData)
    .select()
    .single();
  if (error) throw error;
  return data;
}

async function setProductCategories(productId, categoryIds, primaryId) {
  // Xoá categories cũ rồi insert lại
  await supabase.from('product_categories').delete().eq('product_id', productId);
  if (!categoryIds?.length) return;

  const rows = categoryIds.map(cid => ({
    product_id:  productId,
    category_id: cid,
    is_primary:  cid === (primaryId || categoryIds[0]),
  }));
  const { error } = await supabase.from('product_categories').insert(rows);
  if (error) throw error;
}

async function createVariant(productId, variantData) {
  const { attributeValueIds, ...rest } = variantData;
  const { data, error } = await supabase
    .from('product_variants')
    .insert({ ...rest, product_id: productId })
    .select()
    .single();
  if (error) throw error;

  if (attributeValueIds?.length) {
    await setVariantAttributes(data.id, attributeValueIds);
  }
  await supabase.from('products').update({ has_variants: true }).eq('id', productId);
  return data;
}

async function createVariants(productId, variants) {
  if (!variants?.length) return;

  // Batch insert tất cả variants trong 1 query thay vì N queries
  const rows = variants.map(({ attributeValueIds: _, ...rest }) => ({
    ...rest,
    product_id: productId,
  }));
  const { data: inserted, error } = await supabase
    .from('product_variants')
    .insert(rows)
    .select();
  if (error) throw error;

  // Batch insert tất cả variant_attributes trong 1 query
  const attrRows = inserted.flatMap((v, i) => {
    const ids = variants[i].attributeValueIds;
    if (!ids?.length) return [];
    return ids.map(aid => ({ variant_id: v.id, attribute_value_id: aid }));
  });
  if (attrRows.length) {
    const { error: attrErr } = await supabase.from('variant_attributes').insert(attrRows);
    if (attrErr) throw attrErr;
  }

  // 1 lần update has_variants cho cả batch
  await supabase.from('products').update({ has_variants: true }).eq('id', productId);
}

async function createDefaultVariant(productId, price, stock) {
  const { data, error } = await supabase
    .from('product_variants')
    .insert({ product_id: productId, price, stock, is_active: true })
    .select()
    .single();
  if (error) throw error;
  return data;
}

async function setVariantAttributes(variantId, attributeValueIds) {
  await supabase.from('variant_attributes').delete().eq('variant_id', variantId);
  if (!attributeValueIds?.length) return;
  const rows = attributeValueIds.map(vid => ({ variant_id: variantId, attribute_value_id: vid }));
  const { error } = await supabase.from('variant_attributes').insert(rows);
  if (error) throw error;
}

// ── Read ──────────────────────────────────────────────────────────────────────

async function findProductWithVariants(productId) {
  const { data } = await supabase
    .from('products')
    .select(`
      *,
      product_categories(is_primary, categories(id, name, slug)),
      variant_detail(*)
    `)
    .eq('id', productId)
    .single();
  return data;
}

// ── Update / Delete ───────────────────────────────────────────────────────────

async function updateProduct(productId, body) {
  const { data, error } = await supabase
    .from('products').update(body).eq('id', productId).select().single();
  if (error) throw error;
  return data;
}

async function softDeleteProduct(productId) {
  await supabase.from('products').update({ status: 'deleted' }).eq('id', productId);
}

async function updateVariant(productId, variantId, body) {
  const { attributeValueIds, ...rest } = body;
  const { data, error } = await supabase
    .from('product_variants')
    .update(rest)
    .eq('id', variantId)
    .eq('product_id', productId)
    .select()
    .single();
  if (error || !data) return null;

  if (attributeValueIds !== undefined) {
    await setVariantAttributes(variantId, attributeValueIds);
  }
  return data;
}

async function deleteVariant(productId, variantId) {
  const { error } = await supabase
    .from('product_variants')
    .delete()
    .eq('id', variantId)
    .eq('product_id', productId);
  if (error) throw error;
}

async function findSellerProducts({ shopId, offset, limit, status }) {
  let query = supabase
    .from('products')
    .select(`
      *,
      product_categories(is_primary, categories(id, name, slug)),
      variant_detail(id, sku, price, sale_price, stock, is_active, attributes)
    `, { count: 'exact' })
    .eq('shop_id', shopId)
    .order('created_at', { ascending: false })
    .range(offset, offset + limit - 1);

  if (status) query = query.eq('status', status);
  const { data, error, count } = await query;
  if (error) throw error;
  return { data, count };
}

// ── Attribute types & values ──────────────────────────────────────────────────

async function listAttributeTypes() {
  const { data, error } = await supabase
    .from('attribute_types')
    .select(`*, attribute_values(*)`)
    .order('sort_order', { ascending: true });
  if (error) throw error;
  return data;
}

async function createAttributeValue({ attributeTypeId, value, displayName, colorHex, sortOrder }) {
  const { data, error } = await supabase
    .from('attribute_values')
    .insert({
      attribute_type_id: attributeTypeId,
      value,
      display_name: displayName || null,
      color_hex:    colorHex    || null,
      sort_order:   sortOrder   || 0,
    })
    .select()
    .single();
  if (error) throw error;
  return data;
}

module.exports = {
  browseProducts,
  findProductBySlug,
  findProductsByShop,
  slugExists,
  assertProductOwner,
  createProduct,
  setProductCategories,
  createVariant,
  createVariants,
  createDefaultVariant,
  setVariantAttributes,
  findProductWithVariants,
  updateProduct,
  softDeleteProduct,
  updateVariant,
  deleteVariant,
  findSellerProducts,
  listAttributeTypes,
  createAttributeValue,
};
