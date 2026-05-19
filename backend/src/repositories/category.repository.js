'use strict';

const supabase = require('../lib/supabase');

async function listCategories() {
  const { data, error } = await supabase
    .from('categories')
    .select('id, name, slug, parent_id, image_url, sort_order, is_active')
    .order('sort_order', { ascending: true });
  if (error) throw error;
  return data;
}

async function findCategoryBySlug(slug) {
  const { data, error } = await supabase
    .from('categories')
    .select('*, products(count)')
    .eq('slug', slug)
    .single();
  if (error || !data) return null;
  return data;
}

async function slugExists(slug) {
  const { data } = await supabase
    .from('categories').select('id').eq('slug', slug).maybeSingle();
  return !!data;
}

async function createCategory(body) {
  const { data, error } = await supabase
    .from('categories').insert(body).select().single();
  if (error) throw error;
  return data;
}

async function updateCategory(id, body) {
  const { data, error } = await supabase
    .from('categories').update(body).eq('id', id).select().single();
  if (error || !data) return null;
  return data;
}

async function countProductsByCategory(categoryId) {
  const { count } = await supabase
    .from('products')
    .select('*', { count: 'exact', head: true })
    .eq('category_id', categoryId)
    .neq('status', 'deleted');
  return count || 0;
}

async function deleteCategory(id) {
  const { error } = await supabase.from('categories').delete().eq('id', id);
  if (error) throw error;
}

module.exports = {
  listCategories,
  findCategoryBySlug,
  slugExists,
  createCategory,
  updateCategory,
  countProductsByCategory,
  deleteCategory,
};
