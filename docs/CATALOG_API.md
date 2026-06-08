# Catalog API — Tài liệu Mobile App

Tài liệu chính thức cho dev làm phần **duyệt mua**: cửa hàng (Shop), danh mục
(Category), sản phẩm (Product) và **Flash sale**. Đây là lớp dữ liệu cho Trang
chủ, tab Khám phá, trang Shop, chi tiết sản phẩm và trang Flash sale. Backend =
**Go** (`/api/shops`, `/api/categories`, `/api/products`, `/api/flash-sales`).
Cùng envelope với [LIVESTREAM_API.md](LIVESTREAM_API.md) §1.

---

## 1. Base URL & Envelope

**Dev:**

```
{BACKEND_URL}/api/{endpoint}      # BACKEND_URL = http://localhost:3000
```

**Content-Type:** `application/json`.

### Envelope chuẩn (mọi API)

```json
{
  "Result": true,
  "StatusCode": "200",
  "StatusMess": "Success",
  "status": 200,
  "message": "Success",
  "data": {}
}
```

| Field | Kiểu | Mô tả |
|-------|------|--------|
| `Result` | boolean | `true` = thành công |
| `StatusCode` | string | `"200"`, `"401"`, `"403"`, `"404"`, `"409"`, `"422"`, `"500"` |
| `StatusMess` | string | Message hiển thị (Việt/Anh tuỳ endpoint) |
| `status` | number | HTTP status số |
| `message` | string | Trùng `StatusMess` |
| `data` | object \| array \| null | Payload (`null` khi lỗi) |

**Lỗi ví dụ:**

```json
{
  "Result": false,
  "StatusCode": "404",
  "StatusMess": "product not found",
  "status": 404,
  "message": "product not found",
  "data": null
}
```

> **Mã lỗi hay gặp:** `422` = id/body sai định dạng (`invalid id`, validation
> binding); `401` = thiếu/sai token (`unauthenticated`); `403` = sai quyền
> (`forbidden`, `not your shop`, `not your product`); `404` = không tồn tại;
> `409` = trùng/ràng buộc (slug đã dùng, danh mục còn sản phẩm).

---

## 2. Xác thực (JWT User)

Các API **ghi** (follow, tạo/sửa shop, đăng sản phẩm, quản trị danh mục/flash
sale) yêu cầu header:

```http
Authorization: Bearer {access_token}
```

Token lấy như livestream — `POST /api/login` (alias spec) hoặc
`POST /api/auth/login`. Xem [LIVESTREAM_API.md](LIVESTREAM_API.md) §2.

**API đọc công khai** (list/detail shop, danh mục, browse/detail sản phẩm,
flash-sale đang chạy) **không bắt buộc** token. Riêng `GET /api/shops/:slug` là
**optional-auth**: gắn token thì server điền thêm cờ `is_following`.

---

## 3. Phân quyền

| Lớp | Ai | Endpoint |
|-----|-----|----------|
| Public | Bất kỳ | Đọc shop / danh mục / sản phẩm / flash-sale đang chạy |
| JWT (user) | Đã đăng nhập | Follow shop, `me/info`, `me/following`, follow-status |
| Seller | `role = seller` **hoặc** `admin` | Tạo/sửa shop của mình, đăng & quản lý sản phẩm |
| Admin | `role = admin` | CRUD danh mục, CRUD flash sale |

Thiếu token ở route cần JWT → **401** `unauthenticated`. Sai vai trò → **403**
`forbidden`:

```json
{ "Result": false, "StatusCode": "403", "StatusMess": "forbidden", "status": 403, "message": "forbidden", "data": null }
```

> "Seller" ở đây = tài khoản đã có shop. Một seller **chưa tạo shop** vẫn đăng
> nhập bình thường nhưng `me/info` trả `shop: null` và `quick-create` báo
> `403 seller has no shop`.

---

## 4. Luồng tổng thể (Mobile)

