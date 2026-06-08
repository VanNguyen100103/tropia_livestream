# Video Feed API — Tài liệu Mobile App

Tài liệu chính thức cho dev làm tab **Video** (feed dọc "Dành cho bạn" kiểu
Shopee Video / TikTok): xem, like, comment, theo dõi, đăng clip, gắn sản phẩm
+ voucher. Backend = **Go** (`/api/videos/*`). Cùng envelope với
[LIVESTREAM_API.md](LIVESTREAM_API.md) §1.

---

## 1. Base URL & Envelope

**Dev:**

```
{BACKEND_URL}/api/videos/{endpoint}      # BACKEND_URL = http://localhost:3000
```

**Content-Type:** `application/json` (trừ `POST /api/videos/upload` — `multipart/form-data`).

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
| `StatusCode` | string | `"200"`, `"401"`, `"404"`, `"422"`, `"429"`, `"500"` |
| `StatusMess` | string | Message hiển thị (Việt/Anh tuỳ endpoint) |
| `status` | number | HTTP status số |
| `message` | string | Trùng `StatusMess` |
| `data` | object \| array \| null | Payload (`null` khi lỗi) |

**Lỗi ví dụ:**

```json
{
  "Result": false,
  "StatusCode": "404",
  "StatusMess": "video not found",
  "status": 404,
  "message": "video not found",
  "data": null
}
```

> **Mã lỗi hay gặp:** `422` = id/body sai định dạng (`invalid id`, validation
> binding); `401` = thiếu/sai token; `403` = không có quyền đăng; `404` =
> video/creator không tồn tại; `429` = vượt rate limit.

---

## 2. Xác thực (JWT User)

Các API **like / comment / follow / report / đăng video** yêu cầu header:

```http
Authorization: Bearer {access_token}
```

Token lấy như livestream — `POST /api/login` (alias spec) hoặc
`POST /api/auth/login`. Xem [LIVESTREAM_API.md](LIVESTREAM_API.md) §2.

**API đọc công khai** (feed, chi tiết, comment list, hashtag) **không bắt buộc**
token. Nhưng nếu **gửi kèm** token, server sẽ điền các cờ viewer-relative
(`liked`, `following`, `shop_following`) — nên app vẫn nên gắn token cho mọi
request khi đã đăng nhập.

---

## 3. Quyền đăng video

Đăng / xoá clip dùng **cùng rule với livestream**: chỉ **admin**, **chủ shop**,
hoặc **member được duyệt `can_live`** mới đăng được. Thiếu quyền → **403**:

```json
{
  "Result": false,
  "StatusCode": "403",
  "StatusMess": "Tài khoản chưa được cấp quyền livestream. Liên hệ chủ shop để được duyệt.",
  "status": 403,
  "message": "...",
  "data": null
}
```

Kiểm tra quyền trước khi mở màn đăng: `GET /api/live/can-live`
(xem [LIVESTREAM_API.md](LIVESTREAM_API.md) §B9.1).

---

## 4. Luồng tổng thể (Mobile)

```
[Viewer]
  GET videos/feed           → danh sách clip "Dành cho bạn" (Video)
       → Phát MP4 (ExoPlayer / AVPlayer / video_player) bằng video_url
       → POST videos/:id/view khi clip hiển thị (dedupe theo user)
       → POST/DELETE videos/:id/like  · POST videos/:id/comments
       → POST videos/creators/:userId/follow  (hoặc follow shop ở card)
       → Tap sản phẩm (products[]) → màn product detail
       → Copy mã voucher (coupons[]) → áp ở checkout (commerce.ApplyCoupon)

[Creator] (admin / chủ shop / member can_live)
  POST videos/upload        → upload mp4 (+ cover) → nhận video_url
       → POST videos        → tạo clip (caption, hashtags, product_ids, coupon_ids)
       → worker bake overlay → overlay_url điền sau (tải/chia sẻ)
       → DELETE videos/:id  → gỡ clip

[Admin]
  GET video-reports?status=pending
       → POST video-reports/:reportId/resolve {action: takedown|dismiss}
```

---

## 5. Bảng endpoint nhanh

