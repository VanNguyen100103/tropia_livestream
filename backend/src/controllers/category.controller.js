'use strict';

const { z }  = require('zod');
const svc    = require('../services/category.service');
const { cacheAside } = require('../lib/redis');

const categorySchema = z.object({
  name:       z.string().min(1).max(100),
  slug:       z.string().min(1).max(100).regex(/^[a-z0-9-]+$/, 'slug chỉ gồm a-z, 0-9, dấu gạch ngang'),
  parent_id:  z.string().uuid().nullable().optional(),
  image_url:  z.string().url().nullable().optional(),
  sort_order: z.number().int().min(0).optional(),
  is_active:  z.boolean().optional(),
});

async function listCategories(req, res, next) {
  try {
    const data = await cacheAside('categories:all', () => svc.listCategories(), 300);
    res.json(data);
  } catch (e) { next(e); }
}

async function getCategoryBySlug(req, res, next) {
  try {
    const data = await svc.getCategoryBySlug(req.params.slug);
    res.json(data);
  } catch (e) { next(e); }
}

async function createCategory(req, res, next) {
  try {
    const body = categorySchema.parse(req.body);
    const data = await svc.createCategory(body);
    res.status(201).json(data);
  } catch (e) { next(e); }
}

async function updateCategory(req, res, next) {
  try {
    const body = categorySchema.partial().parse(req.body);
    const data = await svc.updateCategory(req.params.id, body);
    res.json(data);
  } catch (e) { next(e); }
}

async function deleteCategory(req, res, next) {
  try {
    await svc.deleteCategory(req.params.id);
    res.status(204).send();
  } catch (e) { next(e); }
}

module.exports = { listCategories, getCategoryBySlug, createCategory, updateCategory, deleteCategory };