```
[Người mua]
  GET categories                       → chip danh mục (Trang chủ)
  GET flash-sales/active               → dải "Flash sale" + countdown
  GET products?category=&sort=&search= → lưới sản phẩm (filter/sort/paginate)
       → GET products/:slug            → chi tiết SP (ảnh, giá, đã bán, rating)
       → GET products/attributes       → picker biến thể (màu/size/...)
  GET shops/:slug                      → trang Shop (+ is_following nếu có token)
       → GET products/shop/:shopId     → sản phẩm của shop
       → POST/DELETE shops/:slug/follow→ theo dõi / bỏ theo dõi shop
  GET shops/me/following               → tab "Đang theo dõi"

[Seller] (role seller / admin, đã có shop)
  GET shops/me/info                    → shop của mình (null nếu chưa tạo)
  POST shops                           → tạo shop (lần đầu)
  POST products/quick-create           → đăng nhanh 1 sản phẩm
  GET products/seller/list             → quản lý sản phẩm của mình
  PATCH products/:id/status            → bật/tắt bán · DELETE products/:id → gỡ

[Admin]
  POST/PATCH/DELETE categories         → quản trị cây danh mục
  POST/PATCH/DELETE flash-sales        → lên lịch & gắn sản phẩm flash sale
```

---

## 5. Bảng endpoint nhanh

