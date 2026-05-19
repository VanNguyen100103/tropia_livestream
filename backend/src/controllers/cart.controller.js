'use strict';

const { z }   = require('zod');
const repo    = require('../repositories/cart.repository');
const supabase = require('../lib/supabase');

// Lấy giỏ hàng + tính tổng
async function getCart(req, res, next) {
  try {
    const items = await repo.getCart(req.user.id);
    const selectedItems = items.filter(i => i.is_selected);
    const totalItems    = selectedItems.reduce((s, i) => s + i.quantity, 0);
    const totalPrice    = selectedItems.reduce((s, i) => s + i.unit_price * i.quantity, 0);
    const totalSaving   = selectedItems.reduce((s, i) => s + (i.original_price - i.unit_price) * i.quantity, 0);
    res.json({ items, summary: { totalItems, totalPrice, totalSaving } });
  } catch (e) { next(e); }
}

const addSchema = z.object({
  variantId: z.string().uuid(),
  quantity:  z.number().int().min(1).max(999).default(1),
});

// Thêm vào giỏ — tự động build snapshot từ DB
async function addItem(req, res, next) {
  try {
    const { variantId, quantity } = addSchema.parse(req.body);

    // Lấy thông tin variant + product + shop để build snapshot
    let { data: variant, error } = await supabase
      .from('product_variants')
      .select(`
        id, price, sale_price, images,
        products (
          id, name, images,
          shops ( id, name )
        )
      `)
      .eq('id', variantId)
      .eq('is_active', true)
      .single();

    // Fallback: variantId có thể là productId (sản phẩm không có variant)
    if (error || !variant) {
      // Thử tìm variant đầu tiên của product
      const { data: firstVariant } = await supabase
        .from('product_variants')
        .select(`
          id, price, sale_price, images,
          products (
            id, name, images,
            shops ( id, name )
          )
        `)
        .eq('product_id', variantId)
        .eq('is_active', true)
        .limit(1)
        .maybeSingle();

      if (!firstVariant) {
        return res.status(404).json({ error: 'Variant not found or inactive' });
      }
      variant = firstVariant;
    }

    // Lấy attributes của variant từ variant_detail view
    const { data: detail } = await supabase
      .from('variant_detail')
      .select('attributes')
      .eq('id', variant.id)
      .maybeSingle();

    const product = variant.products;
    const shop    = product.shops;

    // Ảnh: variant.images[0] → product.images[0] → null
    const imageUrl = (variant.images?.[0]) || (product.images?.[0]) || null;

    const item = await repo.upsertItem(req.user.id, {
      variantId:     variant.id,
      productId:     product.id,
      productName:   product.name,
      shopId:        shop.id,
      shopName:      shop.name,
      imageUrl,
      attributes:    detail?.attributes ?? [],
      unitPrice:     variant.sale_price ?? variant.price,
      originalPrice: variant.price,
      quantity,
    });

    res.status(201).json(item);
  } catch (e) { next(e); }
}

const updateQtySchema = z.object({ quantity: z.number().int().min(1).max(999) });

async function updateQuantity(req, res, next) {
  try {
    const { quantity } = updateQtySchema.parse(req.body);
    const item = await repo.updateQuantity(req.user.id, req.params.id, quantity);
    res.json(item);
  } catch (e) { next(e); }
}

async function updateSelected(req, res, next) {
  try {
    const { is_selected } = z.object({ is_selected: z.boolean() }).parse(req.body);
    const item = await repo.updateSelected(req.user.id, req.params.id, is_selected);
    res.json(item);
  } catch (e) { next(e); }
}

async function selectAll(req, res, next) {
  try {
    const { is_selected } = z.object({ is_selected: z.boolean() }).parse(req.body);
    await repo.selectAll(req.user.id, is_selected);
    res.json({ ok: true });
  } catch (e) { next(e); }
}

async function removeItem(req, res, next) {
  try {
    await repo.removeItem(req.user.id, req.params.id);
    res.json({ ok: true });
  } catch (e) { next(e); }
}

async function removeSelected(req, res, next) {
  try {
    await repo.removeSelected(req.user.id);
    res.json({ ok: true });
  } catch (e) { next(e); }
}

const addFromLiveSchema = z.object({
  liveProductId: z.string().uuid(),
  sessionId:     z.string().uuid(),
  quantity:      z.number().int().min(1).max(999).default(1),
});

// Thêm vào giỏ từ live — dùng snapshot của live_session_products
async function addItemFromLive(req, res, next) {
  try {
    const { liveProductId, sessionId, quantity } = addFromLiveSchema.parse(req.body);

    // Lấy thông tin sản phẩm từ live_session_products
    const { data: lp, error } = await supabase
      .from('live_session_products')
      .select('*, live_sessions(seller_id, profiles:seller_id(shop_name))')
      .eq('id', liveProductId)
      .eq('session_id', sessionId)
      .single();

    if (error || !lp) {
      return res.status(404).json({ error: 'Live product not found' });
    }

    const shopName  = lp.live_sessions?.profiles?.shop_name ?? 'Shop';
    const sellerId  = lp.live_sessions?.seller_id;

    // Lấy shops.id từ seller_id để đồng bộ với cart items thông thường
    let shopId = sellerId;
    if (sellerId) {
      const { data: shopRow } = await supabase
        .from('shops').select('id').eq('seller_id', sellerId).maybeSingle();
      if (shopRow) shopId = shopRow.id;
    }

    const item = await repo.upsertItem(req.user.id, {
      variantId:     liveProductId,   // dùng liveProductId làm variantId (unique per user+product)
      productId:     liveProductId,
      productName:   lp.product_name,
      shopId,
      shopName,
      imageUrl:      lp.image_url || null,
      attributes:    [],
      unitPrice:     lp.sale_price,
      originalPrice: lp.original_price,
      quantity,
    });

    res.status(201).json(item);
  } catch (e) { next(e); }
}

module.exports = {
  getCart,
  addItem,
  addItemFromLive,
  updateQuantity,
  updateSelected,
  selectAll,
  removeItem,
  removeSelected,
};