| # | Method | Endpoint | Auth | Màn app |
|---|--------|----------|------|---------|
| 1 | GET | `videos/feed` | opt | Tab Video — feed "Dành cho bạn" |
| 2 | GET | `videos/following` | JWT | Feed người đang theo dõi |
| 3 | GET | `videos/user/:userId` | opt | Trang creator (grid) |
| 4 | GET | `videos/:id` | opt | Mở 1 clip (deep link/share) |
| 5 | GET | `videos/:id/comments` | opt | Danh sách bình luận |
| 6 | GET | `videos/hashtags` | opt | Gợi ý/trending hashtag |
| 7 | GET | `videos/me` | JWT | Profile — tab "Video" |
| 8 | GET | `videos/me/liked` | JWT | Profile — tab "Đã thích" |
| 9 | GET | `videos/me/stats` | JWT | Header profile (đếm) |
| 10 | POST | `videos/:id/view` | opt | Đếm lượt xem |
| 11 | POST | `videos/:id/share` | opt | Đếm lượt chia sẻ |
| 12 | POST | `videos/:id/like` | JWT | Thả tim |
| 13 | DELETE | `videos/:id/like` | JWT | Bỏ tim |
| 14 | POST | `videos/:id/comments` | JWT | Gửi bình luận |
| 15 | POST | `videos/:id/report` | JWT | Báo cáo clip |
| 16 | POST | `videos/creators/:userId/follow` | JWT | Theo dõi creator |
| 17 | DELETE | `videos/creators/:userId/follow` | JWT | Bỏ theo dõi |
| 18 | POST | `videos/upload` | live | Upload mp4 + cover |
| 19 | POST | `videos` | live | Tạo clip |
| 20 | DELETE | `videos/:id` | live | Xoá clip của mình |
| 21 | GET | `video-reports` | admin | Hàng đợi kiểm duyệt |
| 22 | POST | `video-reports/:reportId/resolve` | admin | Gỡ / bỏ qua report |

`opt` = không bắt buộc token, nhưng gắn token để điền `liked`/`following`.
`live` = cần quyền đăng (§3). Phân trang dùng `?limit=&offset=` (hoặc `?page=`),
mặc định `limit=10`, tối đa `50`.

---

## 6. API Viewer (xem video)

### 6.1 `GET /api/videos/feed`

Feed "Dành cho bạn" — clip `status = active`, xếp theo điểm tương tác
(`like*3 + comment*2 + view*0.1`) rồi mới nhất.

| | |
|--|--|
| **Auth** | Không (gắn token để điền cờ viewer) |
| **Query** | `limit` (default 10, max 50), `offset` / `page` |
| **Rate limit** | — |

**Request:**

```
GET /api/videos/feed?limit=10&offset=0
```

**Response `data`:**

```json
{
  "videos": [
    {
      "id": "5e7d2c9a-1b34-4f56-8a90-abc123def456",
      "user_id": "9a1b2c3d-0000-0000-0000-000000000012",
      "shop_id": "cc33dd44-0000-0000-0000-000000000001",
      "video_url": "https://r2.tropia.vn/videos/clips/5e7d2c9a/source.mp4",
      "thumbnail_url": "https://r2.tropia.vn/videos/clips/5e7d2c9a/thumb.jpg",
      "caption": "Cà chua bi Đà Lạt mới hái sáng nay 🍅",
      "hashtags": ["cachua", "dalat", "nongsansach"],
      "duration_sec": 27,
      "width": 720,
      "height": 1280,
      "allow_reuse": true,
      "status": "active",
      "overlay_url": "https://r2.tropia.vn/videos/clips/5e7d2c9a/overlay.mp4",
      "view_count": 1820,
      "like_count": 245,
      "comment_count": 18,
      "share_count": 7,
      "created_at": "2026-06-07T09:30:00Z",
      "user_name": "Nông sản Đà Lạt",
      "user_avatar": "https://r2.tropia.vn/avatars/12.jpg",
      "shop_name": "Nông sản Đà Lạt",
      "shop_slug": "nong-san-da-lat",
      "shop_avatar": "https://r2.tropia.vn/logos/shop1.jpg",
      "products": [
        {
          "product_id": "p0010000-0000-0000-0000-000000000001",
          "name": "Cà chua bi 500g",
          "slug": "ca-chua-bi-500g",
          "image_url": "https://r2.tropia.vn/products/ca.jpg",
          "base_price": 35000,
          "sale_price": 25000,
          "total_sold": 320,
          "rating": 4.8,
          "review_count": 56,
          "flash_price": 19000,
          "flash_ends_at": "2026-06-07T14:00:00Z"
        }
      ],
      "coupons": [
        {
          "coupon_id": "f0f1f2f3-0000-0000-0000-000000000009",
          "code": "RAUCU10",
          "discount_type": "percent",
          "discount_value": 10,
          "min_order_value": 100000,
          "max_discount": 30000,
          "expires_at": "2026-06-10T17:00:00Z"
        }
      ],
      "liked": false,
      "following": false,
      "shop_following": false,
      "shop_has_voucher": true
    }
  ]
}
```

Mô tả các field — xem **§10. Object shapes**.

---

### 6.2 `GET /api/videos/following`

Clip của những creator / shop mà user đang theo dõi.

| | |
|--|--|
| **Auth** | Bearer JWT (bắt buộc) |
| **Query** | `limit`, `offset` / `page` |

**Response `data`:** `{ "videos": [ … như §6.1 ] }`. Rỗng → `{ "videos": [] }`.

---

### 6.3 `GET /api/videos/user/:userId`

