# Roles & Quyền truy cập API (Tropia)

Tài liệu mô tả **các role** và **quyền theo từng API**. Cập nhật khi thay đổi
middleware ở [backend/cmd/api/main.go](../backend/cmd/api/main.go).

---

## 1. Hai tầng phân quyền

Tropia có **2 tầng** quyền tách biệt:

### Tầng A — Role tài khoản (`profiles.role`)
| Role | Mô tả |
|------|-------|
| `buyer` | Người mua (mặc định khi đăng ký) |
| `seller` | Người bán — có thể tạo shop, đăng sản phẩm |
| `admin` | Quản trị nền tảng |

### Tầng B — Quyền livestream (theo shop) — `shop_live_permissions`
Đây là điểm **khác biệt cốt lõi** của nền tảng: **không phải ai cũng được live**
(khác Shopee). Chỉ được `live/start` nếu thuộc 1 trong 3 nhóm:

1. **Chủ shop** — `shops.seller_id = user` (suy ra từ bảng `shops`).
2. **Thành viên được duyệt** — có row trong `shop_live_permissions` với
   `status='approved'` **và** `can_live=true`. Gồm 2 loại `member_type`:
   - `staff` — nhân viên của shop.
   - `collaborator` — cộng tác viên (CTV).
3. **Admin**.

> Chủ shop là **người duyệt duy nhất** cho thành viên shop của mình.

---

## 2. Middleware (định nghĩa ở `main.go`)

| Tên | Ý nghĩa | Lỗi khi không đạt |
|-----|---------|-------------------|
| `authMw` | Bắt buộc JWT hợp lệ (mọi role) | 401 |
| `sellerMw` | Role ∈ {seller, admin} | 403 |
| `adminMw` | Role = admin | 403 |
| `optAuthMw` | Đọc JWT nếu có, không bắt buộc | — |
| `liveGate` | **Quyền livestream** (chủ shop / thành viên approved can_live / admin) | 403 `Tài khoản chưa được cấp quyền livestream...` |

`liveGate` (`live.RequireLivePermission`) chạy **sau** `authMw`; admin được bỏ
qua, còn lại tra `shop_live_permissions` + bảng `shops`.

---

## 3. Bảng quyền theo API

> Mọi response đều bọc envelope `{Result, StatusCode, ...}`.

### Auth
| Endpoint | Quyền |
|----------|-------|
| `POST /api/auth/register`, `/login`, `/refresh`, `/verify-otp`, `/forgot-password`, `/reset-password` | Public |
| `POST /api/login` (spec alias) | Public |
| `GET /api/auth/google`, `/google/exchange` | Public (OAuth) |
| `POST /api/auth/logout-all`, `GET /api/auth/me` | `authMw` |

### Live — Spec (LIVESTREAM_API.md)
| Endpoint | Quyền |
|----------|-------|
| `GET /api/live/list`, `/watch`, `/chat/history`, `/gifts`, `/gifts/recent` | **Public** |
| `POST /api/live/start` | `authMw` + **`liveGate`** ⭐ |
| `POST /api/live/stop`, `GET /api/live/my` | `authMw` (thao tác trên phiên của chính user) |
| `POST /api/live/chat/send`, `POST /api/live/gift/send` | `authMw` (mọi user đăng nhập — viewer chat/tặng quà) |

### Live — Quản lý thành viên (chủ shop) ⭐ MỚI
| Endpoint | Quyền |
|----------|-------|
| `GET /api/live/members` | `authMw` + **chủ shop** (enforce trong handler) |
| `POST /api/live/members` (cấp quyền) | `authMw` + chủ shop |
| `PATCH /api/live/members/:userSeq` (duyệt/tắt) | `authMw` + chủ shop |
| `DELETE /api/live/members/:userSeq` (gỡ) | `authMw` + chủ shop |

`:userSeq` = `profiles.seq` (id số). Body POST: `{identifier (email/SĐT), member_type, can_live, status}`.