| # | Method | Endpoint | Auth | Màn app |
|---|--------|----------|------|---------|
| 1 | GET | `shops` | — | DS shop (top theo doanh số) |
| 2 | GET | `shops/:slug` | opt | Trang Shop (+ `is_following`) |
| 3 | GET | `shops/me/info` | JWT | Shop của tôi |
| 4 | GET | `shops/me/following` | JWT | Tab "Đang theo dõi" |
| 5 | GET | `shops/:slug/follow-status` | JWT | Trạng thái follow |
| 6 | POST | `shops/:slug/follow` | JWT | Theo dõi shop |
| 7 | DELETE | `shops/:slug/follow` | JWT | Bỏ theo dõi |
| 8 | POST | `shops` | seller | Tạo shop |
| 9 | PATCH | `shops/:slug` | seller | Sửa shop |
| 10 | GET | `categories` | — | Danh mục (cache 5') |
| 11 | GET | `categories/:slug` | — | Chi tiết danh mục |
| 12 | POST | `categories` | admin | Tạo danh mục |
| 13 | PATCH | `categories/:id` | admin | Sửa danh mục |
| 14 | DELETE | `categories/:id` | admin | Xoá danh mục |
| 15 | GET | `products` | — | Browse (filter/sort/paginate) |
| 16 | GET | `products/attributes` | — | Picker biến thể |
| 17 | GET | `products/shop/:shopId` | — | SP theo shop |
| 18 | GET | `products/seller/list` | seller | SP của tôi |
| 19 | POST | `products/quick-create` | seller | Đăng nhanh SP |
| 20 | PATCH | `products/:id/status` | seller | Đổi trạng thái SP |
| 21 | DELETE | `products/:id` | seller | Gỡ SP (soft delete) |
| 22 | GET | `products/:slug` | — | Chi tiết SP |
| 23 | GET | `flash-sales/active` | — | Flash sale đang chạy |
| 24 | GET | `flash-sales` | admin | Tất cả flash sale |
| 25 | POST | `flash-sales` | admin | Tạo flash sale |
| 26 | GET | `flash-sales/:id` | admin | Chi tiết flash sale |
| 27 | PATCH | `flash-sales/:id` | admin | Sửa flash sale |
| 28 | DELETE | `flash-sales/:id` | admin | Xoá flash sale |
| 29 | PUT | `flash-sales/:id/products` | admin | Thay toàn bộ SP trong sale |
| 30 | DELETE | `flash-sales/:id/products/:productId` | admin | Gỡ 1 SP khỏi sale |

`opt` = không bắt buộc token, nhưng gắn để điền cờ viewer. Phân trang sản phẩm
dùng `?page=&limit=` (mặc định `limit=20`, tối đa `100`).

---

## 6. API Shop

Object **Shop** — xem §10.1.

### 6.1 `GET /api/shops`

DS shop `is_active`, xếp theo `total_sales` giảm dần (top 50).

| | |
|--|--|
| **Auth** | Không |
| **Query** | Không (cố định 50 shop đầu — chưa phân trang) |

**Response `data`:**

```json
{
  "shops": [
    {
      "id": "cc33dd44-0000-0000-0000-000000000001",
      "seller_id": "9a1b2c3d-0000-0000-0000-000000000012",
      "name": "Nông sản Đà Lạt",
      "slug": "nong-san-da-lat",
      "description": "Rau củ quả sạch Đà Lạt",
      "logo_url": "https://r2.tropia.vn/logos/shop1.jpg",
      "banner_url": null,
      "rating": 4.8,
      "total_sales": 1280,
      "follower_count": 340,
      "is_active": true,
      "created_at": "2026-05-01T09:00:00Z"
    }
  ]
}
```

---

### 6.2 `GET /api/shops/:slug`

Chi tiết 1 shop. `:slug` nhận **slug**, **shop UUID**, hoặc **seller UUID**
(linh hoạt — mirror Node.js cũ).

| | |
|--|--|
| **Auth** | Không (gắn token → thêm `is_following`) |

**Response `data` (có token):**

```json
{
  "shop": { "...": "object Shop như §6.1" },
  "is_following": false
}
```

Không gắn token → chỉ có `shop` (không có `is_following`).

**Lỗi 404:**

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "shop not found", "status": 404, "message": "shop not found", "data": null }
```

---

### 6.3 `GET /api/shops/me/info` (JWT)

Shop của chính người đăng nhập.

**Có shop — `data`:** `{ "shop": { … object Shop } }`.

**Chưa tạo shop (vẫn `200`):**

```json
{ "Result": true, "StatusCode": "200", "StatusMess": "Success", "status": 200, "message": "Success", "data": { "shop": null } }
```

---

### 6.4 `GET /api/shops/me/following` (JWT)

Các shop user đang theo dõi (mới-follow-trước).

| | |
|--|--|
| **Query** | `limit` (default 50, max 200), `offset` (default 0) |

**Response `data` — lưu ý shape khác (`data` + `count`, KHÔNG phải `shops`):**

```json
{
  "data": [ { "...": "object Shop như §6.1" } ],
  "count": 1
}
```

> Endpoint này trả `data` (mảng shop) + `count`. App parse `data` là `List`,
> không phải `{ "shops": [...] }` như §6.1. Rỗng → `{ "data": [], "count": 0 }`.

---

### 6.5 Follow / Unfollow shop (JWT)

| Endpoint | `data` |
|----------|--------|
| `GET /api/shops/:slug/follow-status` | `{ "followed": true }` |
| `POST /api/shops/:slug/follow` | `{ "followed": true }` |
| `DELETE /api/shops/:slug/follow` | `{ "followed": false }` |

Follow idempotent (bấm lại không tăng đôi). `:slug` chấp nhận slug/UUID như §6.2.

**Lỗi 404:** `shop not found` (cả 3 route khi shop không tồn tại).

---

### 6.6 `POST /api/shops` — tạo shop (seller)

| | |
|--|--|
| **Auth** | Bearer JWT + role seller/admin |

**Request:**

```json
{
  "name": "Nông sản Đà Lạt",
  "slug": "nong-san-da-lat",
  "description": "Rau củ quả sạch Đà Lạt"
}
```

| Field | Kiểu | Bắt buộc | Ràng buộc |
|-------|------|----------|-----------|
| `name` | string | Có | 1–200 ký tự |
| `slug` | string | Không | ≤ 200; bỏ trống → tự sinh `slugify(name)-{seller8}` |
| `description` | string | Không | |

Shop mới được gán **logo mặc định** dạng ui-avatars (chữ cái đầu của tên) nên
card/clip có avatar ngay.

**Response `data` (201):** `{ "shop": { … object Shop } }`.

**Lỗi 409 (slug/shop trùng):**

```json
{ "Result": false, "StatusCode": "409", "StatusMess": "shop already exists or slug taken", "status": 409, "message": "...", "data": null }
```

---

### 6.7 `PATCH /api/shops/:slug` — sửa shop (seller)

Chỉ **chủ shop** (hoặc admin) sửa được.

**Request (field bỏ trống = giữ nguyên):**

```json
{ "name": "Nông sản Đà Lạt Premium", "description": "Đặc sản cao nguyên" }
```

**Response `data`:** `{ "shop": { … object Shop } }`.

**Lỗi:**

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "shop not found", "status": 404, "message": "shop not found", "data": null }
```

```json
{ "Result": false, "StatusCode": "403", "StatusMess": "not your shop", "status": 403, "message": "not your shop", "data": null }
```

---

## 7. API Danh mục (Category)

Object **Category** — xem §10.2.

### 7.1 `GET /api/categories`

Toàn bộ danh mục `is_active`, xếp `sort_order` rồi `name`. **Cache 5 phút.**

| | |
|--|--|
| **Auth** | Không |

**Response `data`:**