Tất cả clip `active` của 1 creator (trang creator / grid).

| | |
|--|--|
| **Auth** | Không (gắn token để điền cờ) |
| **Param** | `:userId` = UUID người dùng |
| **Query** | `limit`, `offset` / `page` |

**Response `data`:** `{ "videos": [ … ] }`.

**Lỗi 422 (id sai):**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "invalid userId", "status": 422, "message": "invalid userId", "data": null }
```

---

### 6.4 `GET /api/videos/:id`

Chi tiết 1 clip (mở từ deep link / share).

| | |
|--|--|
| **Auth** | Không (gắn token để điền cờ) |
| **Param** | `:id` = UUID video |

**Response `data`:** **object Video** (không bọc trong `videos`), xem §10.1.

**Lỗi:**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "invalid id", "status": 422, "message": "invalid id", "data": null }
```

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "video not found", "status": 404, "message": "video not found", "data": null }
```

---

### 6.5 `GET /api/videos/:id/comments`

Bình luận của 1 clip (mới nhất trước).

| | |
|--|--|
| **Auth** | Không |
| **Query** | `limit` (default 10, max 50), `offset` / `page` |

**Response `data`:**

```json
{
  "comments": [
    {
      "id": "c1a2b3c4-0000-0000-0000-000000000001",
      "video_id": "5e7d2c9a-...",
      "user_id": "u9988776-...",
      "content": "Shop ơi còn hàng không ạ?",
      "like_count": 3,
      "created_at": "2026-06-07T09:45:00Z",
      "user_name": "Trần Thị B",
      "user_avatar": "https://r2.tropia.vn/avatars/88.jpg"
    }
  ]
}
```

---

### 6.6 `GET /api/videos/hashtags`

Gợi ý hashtag cho ô soạn "#" (autocomplete) hoặc trending khi `q` rỗng.

| | |
|--|--|
| **Auth** | Không |
| **Query** | `q` (optional, tiền tố `#` được bỏ qua), `limit` (default 10, max 20) |

**Request:**

```
GET /api/videos/hashtags?q=ca&limit=10
```

**Response `data`:**

```json
{
  "hashtags": [
    { "tag": "cachua", "video_count": 42, "view_count": 128400 },
    { "tag": "cafe",   "video_count": 18, "view_count": 53200 }
  ]
}
```

`q=""` → trending (nhiều view nhất). `q="ca"` → tag bắt đầu bằng `ca`.

---

### 6.7 Profile (JWT)

| Endpoint | `data` | Mô tả |
|----------|--------|--------|
| `GET /api/videos/me` | `{ "videos": [ … ] }` | Clip của chính mình (tab "Video") |
| `GET /api/videos/me/liked` | `{ "videos": [ … ] }` | Clip đã thích, mới-thích-trước (tab "Đã thích") |
| `GET /api/videos/me/stats` | xem dưới | Đếm cho header profile |

**`GET /api/videos/me/stats` → `data`:**

```json
{
  "following_count": 12,
  "follower_count": 340,
  "like_count": 5820
}
```

`following_count` = creator + shop đang theo dõi. `follower_count` /
`like_count` = tổng trên các clip của user. Server-authoritative (không
hardcode 0 ở client).

---

### 6.8 Đếm view / share (public)

| Endpoint | Rate limit | `data` |
|----------|-----------|--------|
| `POST /api/videos/:id/view` | 240/phút/IP | `{ "ok": true }` |
| `POST /api/videos/:id/share` | — | `{ "ok": true }` |

- `view`: dedupe **theo user đăng nhập** (gọi lại không tăng); ẩn danh vẫn
  đếm (đã rate-limit). Gọi khi clip thực sự hiển thị trên màn.
- `share`: tăng counter khi user bấm chia sẻ.
- Body: không cần. **Lỗi:** chỉ `422 invalid id`.

---

## 7. API Tương tác (JWT)

### 7.1 Like — `POST` / `DELETE /api/videos/:id/like`

| | |
|--|--|
| **Auth** | Bearer JWT |
| **Body** | Không |

**Response `data` (cả like lẫn unlike):**

```json
{ "liked": true, "like_count": 246 }
```

`DELETE` → `{ "liked": false, "like_count": 245 }`.

