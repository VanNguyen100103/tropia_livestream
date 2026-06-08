# Cart API — Tài liệu Mobile App

Tài liệu chính thức cho dev làm màn **Giỏ hàng** (thêm / sửa số lượng /
chọn / xoá) và bước **đi tới Checkout**. Cùng hệ thống envelope với
[LIVESTREAM_API.md](LIVESTREAM_API.md) (Phần B — Go backend).

---

## 1. Base URL & Envelope

Base = `{BACKEND_URL}` (dev `http://localhost:3000`, prod `https://api.tropia.vn`).

```
{BACKEND_URL}/api/cart
```

**Content-Type:** `application/json` (POST / PATCH body).

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
| `Result` | boolean | `true` = thành công (HTTP 2xx/3xx) |
| `StatusCode` | string | `"200"`, `"201"`, `"204"`, `"401"`, `"404"`, `"422"`, `"500"` |
| `StatusMess` | string | Message (VN cho lỗi nghiệp vụ, EN cho lỗi validate) |
| `status` | number | HTTP status số |
| `message` | string | Trùng `StatusMess` |
| `data` | object \| array \| null | Payload (`null` khi lỗi hoặc `204`) |

**Lỗi ví dụ:**

```json
{
  "Result": false,
  "StatusCode": "404",
  "StatusMess": "variant not found",
  "status": 404,
  "message": "variant not found",
  "data": null
}
```

> **Lưu ý mã lỗi:** lỗi validate input → **HTTP 422** (`invalid id`, hoặc
> message tiếng Anh kiểu `Key: 'addItemReq.Quantity' Error:...`). Không
> tìm thấy bản ghi → **404**. Chưa đăng nhập → **401**.

---

## 2. Xác thực (JWT)

**Toàn bộ** API giỏ hàng yêu cầu header:

```http
Authorization: Bearer {access_token}
```

Token lấy từ `POST /api/auth/login`. Giỏ hàng gắn với `user_id` trong JWT —
không cần truyền user id trong body.

**Lỗi 401 (thiếu / sai token):**

```json
{ "Result": false, "StatusCode": "401", "StatusMess": "missing Authorization header", "status": 401, "message": "missing Authorization header", "data": null }
```

---

## 3. Mô hình dữ liệu

### CartItem

```json
{
  "id": "c1a2b3c4-...",
  "user_id": "9a1b2c3d-...",
  "variant_id": "v0010000-...",
  "product_id": "p0010000-...",
  "product_name": "Cà chua bi 500g",
  "shop_id": "cc33dd44-...",
  "shop_name": "Nông sản Đà Lạt",
  "image_url": "https://cdn.tropia.vn/products/ca.jpg",
  "attributes": [],
  "unit_price": 25000,
  "original_price": 35000,
  "quantity": 2,
  "is_selected": true,
  "added_at": "2026-06-07T12:00:00Z"
}
```

| Field | Kiểu | Mô tả |
|-------|------|--------|
| `id` | uuid | ID dòng giỏ hàng — dùng cho `qty` / `select` / `delete` |
| `variant_id` | uuid | **Quá tải:** giữ `product_variants.id` (hàng thường) **hoặc** `live_session_products.id` (thêm từ live). Cùng `variant_id` → cộng dồn số lượng |
| `product_id` | uuid \| null | ID sản phẩm gốc (có thể `null` với hàng live ad-hoc → backend fallback = `live_product_id`) |
| `shop_id` / `shop_name` | uuid / string | Dùng để **gom nhóm theo shop** trên UI giỏ |
| `image_url` | string \| null | Ảnh sản phẩm |
| `attributes` | array | JSONB (phân loại/biến thể). Mặc định `[]` |
| `unit_price` | int (VND) | Giá thực trả mỗi đơn vị (đã áp sale / flash sale) |
| `original_price` | int (VND) | Giá gốc — dùng tính "tiết kiệm" |
| `quantity` | int | Số lượng (1–999) |
| `is_selected` | bool | Có được chọn để checkout không (mặc định `true` khi thêm) |

> **Giá:** khi thêm vào giỏ, backend tự lấy `sale_price` nếu có, và nếu sản
> phẩm đang trong **Flash Sale** đang chạy thì `unit_price` = giá flash
> (nếu thấp hơn). `original_price` luôn là giá gốc của variant. → dòng
> "tiết kiệm" = `(original_price − unit_price) × quantity`.

---

## 4. Luồng tổng thể (Mobile)

