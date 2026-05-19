'use strict';

const supabase = require('../lib/supabase');

async function getCart(userId) {
  const { data, error } = await supabase
    .from('cart_items')
    .select('*')
    .eq('user_id', userId)
    .order('added_at', { ascending: false });
  if (error) throw error;
  return data;
}

// Thêm vào giỏ — nếu variant đã có thì tăng qty
async function upsertItem(userId, {
  variantId, productId, productName,
  shopId, shopName, imageUrl, attributes,
  unitPrice, originalPrice, quantity = 1,
}) {
  // Kiểm tra đã có chưa
  const { data: existing } = await supabase
    .from('cart_items')
    .select('id, quantity')
    .eq('user_id', userId)
    .eq('variant_id', variantId)
    .maybeSingle();

  if (existing) {
    const newQty = existing.quantity + quantity;
    const { data, error } = await supabase
      .from('cart_items')
      .update({ quantity: newQty, unit_price: unitPrice, original_price: originalPrice })
      .eq('id', existing.id)
      .select()
      .single();
    if (error) throw error;
    return data;
  }

  const { data, error } = await supabase
    .from('cart_items')
    .insert({
      user_id:        userId,
      variant_id:     variantId,
      product_id:     productId,
      product_name:   productName,
      shop_id:        shopId,
      shop_name:      shopName,
      image_url:      imageUrl,
      attributes:     attributes,
      unit_price:     unitPrice,
      original_price: originalPrice,
      quantity,
    })
    .select()
    .single();
  if (error) throw error;
  return data;
}

async function updateQuantity(userId, itemId, quantity) {
  const { data, error } = await supabase
    .from('cart_items')
    .update({ quantity })
    .eq('id', itemId)
    .eq('user_id', userId)  // đảm bảo chỉ sửa của chính mình
    .select()
    .single();
  if (error) throw error;
  return data;
}

async function updateSelected(userId, itemId, isSelected) {
  const { data, error } = await supabase
    .from('cart_items')
    .update({ is_selected: isSelected })
    .eq('id', itemId)
    .eq('user_id', userId)
    .select()
    .single();
  if (error) throw error;
  return data;
}

async function selectAll(userId, isSelected) {
  const { error } = await supabase
    .from('cart_items')
    .update({ is_selected: isSelected })
    .eq('user_id', userId);
  if (error) throw error;
}

async function removeItem(userId, itemId) {
  const { error } = await supabase
    .from('cart_items')
    .delete()
    .eq('id', itemId)
    .eq('user_id', userId);
  if (error) throw error;
}

async function removeSelected(userId) {
  const { error } = await supabase
    .from('cart_items')
    .delete()
    .eq('user_id', userId)
    .eq('is_selected', true);
  if (error) throw error;
}

async function clearCart(userId) {
  const { error } = await supabase
    .from('cart_items')
    .delete()
    .eq('user_id', userId);
  if (error) throw error;
}

module.exports = {
  getCart,
  upsertItem,
  updateQuantity,
  updateSelected,
  selectAll,
  removeItem,
  removeSelected,
  clearCart,
};