**Lỗi:**

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "video not found", "status": 404, "message": "video not found", "data": null }
```

---

### 7.2 `POST /api/videos/:id/comments`

| | |
|--|--|
| **Auth** | Bearer JWT |
| **Rate limit** | 30/phút/IP |

**Request:**

```json
{ "content": "Shop ơi còn hàng không ạ?" }
```

| Field | Kiểu | Bắt buộc | Ràng buộc |
|-------|------|----------|-----------|
| `content` | string | Có | 1–500 ký tự |

**Response `data` (comment vừa gửi):** object VideoComment (như §6.5).

**Lỗi:**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "Key: 'commentReq.Content' Error:Field validation for 'Content' failed on the 'required' tag", "status": 422, "message": "...", "data": null }
```

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "video not found", "status": 404, "message": "video not found", "data": null }
```

---

### 7.3 Follow creator — `POST` / `DELETE /api/videos/creators/:userId/follow`

| | |
|--|--|
| **Auth** | Bearer JWT |
| **Param** | `:userId` = UUID creator |
| **Body** | Không |

**Response `data`:**

```json
{ "following": true }
```

`DELETE` → `{ "following": false }`.

> **Card feed:** nút (+) ưu tiên **follow shop** nếu clip có `shop_id`
> (`shop_following`), ngược lại fallback **follow creator** (`following`).
> Follow shop dùng API shop riêng; endpoint này chỉ follow **creator**.

**Lỗi:**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "không thể tự theo dõi chính mình", "status": 422, "message": "không thể tự theo dõi chính mình", "data": null }
```

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "creator not found", "status": 404, "message": "creator not found", "data": null }
```

---

### 7.4 `POST /api/videos/:id/report`

Báo cáo clip vi phạm → vào hàng đợi kiểm duyệt admin.

| | |
|--|--|
| **Auth** | Bearer JWT |
| **Rate limit** | 20/phút/IP |

**Request:**

```json
{ "reason": "Nội dung phản cảm / lừa đảo" }
```

| Field | Kiểu | Bắt buộc | Ràng buộc |
|-------|------|----------|-----------|
| `reason` | string | Có | 1–200 ký tự |

**Response `data`:** `{ "ok": true }`.

**Lỗi:** `422` (reason rỗng / quá dài), `404 video not found`.

---

## 8. API Đăng video (creator)

### 8.1 `POST /api/videos/upload` — upload media

Lưu MP4 (+ cover tuỳ chọn) → trả URL. Sau đó client `POST /api/videos` kèm URL.

| | |
|--|--|
| **Auth** | Bearer JWT + quyền đăng (§3) |
| **Content-Type** | `multipart/form-data` |
| **Rate limit** | 20/giờ |

**Form fields:**

| Field | Bắt buộc | Ràng buộc |
|-------|----------|-----------|
| `video` | Có | `.mp4` / `.mov`, ≤ 50MB, magic-byte `ftyp` hợp lệ |
| `thumbnail` | Không | `.jpg/.jpeg/.png/.webp`, ≤ 5MB |

> Toàn bộ request body bị giới hạn cứng ~60MB (route này miễn trừ
> `RequestSizeGuard` toàn cục). Quá cap → đọc file lỗi → `422`.

**Response `data`:**

```json
{
  "video_url": "https://r2.tropia.vn/videos/clips/5e7d2c9a/source.mp4",
  "thumbnail_url": "https://r2.tropia.vn/videos/clips/5e7d2c9a/thumb.jpg"
}
```

R2 không cấu hình (dev) → URL dạng `"/uploads/videos/clips/.../source.mp4"`,
client ghép `{BACKEND_URL}` (giống HLS proxy). `thumbnail_url` chỉ có khi cover
hợp lệ.

**Lỗi:**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "chỉ chấp nhận mp4/mov", "status": 422, "message": "chỉ chấp nhận mp4/mov", "data": null }
```

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "video quá lớn (tối đa 50MB)", "status": 422, "message": "video quá lớn (tối đa 50MB)", "data": null }
```

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "tệp không phải video hợp lệ (mp4/mov)", "status": 422, "message": "...", "data": null }
```

---

### 8.2 `POST /api/videos` — tạo clip

| | |
|--|--|
| **Auth** | Bearer JWT + quyền đăng (§3) |

**Request:**

```json
{
  "video_url": "https://r2.tropia.vn/videos/clips/5e7d2c9a/source.mp4",
  "thumbnail_url": "https://r2.tropia.vn/videos/clips/5e7d2c9a/thumb.jpg",
  "caption": "Cà chua bi Đà Lạt mới hái sáng nay 🍅",
  "hashtags": ["cachua", "#dalat", "nongsansach"],
  "duration_sec": 27,
  "width": 720,
  "height": 1280,
  "allow_reuse": true,
  "product_ids": ["p0010000-0000-0000-0000-000000000001"],
  "coupon_ids": ["f0f1f2f3-0000-0000-0000-000000000009"]
}
```

