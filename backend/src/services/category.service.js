'use strict';

const { invalidatePattern } = require('../lib/redis');
const { NotFoundError, ConflictError } = require('../errors/AppError');
const repo = require('../repositories/category.repository');

async function listCategories() {
  return repo.listCategories();
}

async function getCategoryBySlug(slug) {
  const data = await repo.findCategoryBySlug(slug);
  if (!data) throw new NotFoundError('Category not found');
  return data;
}

async function createCategory(body) {
  if (await repo.slugExists(body.slug)) throw new ConflictError('Slug đã tồn tại');
  const data = await repo.createCategory(body);
  await invalidatePattern('categories:*');
  return data;
}

async function updateCategory(id, body) {
  const data = await repo.updateCategory(id, body);
  if (!data) throw new NotFoundError('Category not found');
  await invalidatePattern('categories:*');
  return data;
}

async function deleteCategory(id) {
  const count = await repo.countProductsByCategory(id);
  if (count > 0) throw new ConflictError(`Còn ${count} sản phẩm đang dùng danh mục này`);
  await repo.deleteCategory(id);
  await invalidatePattern('categories:*');
}

module.exports = { listCategories, getCategoryBySlug, createCategory, updateCategory, deleteCategory };