```
[Buyer]
  Login → lưu JWT
       → (Catalog) chọn variant → POST cart/items
       → (Live)    chọn sản phẩm trong phiên → POST cart/items/from-live
       → GET cart → render danh sách + summary (chỉ tính item is_selected)
       → PATCH items/:id/qty       (đổi số lượng)
       → PATCH items/:id/select    (tích/bỏ tích 1 dòng)
       → PATCH select-all          (chọn/bỏ chọn tất cả)
       → DELETE items/:id          (xoá 1 dòng)
       → DELETE items/selected     (xoá các dòng đã chọn)
       → [Checkout] POST /api/orders/checkout  (dùng các dòng is_selected)
            ├─ COD     → xoá selected items ngay, order 'confirmed'
            └─ Online  → giữ items đến khi gateway xác nhận (MarkPaid mới xoá)
```

Coupon áp ở bước checkout — validate riêng qua
`POST /api/coupons/validate` (xem [COUPON_API.md](COUPON_API.md)).

---

## 5. Bảng endpoint nhanh

| # | Method | Endpoint | Auth | Thành công | Mô tả |
|---|--------|----------|------|-----------|--------|
| 1 | GET | `/api/cart` | JWT | 200 | DS giỏ + summary |
| 2 | POST | `/api/cart/items` | JWT | 201 | Thêm theo `variant_id` |
| 3 | POST | `/api/cart/items/from-live` | JWT | 201 | Thêm từ sản phẩm live |
| 4 | PATCH | `/api/cart/items/:id/qty` | JWT | 200 | Đổi số lượng (trả full item) |
| 5 | PATCH | `/api/cart/items/:id/select` | JWT | 204 | Tích/bỏ tích 1 dòng |
| 6 | PATCH | `/api/cart/select-all` | JWT | 204 | Tích/bỏ tích tất cả |
| 7 | DELETE | `/api/cart/items/:id` | JWT | 204 | Xoá 1 dòng |
| 8 | DELETE | `/api/cart/items/selected` | JWT | 204 | Xoá các dòng đã chọn |
| 9 | POST | `/api/orders/checkout` | JWT | 201 | Đặt hàng từ giỏ (xem §11) |

> Thứ tự route quan trọng: `DELETE /items/selected` được đăng ký **trước**
> `DELETE /items/:id` nên `selected` không bị hiểu nhầm là `:id`.

---

## 6. `GET /api/cart` — danh sách giỏ + tổng tiền

| | |
|--|--|
| **Auth** | Bearer JWT |
| **Query** | Không |

**Response `data`:**

```json
{
  "items": [
    {
      "id": "c1a2b3c4-...",
      "user_id": "9a1b2c3d-...",
      "variant_id": "v0010000-...",
      "product_id": "p0010000-...",
      "product_name": "Cà chua bi 500g",
      "shop_id": "cc33dd44-...",
      "shop_name": "Nông sản Đà Lạt",
      "image_url": "https://cdn.tropia.vn/products/ca.jpg",
      "attributes": [],
      "unit_price": 25000,
      "original_price": 35000,
      "quantity": 2,
      "is_selected": true,
      "added_at": "2026-06-07T12:00:00Z"
    }
  ],
  "summary": {
    "total_items": 2,
    "total_price": 50000,
    "total_saving": 20000
  }
}
```

| Field summary | Mô tả |
|---------------|--------|
| `total_items` | Tổng **số lượng** của các dòng `is_selected = true` |
| `total_price` | `Σ unit_price × quantity` (chỉ dòng đã chọn) |
| `total_saving` | `Σ (original_price − unit_price) × quantity` (chỉ dòng đã chọn) |

- `items` sắp xếp **mới thêm trước** (`added_at` DESC).
- Summary **chỉ cộng dòng đã chọn** — dòng bỏ tích không vào tổng tiền.
- Giỏ rỗng → `items: []`, summary toàn `0`.

---

## 7. Thêm vào giỏ

### 7.1 `POST /api/cart/items` — thêm từ Catalog

| | |
|--|--|
| **Auth** | Bearer JWT |

**Request:**

```json
{
  "variant_id": "v0010000-0000-0000-0000-000000000001",
  "quantity": 2
}
```

| Field | Kiểu | Bắt buộc | Ràng buộc |
|-------|------|----------|-----------|
| `variant_id` | uuid | Có | Phải là variant `is_active = true` |
| `quantity` | int | Có | 1–999 |