| Field | Kiểu | Bắt buộc | Ghi chú |
|-------|------|----------|---------|
| `video_url` | string | Có | **Phải là URL do `upload` cấp** (server kiểm `Owns`) |
| `thumbnail_url` | string | Không | Cũng phải là URL đã upload nếu có |
| `caption` | string | Không | Tối đa 2200 ký tự |
| `hashtags` | string[] | Không | Tự bỏ `#`, bỏ rỗng; tối đa 20 tag, mỗi tag ≤ 50 ký tự |
| `duration_sec` / `width` / `height` | int | Không | Metadata hiển thị |
| `allow_reuse` | bool | Không | Mặc định `true` |
| `product_ids` | string[] (UUID) | Không | Gắn sản phẩm ("Xem sản phẩm"); tối đa 20. **Id lạ/không thuộc shop bị bỏ qua, không báo lỗi** |
| `coupon_ids` | string[] (UUID) | Không | Gắn voucher shop; tối đa 10. Id lạ bị bỏ qua tương tự |

Shop được suy ra từ người đăng (admin không shop → clip cá nhân).

**Response `data` (201):** object **Video** đầy đủ (như §10.1). Lúc mới tạo
`overlay_url = null` — worker bake overlay xong sẽ điền (trạng thái bake là nội
bộ DB, không trả ra JSON).

**Lỗi:**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "video_url không hợp lệ (phải là tệp đã upload)", "status": 422, "message": "...", "data": null }
```

```json
{ "Result": false, "StatusCode": "403", "StatusMess": "Tài khoản chưa được cấp quyền livestream. Liên hệ chủ shop để được duyệt.", "status": 403, "message": "...", "data": null }
```

```json
{ "Result": false, "StatusCode": "401", "StatusMess": "missing Authorization header", "status": 401, "message": "missing Authorization header", "data": null }
```

---

### 8.3 `DELETE /api/videos/:id` — xoá clip

Soft-delete clip của chính mình (admin xoá được mọi clip).

| | |
|--|--|
| **Auth** | Bearer JWT + quyền đăng (§3) |

**Response `data`:** `{ "ok": true }`.

**Lỗi:**

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "video not found", "status": 404, "message": "video not found", "data": null }
```

(`404` cũng trả khi clip không thuộc về người gọi — không lộ tồn tại.)

---

## 9. API Kiểm duyệt (admin)

> Đăng ký dưới resource **riêng** `/api/video-reports` (không phải
> `/api/videos/reports`) để tránh đụng route param `/videos/:id`.

### 9.1 `GET /api/video-reports`

| | |
|--|--|
| **Auth** | Bearer JWT + role admin |
| **Query** | `status` (`pending` mặc định · `all` = mọi trạng thái), `limit`, `offset` |

**Response `data`:**

```json
{
  "reports": [
    {
      "id": "r0000000-0000-0000-0000-000000000001",
      "video_id": "5e7d2c9a-...",
      "reporter_id": "u9988776-...",
      "reason": "Nội dung phản cảm",
      "status": "pending",
      "action": null,
      "created_at": "2026-06-07T10:05:00Z",
      "reporter_name": "Trần Thị B",
      "video_caption": "Cà chua bi Đà Lạt...",
      "video_thumbnail_url": "https://r2.tropia.vn/videos/clips/5e7d2c9a/thumb.jpg",
      "video_status": "active",
      "owner_name": "Nông sản Đà Lạt"
    }
  ]
}
```

### 9.2 `POST /api/video-reports/:reportId/resolve`

**Request:**

```json
{ "action": "takedown" }
```

| `action` | Tác dụng |
|----------|----------|
| `takedown` | Gỡ clip (chuyển `status` removed) + đóng report |
| `dismiss` | Bỏ qua report, giữ clip |

**Response `data`:** `{ "ok": true }`.

**Lỗi:**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "Key: 'resolveReq.Action' Error:Field validation for 'Action' failed on the 'oneof' tag", "status": 422, "message": "...", "data": null }
```

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "report not found", "status": 404, "message": "report not found", "data": null }
```

---

## 10. Object shapes

### 10.1 Video

| Field | Kiểu | Mô tả |
|-------|------|--------|
| `id` | UUID | Id video — dùng cho mọi route `/videos/:id/*` |
| `user_id` | UUID | Creator |
| `shop_id` | UUID? | Shop gắn clip (`null` = clip cá nhân) |
| `video_url` | string | MP4 gốc — **app phát URL này** (overlay/buy buttons tương tác) |
| `thumbnail_url` | string? | Cover |
| `caption` | string? | Mô tả |
| `hashtags` | string[] | Tag (không kèm `#`) |
| `duration_sec` / `width` / `height` | int | Metadata |
| `allow_reuse` | bool | Cho phép dùng lại audio/clip |
| `status` | string | `active` (feed chỉ trả `active`) |
| `overlay_url` | string? | Bản bake overlay (handle + caption + card SP + badge voucher + watermark) để **tải/chia sẻ ngoài**; `null` đến khi worker xong |
| `view_count` / `like_count` / `comment_count` / `share_count` | int | Counter |
| `created_at` | RFC3339 | |
| `user_name` / `user_avatar` | string? | Hồ sơ creator |
| `shop_name` / `shop_slug` / `shop_avatar` | string? | Thông tin shop (logo cho card shop) |
| `products` | VideoProduct[] | SP gắn ("Xem sản phẩm"), luôn là list (`[]` khi không có) |
| `coupons` | VideoCoupon[] | Voucher gắn, đọc live từ `coupons` (hết hạn/tắt → rớt) |
| `liked` | bool | Viewer đã thích? (cần token) |
| `following` | bool | Viewer follow **creator**? |
| `shop_following` | bool | Viewer follow **shop**? (luôn `false` nếu clip không có shop) |
| `shop_has_voucher` | bool | Shop có voucher đang chạy → card hiện "Mua với Voucher" (không phụ thuộc viewer) |