```json
{
  "categories": [
    {
      "id": "11112222-0000-0000-0000-000000000001",
      "name": "Rau củ",
      "slug": "rau-cu",
      "parent_id": null,
      "image_url": "https://r2.tropia.vn/cats/raucu.jpg",
      "sort_order": 0,
      "is_active": true,
      "created_at": "2026-05-01T09:00:00Z"
    }
  ]
}
```

`parent_id` ≠ `null` → danh mục con (app tự dựng cây theo `parent_id`).

---

### 7.2 `GET /api/categories/:slug`

Chi tiết 1 danh mục theo slug. **Response `data`:** `{ "category": { … } }`.

**Lỗi 404:** `category not found`.

---

### 7.3 CRUD danh mục (admin)

| Method | Endpoint | Body | `data` |
|--------|----------|------|--------|
| POST | `categories` | `name`(1–100, req), `slug`(1–100, req), `parent_id?`, `image_url?`, `sort_order?` | `{ "category": { … } }` (201) |
| PATCH | `categories/:id` | `name?`, `slug?`, `image_url?`, `sort_order?`, `is_active?` | `{ "category": { … } }` |
| DELETE | `categories/:id` | — | `204` |

`:id` = UUID danh mục (sai → `422 invalid id`). Tạo/sửa/xoá đều **xoá cache**
`categories:*`.

**Lỗi 409 khi xoá danh mục còn sản phẩm active:**

```json
{ "Result": false, "StatusCode": "409", "StatusMess": "category still in use by active products", "status": 409, "message": "...", "data": null }
```

---

## 8. API Sản phẩm (Product)

Object **Product** — xem §10.3.

### 8.1 `GET /api/products` — browse

Lưới sản phẩm `status = active`, hỗ trợ lọc + sắp xếp + phân trang.

| | |
|--|--|
| **Auth** | Không |

| Query | Kiểu | Default | Mô tả |
|-------|------|---------|--------|
| `category` | string | — | Lọc theo **slug** danh mục |
| `search` | string | — | Full-text (tên/mô tả) |
| `shop` | UUID | — | Lọc theo shop |
| `sort` | string | `total_sold` DESC | `price_asc` \| `price_desc` \| `newest` \| `rating` |
| `min_price` / `max_price` | int | — | Khoảng giá (theo `sale_price` nếu có, else `base_price`) |
| `page` | int | 1 | Trang |
| `limit` | int | 20 | Tối đa 100 |

**Request:**

```
GET /api/products?category=rau-cu&sort=price_asc&min_price=10000&page=1&limit=20
```

**Response `data`:**

```json
{
  "data": [
    {
      "id": "p0010000-0000-0000-0000-000000000001",
      "shop_id": "cc33dd44-0000-0000-0000-000000000001",
      "name": "Cà chua bi 500g",
      "slug": "ca-chua-bi-500g",
      "description": "Cà chua bi Đà Lạt",
      "images": ["https://r2.tropia.vn/products/ca.jpg"],
      "base_price": 35000,
      "sale_price": 25000,
      "unit": "hộp",
      "has_variants": false,
      "rating": 4.8,
      "review_count": 56,
      "total_sold": 320,
      "total_stock": 40,
      "status": "active",
      "created_at": "2026-05-10T08:00:00Z"
    }
  ],
  "pagination": { "page": 1, "limit": 20, "total": 137 }
}
```

