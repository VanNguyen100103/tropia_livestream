# SQL – Hướng dẫn chạy

Chạy tất cả trong **Supabase Dashboard → SQL Editor**.

---

## Setup từ đầu (fresh database)

Chạy theo thứ tự:

```
ddl/01_core.sql          → Tạo bảng core (profiles, live_sessions, orders...)
ddl/02_marketplace.sql   → Tạo bảng marketplace (categories, shops, products, variants)
ddl/03_attributes.sql    → Tạo bảng attributes + view variant_detail
ddl/04_cart_follows.sql  → Tạo bảng cart_items, shop_follows
ddl/05_coupons.sql       → Tạo bảng coupons, coupon_usages

rls/01_core_rls.sql      → RLS cho core tables
rls/02_marketplace_rls.sql → RLS cho marketplace tables
rls/03_coupons_rls.sql   → RLS cho coupons

rpc/01_triggers.sql      → Triggers tự động (updated_at, viewer_count, stats...)
rpc/02_functions.sql     → Atomic increment functions

seed/01_categories.sql   → Seed 10 categories + attribute types
seed/02_auto_shop.sql    → Tự động tạo shop cho seller (chạy sau khi có seller account)
seed/03_products.sql     → Seed 10 sản phẩm mẫu
seed/04_coupons.sql      → Seed 9 coupon mẫu
```

---

## Cập nhật database đang chạy (existing database)

Chỉ chạy các file trong `alter/` theo thứ tự:

```
alter/01_live_orders_payment.sql   → Thêm cột payment, bỏ NOT NULL session_id/product_id
alter/02_variants_images.sql       → Đổi image_url → images[] (chỉ nếu chưa migrate)
alter/03_live_session_stats.sql    → Thêm cart_add_count, follow_count, product_id
alter/04_cart_live_support.sql     → Bỏ FK, fix shop_id
alter/05_chat_is_host.sql          → Thêm is_host vào chat_messages
```

---

## Phân loại

| Thư mục | Loại | Nội dung |
|---------|------|----------|
| `ddl/`  | DDL  | `CREATE TABLE` – tạo schema mới |
| `alter/`| DDL  | `ALTER TABLE` – sửa bảng đã tồn tại |
| `rls/`  | DCL  | Row Level Security policies |
| `rpc/`  | DDL  | Functions, Triggers |
| `seed/` | DML  | `INSERT` dữ liệu mẫu |

---

## Thư mục `src/migrations/` (legacy)

Các file số `000`–`020` là lịch sử migration theo thứ tự thời gian. **Không xóa** — dùng để tra cứu khi cần.
Nội dung đã được tổ chức lại vào các thư mục trên.