### 10.2 VideoProduct

| Field | Kiểu | Mô tả |
|-------|------|--------|
| `product_id` | UUID | Điều hướng sang product detail |
| `name` / `slug` | string | |
| `image_url` | string? | |
| `base_price` | int | Giá gốc (VND) |
| `sale_price` | int? | Giá khuyến mãi thường |
| `total_sold` | int | Đã bán |
| `rating` / `review_count` | float/int | |
| `flash_price` | int? | Giá flash sale đang chạy (`null` nếu không có) |
| `flash_ends_at` | RFC3339? | Mốc kết thúc flash → countdown trên card |

> Giá/tên/sold đọc **live** từ `products` (không snapshot) → card luôn hiện
> giá hiện tại.

### 10.3 VideoCoupon

| Field | Kiểu | Mô tả |
|-------|------|--------|
| `coupon_id` | UUID | |
| `code` | string | Mã viewer copy để áp ở checkout |
| `discount_type` | string | `percent` \| `fixed` |
| `discount_value` | float | |
| `min_order_value` | int | Đơn tối thiểu |
| `max_discount` | int? | Trần giảm (cho `percent`) |
| `expires_at` | RFC3339 | |

Áp mã ở checkout: `commerce.ApplyCoupon` — xem [COUPON_API.md](COUPON_API.md).

### 10.4 VideoComment

| Field | Kiểu | Mô tả |
|-------|------|--------|
| `id` / `video_id` / `user_id` | UUID | |
| `content` | string | |
| `like_count` | int | |
| `created_at` | RFC3339 | |
| `user_name` / `user_avatar` | string? | Tác giả |

---

## 11. Overlay bake (async)

Khi tạo clip, backend phát event `video.created` → worker bake một bản MP4 có
overlay tĩnh (handle shop + caption + card sản phẩm + badge voucher + watermark
Tropia) dùng cho **tải về / chia sẻ ngoài**. Đây là best-effort:

- Feed **luôn phát `video_url` (raw)** để giữ overlay live + nút mua tương tác.
- `overlay_url` = `null` cho tới khi worker xong; thất bại chỉ để `pending`,
  **không bao giờ chặn việc đăng**.

---

## 12. Luồng tích hợp thương mại (từ thẻ Video)

Feed Video **không chỉ là xem clip** — mỗi thẻ là một điểm bán hàng. Các nút
"Xem sản phẩm", "Thêm vào giỏ", "Mua với Voucher", follow shop, copy voucher
đều **gọi sang các resource thương mại khác** (`products` / `cart` / `coupons` /
`orders` / `payment` / `shops`). Object Video (§10.1) chỉ **mang sẵn dữ liệu để
render** (`products[]`, `coupons[]`, `shop_*`, `flash_*`, các cờ viewer); còn
**hành động** thì gọi API của resource tương ứng. Phần này mô tả **cách nối** —
chi tiết từng endpoint xem doc được dẫn.

> **Hai backend tách rời:** mọi luồng dưới đây chạy trên **Go `:3000`** (cùng
> JWT/UUID với feed Video). Add-to-cart từ video dùng **giỏ Go** (`/api/cart`),
> **không** đụng giỏ của app chính (PHP).

### 12.1 Tap sản phẩm → chi tiết + chọn biến thể

`VideoProduct` (§10.2) cho sẵn `product_id` **và** `slug`.

1. Mở chi tiết: `GET /api/products/:slug` (dùng `slug`, **không** phải UUID) —
   [CATALOG_API.md](CATALOG_API.md) §8.2.
2. Nếu `product.has_variants = true` → `GET /api/products/attributes` để dựng
   picker biến thể (CATALOG_API §8.3). `has_variants = false` → 1 variant mặc định.
3. Giá hiển thị, ưu tiên: `flash_price` (+ countdown tới `flash_ends_at`) →
   `sale_price` → `base_price` (xem §12.5).

### 12.2 Thêm vào giỏ từ thẻ (bottom-sheet biến thể)

Bottom-sheet chọn biến thể + số lượng → `POST /api/cart/items`
`{ variant_id, quantity }` — [CART_API.md](CART_API.md) §7.1.