> Giá flash sale **không** nằm ở đây — đọc qua [`flash-sales/active`](#91-get-apiflash-salesactive)
> hoặc field `flash_price` trên card video feed. `pagination` phản hồi đúng
> `page`/`limit` client gửi (bỏ trống → server dùng `page=1`, `limit=20`).

---

### 8.2 `GET /api/products/:slug` — chi tiết

| | |
|--|--|
| **Auth** | Không |
| **Param** | `:slug` = slug sản phẩm (không phải UUID) |

**Response `data`:** `{ "product": { … object Product } }`.

**Lỗi 404:** `product not found` (gồm cả sản phẩm đã `deleted`).

> **Lưu ý route order:** `/attributes`, `/shop/:shopId`, `/seller/list`,
> `/quick-create` được đăng ký **trước** `/:slug`, nên các path đó không bị
> hiểu nhầm là slug. Khi gọi `GET /api/products/{slug}`, đừng dùng các từ khoá
> trên làm slug.

---

### 8.3 `GET /api/products/attributes`

Toàn bộ trục biến thể (Màu, Size, Trọng lượng…) + giá trị — cho picker biến thể.

**Response `data`:**

```json
{
  "attribute_types": [
    {
      "id": "a1...",
      "name": "Trọng lượng",
      "sort_order": 0,
      "values": [
        { "id": "v1...", "value": "500g", "display_name": null, "color_hex": null, "sort_order": 0 },
        { "id": "v2...", "value": "1kg",  "display_name": null, "color_hex": null, "sort_order": 1 }
      ]
    }
  ]
}
```

---

### 8.4 `GET /api/products/shop/:shopId`

Sản phẩm `active` của 1 shop (trang Shop).

| | |
|--|--|
| **Auth** | Không |
| **Param** | `:shopId` = UUID shop (sai → `422 invalid shop id`) |
| **Query** | `page`, `limit` |

**Response `data`:** `{ "data": [ … Product ], "pagination": { … } }` (như §8.1).

---

### 8.5 `GET /api/products/seller/list` (seller)

Sản phẩm của chính seller (kho quản lý). Reuse browse với filter shop suy từ JWT.

| | |
|--|--|
| **Auth** | Bearer JWT + role seller/admin |
| **Query** | `status`, `page`, `limit` |

**Response `data`:** `{ "data": [ … ], "pagination": { … } }`. Seller **chưa có
shop** → trả rỗng `{ "data": [], "pagination": { "page": 1, "limit": 20, "total": 0 } }`
(không phải lỗi).

---

### 8.6 `POST /api/products/quick-create` (seller) — đăng nhanh

Tạo nhanh 1 sản phẩm đơn giản (tự tạo 1 default variant cho giỏ hàng).

**Request:**

```json
{
  "name": "Cà chua bi 500g",
  "description": "Cà chua bi Đà Lạt mới hái",
  "price": 25000,
  "stock": 40,
  "image_url": "https://r2.tropia.vn/products/ca.jpg"
}
```

| Field | Kiểu | Bắt buộc | Ràng buộc |
|-------|------|----------|-----------|
| `name` | string | Có | 1–200 ký tự |
| `price` | int | Có | ≥ 0 (VND) |
| `stock` | int | Không | ≥ 0 |
| `description` | string | Không | |
| `image_url` | string | Không | URL ảnh (1 ảnh) |

**Response `data` (201):** `{ "product": { … object Product } }`. Slug tự sinh.

**Lỗi 403 (seller chưa có shop):**

```json
{ "Result": false, "StatusCode": "403", "StatusMess": "seller has no shop", "status": 403, "message": "seller has no shop", "data": null }
```

---

### 8.7 Đổi trạng thái / gỡ sản phẩm (seller)

Chỉ **chủ sản phẩm** (hoặc admin) thao tác được.

| Method | Endpoint | Body | Kết quả |
|--------|----------|------|---------|
| PATCH | `products/:id/status` | `{ "status": "active" }` — `draft\|active\|inactive` | `204` |
| DELETE | `products/:id` | — | `204` (soft delete → `status=deleted`) |

`:id` = UUID sản phẩm (sai → `422 invalid id`).

**Lỗi 403 (không phải SP của bạn):**

```json
{ "Result": false, "StatusCode": "403", "StatusMess": "not your product", "status": 403, "message": "not your product", "data": null }
```

---

## 9. API Flash sale

Flash sale là **giảm giá toàn sàn do admin lên lịch**. Trong khoảng
`starts_at ≤ now < ends_at` và `is_active`, các sản phẩm gắn kèm hiển thị
`flash_price` + countdown tới `ends_at` ở mọi nơi (card video feed, trang flash
sale). Object **FlashSale** / **FlashSaleProduct** — xem §10.4.

> **Quan trọng:** flash sale create/get/update/setProducts trả **thẳng object
> FlashSale** (không bọc trong key) → `data` chính là object đó. Còn list/active
> bọc trong `{ "flash_sales": [...] }`.

### 9.1 `GET /api/flash-sales/active`

Sale đang chạy ngay lúc gọi (xếp `ends_at` tăng dần — sắp hết trước). **Public.**

**Response `data`:**

```json
{
  "flash_sales": [
    {
      "id": "fs000000-0000-0000-0000-000000000001",
      "name": "Flash sale rau củ 14h",
      "starts_at": "2026-06-07T13:00:00Z",
      "ends_at": "2026-06-07T14:00:00Z",
      "is_active": true,
      "created_by": "ad000000-...",
      "created_at": "2026-06-07T08:00:00Z",
      "products": [
        {
          "product_id": "p0010000-0000-0000-0000-000000000001",
          "name": "Cà chua bi 500g",
          "slug": "ca-chua-bi-500g",
          "image_url": "https://r2.tropia.vn/products/ca.jpg",
          "base_price": 35000,
          "flash_price": 19000,
          "stock_limit": 100,
          "sold_count": 23,
          "sort_order": 0
        }
      ]
    }
  ]
}
```

`flash_price` = giá tuyệt đối (VND) trong khung giờ. `name`/`base_price`/`image`
đọc **live** từ `products`. `products` luôn là list (`[]` khi không có).

---

### 9.2 `GET /api/flash-sales` (admin)

Tất cả sale cho console admin.

| | |
|--|--|
| **Query** | `all=true` / `include_inactive=true` (kèm sale đã tắt), `limit` (default 50, max 100), `offset` |

**Response `data`:** `{ "flash_sales": [ … như §9.1 ] }` (newest first theo `starts_at`).

---

### 9.3 `POST /api/flash-sales` (admin) — tạo

**Request:**

```json
{
  "name": "Flash sale rau củ 14h",
  "starts_at": "2026-06-07T13:00:00Z",
  "ends_at": "2026-06-07T14:00:00Z",
  "products": [
    { "product_id": "p0010000-0000-0000-0000-000000000001", "flash_price": 19000, "stock_limit": 100 }
  ]
}
```

| Field | Kiểu | Bắt buộc | Ghi chú |
|-------|------|----------|---------|
| `name` | string | Có | 1–200 ký tự |
| `starts_at` / `ends_at` | RFC3339 | Có | `ends_at` phải **sau** `starts_at` |
| `products[].product_id` | UUID | Có | Id lạ/không `active`/trùng **bị bỏ qua, không báo lỗi** |
| `products[].flash_price` | int | — | ≥ 0 (VND) |
| `products[].stock_limit` | int | Không | ≥ 0; `null` = không giới hạn |

**Response `data` (201):** object **FlashSale** đầy đủ (như §9.1, một phần tử).

**Lỗi 422 (khung giờ sai):**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "thời gian kết thúc phải sau thời gian bắt đầu", "status": 422, "message": "...", "data": null }
```

---

### 9.4 Quản lý 1 flash sale (admin)

| Method | Endpoint | Body | `data` |
|--------|----------|------|--------|
| GET | `flash-sales/:id` | — | object FlashSale |
| PATCH | `flash-sales/:id` | `name?`, `starts_at?`, `ends_at?`, `is_active?` | object FlashSale (đã cập nhật) |
| DELETE | `flash-sales/:id` | — | `{ "ok": true }` |
| PUT | `flash-sales/:id/products` | `{ "products": [ … như §9.3 ] }` | object FlashSale (thay **toàn bộ** set SP) |
| DELETE | `flash-sales/:id/products/:productId` | — | `{ "ok": true }` |

`:id` / `:productId` = UUID (sai → `422 invalid id` / `invalid productId`).
PATCH khi sửa cả 2 mốc thời gian vẫn validate `ends_at` > `starts_at`.

**Lỗi 404:**

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "flash sale not found", "status": 404, "message": "flash sale not found", "data": null }
```