### Live — Legacy `/streams` (UI cũ vẫn dùng)
| Endpoint | Quyền |
|----------|-------|
| `GET /api/live/streams`, `/:id`, `/:id/stats`, `/:id/chat`, `/:id/products`, `/:id/playback`, `/:id/coupons`, `/:id/timeline`, HLS, WS | **Public** |
| `POST /api/live/streams/:id/like` | Public (rate-limited) |
| `POST /api/live/streams/:id/join`, `/leave`, `/chat`, `/track-cart-add`, `/track-follow` | `authMw` |
| `POST /api/live/streams` (create), `/:id/end`, `GET /:id/publish`, `PATCH /:id/bot`, products CRUD, `/:id/pin`, coupons, `/:id/chat/mute|unmute` | `authMw` + **`liveGate`** + check **chủ phiên** (`session.seller_id == user`) |
| `POST /api/live/streams/:id/ai-suggestions`, `/ai-reply`, `/analyze` | `authMw` + `sellerMw` ⚠️ (xem mục 5) |

### SRS webhook (chỉ server SRS gọi)
| Endpoint | Quyền |
|----------|-------|
| `POST /api/srs/on_publish`, `on_unpublish`, `on_play`, `on_stop`, `on_dvr` | Shared secret `?secret=` (không phải JWT). `on_publish` còn validate `publish_token`. |

### Shop / Catalog / Commerce
| Nhóm | Public | authMw | seller/admin | admin |
|------|--------|--------|--------------|-------|
| `/api/shops` | `GET /`, `GET /:slug`, `/:slug/follow-status` | `me/info`, `me/following`, follow/unfollow | `POST /` create, `PATCH /:slug` | — |
| `/api/categories` | `GET /`, `GET /:slug` | — | — | create/update/delete |
| `/api/products` | `GET /`, `/:slug`, `/shop/:id`, `/attributes` | — | seller list, quick-create, update-status, delete | — |
| `/api/cart` | — | tất cả | — | — |
| `/api/coupons` | `/available`, `/shop/:id` | `/validate` | — | — |
| `/api/orders` | — | tất cả | — | — |
| `/api/payment` | callbacks/IPN | init momo/vnpay/zalopay | — | — |
| `/api/upload` | — | — | tất cả (seller/admin) | — |
| `/health`, `/metrics`, `/docs` | Public (metrics/docs có thể gắn token) | | | |

---

## 4. Luồng cấp quyền livestream

```
[Chủ shop]  (seller + có shop)
   POST /api/live/members { identifier: "<email/SĐT CTV>", member_type, can_live }
        → tạo row shop_live_permissions (status='approved', approved_by=owner)

[CTV / nhân viên]  (role buyer/seller bất kỳ, đã được approve)
   POST /api/live/start
        → liveGate: AuthorizedShop(user) → tìm thấy quyền approved+can_live → CHO PHÉP
        → tạo phiên (seller_id = chính CTV; host{} hiển thị CTV)

[User thường]  (không shop, không quyền)
   POST /api/live/start
        → liveGate: không thấy → 403 "Tài khoản chưa được cấp quyền livestream"
```

Tắt quyền tạm thời: `PATCH /api/live/members/:userSeq { "can_live": false }`
hoặc `{ "status": "rejected" }`. Gỡ hẳn: `DELETE`.

---

## 5. Điểm cần lưu ý / TODO

- ⚠️ **AI endpoints** (`/streams/:id/ai-suggestions|ai-reply|analyze`) hiện vẫn
  dùng `sellerMw` (role seller/admin). Nên một **CTV role=buyer** đã được duyệt
  live thì **không gọi được** các API AI này. Nếu muốn nhất quán, đổi sang
  `liveGate` + check chủ phiên.
- `liveGate` áp cho cả nhóm legacy `/streams` quản lý phiên → mỗi request thêm
  1–2 truy vấn DB (shops + shop_live_permissions). Có thể cache nếu cần.
- Spec gốc LIVESTREAM_API.md để `live/start` mở cho mọi user JWT — Tropia
  **cố ý siết lại** bằng `liveGate` (điểm khác biệt nền tảng). Đã cập nhật mô tả
  ở đây; nên thêm note 403 vào LIVESTREAM_API.md §5.1.
- Chưa có **UI Flutter** cho màn quản lý CTV — chủ shop hiện thao tác qua 4
  endpoint `/api/live/members`.

---

## 6. Tham chiếu code

| Việc | File |
|------|------|
| Đăng ký middleware + route | `backend/cmd/api/main.go` |
| `authMw`, `sellerMw`, `adminMw` | `backend/internal/auth/middleware.go` |
| `liveGate` (RequireLivePermission) | `backend/internal/live/member_handler.go` |
| Bảng quyền + truy vấn | `backend/internal/live/shop_member_repo.go`, `migrations/0011_shop_live_permissions.up.sql` |
| API quản lý member | `backend/internal/live/member_handler.go` |