- `variant_id` = **`product_variants.id`** lấy từ chi tiết SP (§12.1), **không
  phải** `VideoProduct.product_id`.
- Backend tự áp giá flash/sale → `unit_price`; client không tự tính giá.
- **Bắt đăng nhập** (chưa có JWT → `401`). Trùng variant → cộng dồn số lượng.
- Đây là **giỏ Go** (`/api/cart`) — badge/màn giỏ app chính không đổi.

### 12.3 Follow trên thẻ — shop ưu tiên, fallback creator

Nút (+) trên thẻ chọn mục tiêu theo dữ liệu clip:

| Điều kiện | Hành động | API | Cờ đọc trạng thái |
|-----------|-----------|-----|-------------------|
| Clip có `shop_id` | Follow **shop** | `POST`/`DELETE /api/shops/:slug/follow` (dùng `shop_slug` từ feed) — [CATALOG_API.md](CATALOG_API.md) §6.5 | `shop_following` |
| Clip **không** shop | Follow **creator** | `POST`/`DELETE /api/videos/creators/:userId/follow` (§7.3) | `following` |

Sau khi follow, clip của shop/creator đó xuất hiện ở `GET /api/videos/following`
(§6.2). Lưu ý: endpoint `videos/creators/:userId/follow` **chỉ** follow creator
— follow shop là API riêng của resource `shops`.

### 12.4 Voucher — copy mã & "Mua với Voucher"

Mỗi clip mang `coupons[]` (voucher gắn lúc tạo, §10.3) + cờ `shop_has_voucher`.

1. **Copy mã:** lấy `coupons[].code`. Kiểm trước khi áp (tuỳ chọn):
   `POST /api/coupons/validate` `{ code, orderTotal }` (camelCase) —
   [COUPON_API.md](COUPON_API.md) §3.
2. **Nút "Mua với Voucher"** (chỉ hiện khi `shop_has_voucher = true`): mở danh
   sách voucher shop để buyer chọn — `GET /api/coupons/shop/:shopId`
   (COUPON_API §2).
3. **Áp ở checkout:** truyền `coupon_codes[]` vào `POST /api/orders/checkout`
   (CART_API §11) — gộp được voucher sàn + shop. **Chưa auto-apply** từ thẻ;
   buyer tự nhập/chọn ở bước thanh toán.

### 12.5 Flash sale trên thẻ

`VideoProduct.flash_price` + `flash_ends_at` đọc **live** từ flash-sale đang
chạy (`null` nếu không có):

- Render badge "Giảm X%" + **countdown** tới `flash_ends_at`.
- `flash_ends_at < now` (hết giờ) → ẩn countdown, dùng `sale_price`/`base_price`.
- Giá flash được **cart áp lại khi add** (§12.2) — không snapshot ở client, nên
  card và giỏ luôn khớp. Flash sale do **admin** lên lịch (CATALOG_API §9).

### 12.6 Checkout & thanh toán

Từ giỏ → đặt hàng → (nếu online) thanh toán:

1. `POST /api/orders/checkout` — tiêu thụ dòng `is_selected`, nhận
   `coupon_codes[]` + `payment_method` (CART_API §11). Trả về `order`.
2. **COD** → đơn `confirmed`, xoá selected items ngay.
3. **Online** (`momo`/`vnpay`/`zalopay`) → giỏ giữ tới khi IPN xác nhận `paid`;
   gọi tiếp `POST /api/payment/{momo|vnpay|zalopay}` `{ order_id }` → nhận
   `{ pay_url, deeplink, qr_code_url }` để mở app/QR. Rate limit 10/phút.

### 12.7 Bảng tra nhanh: hành động trên thẻ → API

| Hành động trên thẻ Video | API thực thi | Auth | Doc |
|--------------------------|--------------|------|-----|
| Tap "Xem sản phẩm" | `GET /api/products/:slug` (+ `/attributes` nếu `has_variants`) | opt | CATALOG_API §8.2/§8.3 |
| Thêm vào giỏ (chọn biến thể) | `POST /api/cart/items` | JWT | CART_API §7.1 |
| Follow shop (clip có `shop_id`) | `POST`/`DELETE /api/shops/:slug/follow` | JWT | CATALOG_API §6.5 |
| Follow creator (clip không shop) | `POST`/`DELETE /api/videos/creators/:userId/follow` | JWT | §7.3 |
| Kiểm / áp voucher | `POST /api/coupons/validate` | JWT | COUPON_API §3 |
| "Mua với Voucher" (`shop_has_voucher`) | `GET /api/coupons/shop/:shopId` | opt | COUPON_API §2 |
| Đặt hàng (áp `coupon_codes`) | `POST /api/orders/checkout` | JWT | CART_API §11 |
| Thanh toán online | `POST /api/payment/{momo\|vnpay\|zalopay}` | JWT | (xem §12.6) |

### 12.8 Sơ đồ end-to-end (xem clip → mua)