(DELETE product cũng trả `404 flash sale not found` khi sản phẩm không nằm trong sale.)

---

## 10. Object shapes

### 10.1 Shop

| Field | Kiểu | Mô tả |
|-------|------|--------|
| `id` | UUID | Id shop |
| `seller_id` | UUID | Chủ shop |
| `name` / `slug` | string | Tên / slug (slug dùng cho route `/:slug`) |
| `description` | string? | |
| `logo_url` / `banner_url` | string? | Logo (mặc định ui-avatars) / banner |
| `rating` | float | Điểm đánh giá |
| `total_sales` | int | Tổng đã bán (dùng để xếp `GET /shops`) |
| `follower_count` | int | Số người theo dõi |
| `is_active` | bool | Shop còn hoạt động |
| `created_at` | RFC3339 | |

### 10.2 Category

| Field | Kiểu | Mô tả |
|-------|------|--------|
| `id` | UUID | |
| `name` / `slug` | string | `slug` dùng cho `GET /:slug` và lọc `products?category=` |
| `parent_id` | UUID? | `null` = danh mục gốc |
| `image_url` | string? | Icon danh mục |
| `sort_order` | int | Thứ tự hiển thị |
| `is_active` | bool | |
| `created_at` | RFC3339 | |

### 10.3 Product