**Response `data` (201):** đối tượng **CartItem** (xem §3). Nếu `variant_id`
đã có trong giỏ → cộng dồn `quantity`, set lại `is_selected = true`.

**Lỗi 404 (variant không tồn tại / ngừng bán):**

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "variant not found", "status": 404, "message": "variant not found", "data": null }
```

**Lỗi 422 (thiếu / sai field):**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "Key: 'addItemReq.Quantity' Error:Field validation for 'Quantity' failed on the 'min' tag", "status": 422, "message": "...", "data": null }
```

---

### 7.2 `POST /api/cart/items/from-live` — thêm từ phiên Live

Thêm sản phẩm đang bán trong một phiên livestream vào giỏ.

| | |
|--|--|
| **Auth** | Bearer JWT |

**Request:**

```json
{
  "live_product_id": "aa11bb22-...",
  "session_id": "2b1c4d5e-...",
  "quantity": 1
}
```

| Field | Kiểu | Bắt buộc | Ghi chú |
|-------|------|----------|---------|
| `live_product_id` | uuid | Có | = `live_session_products.id` (lấy từ `GET /api/live/streams/:id/products`) |
| `session_id` | uuid | Có | UUID phiên live |
| `quantity` | int | Có | 1–999 |

**Response `data` (201):** đối tượng **CartItem**. Lưu ý:
`variant_id` = `live_product_id`; `shop_id`/`shop_name` lấy từ shop của
seller phiên live; giá `unit_price`/`original_price` lấy từ
`live_session_products`.

**Lỗi 404 (sản phẩm live không tồn tại trong phiên):**

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "live product not found", "status": 404, "message": "live product not found", "data": null }
```

---

## 8. Sửa số lượng & chọn

### 8.1 `PATCH /api/cart/items/:id/qty` — đổi số lượng

`:id` = `CartItem.id`.

**Request:**

```json
{ "quantity": 5 }
```

| Field | Kiểu | Bắt buộc | Ràng buộc |
|-------|------|----------|-----------|
| `quantity` | int | Có | 1–999 |

**Response `data` (200):** đối tượng **CartItem** đã cập nhật (full row —
app reconcile state trong 1 round-trip, không cần GET lại giỏ).

**Lỗi 404 (dòng không thuộc user / không tồn tại):**

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "cart item not found", "status": 404, "message": "cart item not found", "data": null }
```

**Lỗi 422 (id sai định dạng UUID):**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "invalid id", "status": 422, "message": "invalid id", "data": null }
```

---

### 8.2 `PATCH /api/cart/items/:id/select` — tích / bỏ tích 1 dòng

**Request:**

```json
{ "is_selected": true }
```

**Thành công 204** (không body):

```json
{ "Result": true, "StatusCode": "204", "StatusMess": "Success", "status": 204, "message": "Success", "data": null }
```

> Idempotent: gọi với dòng không tồn tại vẫn trả `204` (UPDATE không khớp
> hàng nào, không lỗi). App tự refetch `GET /cart` để lấy summary mới.

---

### 8.3 `PATCH /api/cart/select-all` — chọn / bỏ chọn tất cả

**Request:**

```json
{ "is_selected": true }
```

**Thành công 204.** Đặt `is_selected` cho **toàn bộ** dòng của user.

---

## 9. Xoá

### 9.1 `DELETE /api/cart/items/:id` — xoá 1 dòng

`:id` = `CartItem.id`. **Thành công 204.** Idempotent (xoá dòng không tồn
tại vẫn `204`).

**Lỗi 422 (id sai UUID):**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "invalid id", "status": 422, "message": "invalid id", "data": null }
```

### 9.2 `DELETE /api/cart/items/selected` — xoá các dòng đã chọn

Xoá mọi dòng `is_selected = true` của user (dùng sau khi mua xong, hoặc
nút "xoá đã chọn"). **Thành công 204.**

---

## 10. Tổng kết hành vi quan trọng

| Hành vi | Chi tiết |
|---------|----------|
| Thêm trùng variant | Cộng dồn `quantity`, set `is_selected = true`, cập nhật `added_at` |
| Mặc định khi thêm | `is_selected = true` |
| Summary | **Chỉ** tính dòng `is_selected = true` |
| Flash Sale | `unit_price` = giá flash nếu đang chạy và thấp hơn sale_price |
| `variant_id` quá tải | Variant thường **hoặc** live_session_products.id |
| 204 vs 200 | `qty` trả **200 + full item**; `select`/`select-all`/`delete` trả **204** rỗng |
| Sở hữu | Mọi thao tác lọc theo `user_id` của JWT (không sửa được giỏ người khác) |