```
[Viewer ở thẻ Video]
  GET videos/feed  → thẻ mang products[] / coupons[] / shop_* / flash_* / cờ
   │
   ├─ Tap SP ─────────→ GET products/:slug (+ /attributes)        [§12.1]
   │                     → chọn variant + qty
   │                     → POST cart/items {variant_id, quantity}  [§12.2]
   ├─ Nút (+) ────────→ shop_id? POST shops/:slug/follow           [§12.3]
   │                     else    POST videos/creators/:id/follow
   ├─ Voucher ────────→ copy coupons[].code · POST coupons/validate [§12.4]
   │                     (shop_has_voucher → GET coupons/shop/:shopId)
   └─ [Giỏ] ──────────→ POST orders/checkout {coupon_codes, payment_method} [§12.6]
                          ├─ cod    → đơn confirmed, xoá selected
                          └─ online → POST payment/{momo|vnpay|zalopay} {order_id}
                                       → mở pay_url / qr_code_url
```

---

## 13. Checklist tích hợp dev

- [ ] Gắn JWT vào mọi request khi đã đăng nhập (để có `liked`/`following`)
- [ ] Feed: `GET videos/feed`, phát `video_url`, `POST videos/:id/view` khi hiển thị
- [ ] Like/comment: `POST/DELETE videos/:id/like`, `POST videos/:id/comments`
- [ ] Follow: nút (+) → follow **shop** (`/api/shops/:slug/follow`) nếu có `shop_id`, else follow creator (§12.3)
- [ ] Sản phẩm: tap `products[]` → `GET products/:slug` (+ `/attributes` nếu `has_variants`) (§12.1)
- [ ] Thêm vào giỏ: bottom-sheet biến thể → `POST cart/items` `{variant_id, quantity}` (§12.2)
- [ ] Flash sale: đọc `flash_price`/`flash_ends_at` → badge + countdown; hết giờ → fallback `sale_price` (§12.5)
- [ ] Voucher: copy `coupons[].code` (kiểm `coupons/validate`) → áp `coupon_codes[]` ở checkout (§12.4)
- [ ] Checkout/thanh toán: `POST orders/checkout` → COD vs online (`payment/{momo|vnpay|zalopay}` `{order_id}`) (§12.6)
- [ ] Đăng: kiểm `GET live/can-live` → `upload` → `POST videos` (URL phải từ upload)
- [ ] `overlay_url` có thể `null` lúc mới đăng — chỉ dùng để tải/chia sẻ
- [ ] Báo cáo: `POST videos/:id/report` (admin xử lý ở `/video-reports`)
- [ ] Xử lý envelope `Result === false` + hiển thị `StatusMess`

---

## 14. Mapping Video ↔ Livestream

| | Video feed | Livestream (Phần B) |
|--|------------|----------------------|
| Định danh | `video.id` (UUID) | `session_id` (UUID) |
| Phát | MP4 `video_url` (VOD-like) | HLS proxy `/streams/:id/hls/...` |
| Tạo nội dung | `POST videos` (sau upload) | `POST /streams` (rồi push RTMP) |
| Gắn SP | `product_ids` khi tạo | `POST /streams/:id/products` |
| Gắn voucher | `coupon_ids` khi tạo | `POST /streams/:id/coupons` |
| Quyền đăng | live-permission gate (§3) | live-permission gate |
| Tương tác | like/comment/follow REST | chat REST + WS, like, gift |

---

## 15. Tham chiếu code

| Chủ đề | File |
|--------|------|
| Route + mount | `cmd/api/main.go` (`videoH.Register(router.Group("/api"), …)`) |
| Handler | `internal/video/handler.go` |
| Repository (query feed/like/comment/follow) | `internal/video/repo.go` |
| Object models | `internal/video/model.go` |
| Media store (R2 / local-disk) | `internal/video/store.go` |
| Overlay bake worker | `internal/vod/*` (event `video.created`) |
| Quyền đăng | `internal/live/member_handler.go` (`RequireLivePermission`) |
| Envelope | `internal/httpx/envelope.go` |
| Giỏ / checkout (§12.2, §12.6) | `internal/commerce/cart.go`, `orders.go` |
| Coupon (§12.4) | `internal/commerce/coupons.go`, `coupons_handler.go` |
| Sản phẩm / biến thể (§12.1) | `internal/catalog/products.go` |
| Flash sale (§12.5) | `internal/flashsale/*` |
| Follow shop (§12.3) | `internal/shops/shops.go` |
| Thanh toán (§12.6) | `internal/payment/handler.go` |

**Tài liệu liên quan:** [CART_API.md](CART_API.md) ·
[CATALOG_API.md](CATALOG_API.md) · [COUPON_API.md](COUPON_API.md) ·
[LIVESTREAM_API.md](LIVESTREAM_API.md)