| Field | Kiểu | Mô tả |
|-------|------|--------|
| `id` | UUID | Id sản phẩm (dùng `status`/`delete`/flash-sale) |
| `shop_id` | UUID | Shop sở hữu |
| `name` / `slug` | string | `slug` dùng cho `GET /products/:slug` |
| `description` | string? | |
| `images` | string[] | Danh sách ảnh (`[]` nếu chưa có) |
| `base_price` | int | Giá gốc (VND) |
| `sale_price` | int? | Giá KM thường (`null` = không giảm) |
| `unit` | string | Đơn vị (hộp, kg…) |
| `has_variants` | bool | Có biến thể? (true → lấy picker từ `/attributes`) |
| `rating` / `review_count` | float/int | |
| `total_sold` / `total_stock` | int | Đã bán / tồn kho |
| `status` | string | `active` (browse chỉ trả `active`) · `draft` · `inactive` · `deleted` |
| `created_at` | RFC3339 | |

### 10.4 FlashSale / FlashSaleProduct

**FlashSale:** `id`, `name`, `starts_at`, `ends_at` (RFC3339), `is_active`,
`created_by` (UUID), `created_at`, `products` (FlashSaleProduct[], luôn list).

**FlashSaleProduct:**

| Field | Kiểu | Mô tả |
|-------|------|--------|
| `product_id` | UUID | Điều hướng sang product detail |
| `name` / `slug` | string | Đọc live từ `products` |
| `image_url` | string? | Ảnh đầu tiên của sản phẩm |
| `base_price` | int | Giá gốc (để gạch ngang) |
| `flash_price` | int | Giá flash (VND) trong khung giờ |
| `stock_limit` | int? | Giới hạn suất (`null` = không giới hạn) |
| `sold_count` | int | Đã bán trong sale → countdown/khan hiếm |
| `sort_order` | int | Thứ tự hiển thị |

---

## 11. Checklist tích hợp dev

- [ ] Trang chủ: `GET categories` (cache client) + `GET flash-sales/active`
- [ ] Lưới SP: `GET products` với `category`/`sort`/`search`/`page`/`limit`
- [ ] Chi tiết SP: `GET products/:slug`; nếu `has_variants` → `GET products/attributes`
- [ ] Trang Shop: `GET shops/:slug` (+token để có `is_following`) → `GET products/shop/:shopId`
- [ ] Follow: `POST/DELETE shops/:slug/follow`; tab theo dõi đọc `me/following` (`data`+`count`)
- [ ] Seller: `GET shops/me/info` → `POST shops` (nếu null) → `quick-create` / `seller/list`
- [ ] Flash sale card: đọc `flash_price`/`ends_at` → countdown; hết giờ → ẩn
- [ ] Xử lý envelope `Result === false` + hiển thị `StatusMess`
- [ ] Nhớ shape khác nhau: `shops` vs `data`+`count` (me/following) vs `data`+`pagination` (products) vs `flash_sales`

---

## 12. Mapping Catalog ↔ các doc khác

| Chủ đề | Doc tham chiếu |
|--------|----------------|
| Áp voucher shop/sàn ở checkout | [COUPON_API.md](COUPON_API.md) |
| Sản phẩm gắn trong clip video | [VIDEO_FEED_API.md](VIDEO_FEED_API.md) (`product_ids`, card đọc `flash_price`) |
| Sản phẩm gắn trong phiên live | [LIVESTREAM_API.md](LIVESTREAM_API.md) §B4 (`/streams/:id/products`) |
| Quyền seller/admin, đăng nhập | [LIVESTREAM_API.md](LIVESTREAM_API.md) §2, [ROLES.md](ROLES.md) |

---

## 13. Tham chiếu code

| Chủ đề | File |
|--------|------|
| Route + mount | `cmd/api/main.go` (`shopH/catH/prodH/flashSaleH.Register`) |
| Shop handler + repo | `internal/shops/shops.go` |
| Category handler + repo | `internal/catalog/categories.go` |
| Product handler + repo | `internal/catalog/products.go` |
| Flash sale | `internal/flashsale/handler.go`, `repo.go`, `model.go` |
| Phân quyền (seller/admin) | `internal/auth/middleware.go` (`RequireRole`) |
| Envelope | `internal/httpx/envelope.go` |
| OpenAPI | `backend/docs/openapi.yaml` |