---

## 11. Bridge sang Checkout (`POST /api/orders/checkout`)

Checkout tiêu thụ các dòng **`is_selected = true`** trong giỏ. Chi tiết
đầy đủ xem **[ORDER_API.md](ORDER_API.md)**; tóm tắt:

| | |
|--|--|
| **Auth** | Bearer JWT |
| **Rate limit** | 20/phút/user |

**Request:**

```json
{
  "coupon_codes": ["SALE10", "SHOPABC5"],
  "payment_method": "cod",
  "shipping_name": "Nguyễn Văn A",
  "shipping_phone": "0901234567",
  "shipping_address": "123 Lê Lợi, Q1, TP.HCM"
}
```

| Field | Kiểu | Bắt buộc | Ghi chú |
|-------|------|----------|---------|
| `coupon_codes` | string[] | Không | Union voucher sàn + shop (validate từng mã, cộng giảm) |
| `coupon_code` | string | Không | Field cũ — 1 voucher (vẫn nhận, gộp vào `coupon_codes`) |
| `payment_method` | string | Không | `cod` (mặc định) \| `momo` \| `vnpay` \| `zalopay` |
| `shipping_*` | string | Không | Snapshot địa chỉ giao; bỏ trống = nhận tại cửa hàng |

**Response `data` (201):** `{ "order": { … Order } }`.

**Quan trọng — dọn giỏ:**

- `payment_method = "cod"` → đơn `confirmed` ngay, **xoá selected items** lập tức.
- Online (`momo`/`vnpay`/`zalopay`) → **giữ nguyên** giỏ đến khi gateway
  IPN xác nhận `paid` (lúc đó `MarkPaid` mới xoá các item đã chọn). Thanh
  toán huỷ/thất bại không làm mất giỏ.

**Lỗi 422 (chưa chọn dòng nào):**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "no items selected", "status": 422, "message": "no items selected", "data": null }
```

Lỗi coupon (hết hạn / quá lượt / dưới mức tối thiểu) → trả message từ
coupon validate (xem [COUPON_API.md](COUPON_API.md)); FE nhắc buyer gỡ
voucher thay vì âm thầm tính giá chưa giảm.

---

## 12. Checklist tích hợp dev

- [ ] Lưu JWT sau login; gắn `Authorization` cho mọi call `/api/cart`
- [ ] Thêm hàng thường: `POST cart/items` (`variant_id` + `quantity`)
- [ ] Thêm từ live: `POST cart/items/from-live` (`live_product_id` + `session_id`)
- [ ] Render giỏ từ `GET cart`; **gom nhóm theo `shop_id`/`shop_name`**
- [ ] Hiển thị summary từ `data.summary` (chỉ tính dòng đã chọn)
- [ ] Đổi số lượng: `PATCH items/:id/qty` → dùng item trả về cập nhật state
- [ ] Tích/bỏ tích: `select` / `select-all` → refetch `GET cart` lấy summary
- [ ] Xoá: `items/:id` hoặc `items/selected`
- [ ] Checkout: `POST /api/orders/checkout` với các dòng đã chọn
- [ ] Hiểu khác biệt dọn giỏ COD vs Online
- [ ] Xử lý envelope `Result === false` → hiển thị `StatusMess`

---

## 13. Tham chiếu

- Tài liệu liên quan: [LIVESTREAM_API.md](LIVESTREAM_API.md),
  [COUPON_API.md](COUPON_API.md), [ORDER_API.md](ORDER_API.md),
  [CATALOG_API.md](CATALOG_API.md)
- Quirk `cart_items.variant_id` (variant **hoặc** live_session_products):
  xem `backend/AUDIT.md`

## 14. Tham chiếu code (backend)

| Chủ đề | File |
|--------|------|
| Repo + handler giỏ | `internal/commerce/cart.go` |
| Checkout / order | `internal/commerce/orders.go` (`CheckoutCart`, `MarkPaid`) |
| Coupon | `internal/commerce/coupons.go`, `coupons_handler.go` |
| Route | `cmd/api/main.go` (`/api/cart`, `/api/orders`) |
| Envelope | `internal/httpx/envelope.go` |
| Lỗi / status | `internal/httpx/errors.go` |
| OpenAPI | `backend/docs/openapi.yaml` |
