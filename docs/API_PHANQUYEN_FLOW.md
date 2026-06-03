# Tropia Live — Bổ sung tài liệu API: Giới thiệu, Phân quyền (Role) & Flow



## 11. Giới thiệu mô hình tài khoản & quyền

### 11.1. Ba loại tài khoản (role)

Mỗi người dùng có đúng **một** role lưu ở cột `profiles.role`:

| Role | Ai là người này | Làm được gì nổi bật |
|------|-----------------|---------------------|
| `buyer` | Người mua — **mặc định** khi đăng ký | Xem live, chat, tặng quà, thêm giỏ, đặt hàng, thanh toán, theo dõi shop |
| `seller` | Người bán | Mọi quyền của buyer **+** tạo shop (1 shop/seller), đăng/sửa sản phẩm, tải ảnh, tạo phiên live cho shop của mình |
| `admin` | Quản trị nền tảng | Toàn quyền: quản lý danh mục, bỏ qua mọi kiểm tra quyền sở hữu, livestream bất kỳ phiên nào |

> **Chống leo thang quyền:** khi đăng ký chỉ chấp nhận `buyer`/`seller`. Truyền
> `role=admin` bị **âm thầm hạ về `buyer`**. Admin chỉ tạo trực tiếp trong DB.
> (Xem mục 3.2 bản PDF.)

### 11.2. Điểm khác biệt cốt lõi: quyền livestream là **tầng thứ hai**

Đây là khác biệt lớn nhất so với mô hình Shopee và là chỗ bản PDF mô tả chưa
đủ. Ở Tropia, **role `seller` chưa đủ để được lên sóng**. Quyền livestream là
một **tầng phân quyền riêng, gắn theo shop**, lưu ở bảng
`shop_live_permissions`. Một tài khoản chỉ được phép `live/start` nếu thuộc
**một trong ba nhóm**:

1. **Chủ shop** — `shops.seller_id == user` (suy ra từ bảng `shops`).
2. **Thành viên được duyệt của shop** — có bản ghi trong
   `shop_live_permissions` với `status='approved'` **và** `can_live=true`.
   Có hai loại thành viên (`member_type`):
   - `staff` — nhân viên của shop;
   - `collaborator` — cộng tác viên (CTV / KOL/KOC).
3. **Admin** — luôn được phép.

> Một CTV có thể mang role `buyer` mà **vẫn được lên sóng** cho shop đã duyệt
> họ. Ngược lại, một `seller` chưa có shop (hoặc chưa được shop khác duyệt) sẽ
> **bị từ chối** khi gọi `live/start`. Chủ shop là **người duyệt duy nhất** cho
> thành viên shop của mình.

Tóm tắt hai tầng:

```
## 0. Sơ đồ phả hệ role (cái nhìn tổng quan)

```
                          ┌──────────────────────────┐
                          │        TÀI KHOẢN          │
                          │     (profiles.role)       │
                          └────────────┬──────────────┘
                                       │  Tầng A — role tài khoản (1 user = 1 role)
          ┌────────────────────────────┼────────────────────────────┐
          ▼                            ▼                             ▼
   ┌─────────────┐             ┌───────────────┐              ┌─────────────┐
   │   buyer     │             │    seller     │              │    admin    │
   │ (mặc định)  │             │ tạo 1 shop,   │              │ toàn quyền  │
   │ mua/xem/    │             │ đăng sản phẩm │              │ nền tảng    │
   │ chat/quà    │             │               │              │             │
   └──────┬──────┘             └───────┬───────┘              └──────┬──────┘
          │                            │                             │
          │  Role KHÔNG tự cho quyền live. Quyền live là TẦNG B,     │ admin
          │  gắn theo shop, lưu ở `shop_live_permissions`.           │ luôn
          │                            │                             │ được
          └──────────────┐             │            ┌────────────────┘ live
                          ▼            ▼            ▼
                 ╔═══════════════════════════════════════════╗
                 ║   Tầng B — AI ĐƯỢC LÊN SÓNG (liveGate)     ║
                 ║   POST /api/live/start  →  cần 1 trong 3:  ║
                 ╠═══════════════════════════════════════════╣
                 ║  ① CHỦ SHOP   shops.seller_id == user      ║
                 ║  ② THÀNH VIÊN shop được DUYỆT:             ║
                 ║       shop_live_permissions                ║
                 ║       status='approved' AND can_live=true  ║
                 ║       member_type ∈ { staff | collaborator}║
                 ║  ③ ADMIN                                   ║
                 ╚═══════════════════════════════════════════╝
                                   │
                                   ▼
                  Không thuộc 3 nhóm → 403 "Tài khoản chưa được
                  cấp quyền livestream. Liên hệ chủ shop để được duyệt."
```

**Ai duyệt ai (phả hệ cấp quyền live):**

```
        ADMIN ───(tạo trong DB)──► seller / buyer
          │
          │ (bỏ qua mọi kiểm tra — live phiên nào cũng được)
          ▼
   ┌──────────────┐   POST /api/live/members { identifier, member_type, can_live }
   │   CHỦ SHOP    │ ───────────────────────────────────────────────┐
   │ (seller +    │   PATCH /:userSeq (duyệt/tắt)  DELETE /:userSeq  │
   │  có 1 shop)  │   ◄── là NGƯỜI DUYỆT DUY NHẤT cho shop của mình  │
   └──────────────┘                                                  ▼
                                              ┌────────────────────────────────┐
                                              │  Thành viên shop (đã approved)  │
                                              ├────────────────────────────────┤
                                              │  • staff        — nhân viên     │
                                              │  • collaborator — CTV / KOL/KOC │
                                              │  (role gốc có thể vẫn là buyer) │
                                              └────────────────────────────────┘
```

> **Lưu ý quan trọng:** role và quyền live **độc lập**. Một `seller` chưa có
> shop (hoặc chưa được shop khác duyệt) **không** được live; ngược lại một
> `buyer` được chủ shop duyệt làm CTV thì **được** live. App gọi
> `GET /api/live/can-live` để biết có nên hiện nút "Phát live" hay không.

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
```

---

## 12. Giải thích phân quyền theo từng nhóm API

### 12.1. Các middleware (định nghĩa ở `main.go`)

Mọi route đi qua một chuỗi middleware. Năm "cổng" quyền chính:

| Middleware | Ý nghĩa | Lỗi khi không đạt |
|-----------|---------|-------------------|
| `authMw` | Bắt buộc JWT hợp lệ (mọi role) | `401 UNAUTHORIZED` |
| `sellerMw` | Role ∈ {`seller`, `admin`} | `403 SELLER_ONLY` |
| `adminMw` | Role = `admin` | `403 ADMIN_ONLY` |
| `optAuthMw` | Đọc JWT **nếu có**, không bắt buộc (để trả thêm `is_following`…) | — |
| `liveGate` | **Quyền livestream** (chủ shop / thành viên approved+can_live / admin) | `403` — *"Tài khoản chưa được cấp quyền livestream. Liên hệ chủ shop để được duyệt."* |

`liveGate` (`live.RequireLivePermission`) luôn chạy **sau** `authMw`. Với
`admin` nó cho qua ngay; còn lại nó tra bảng `shops` + `shop_live_permissions`
(thêm 1–2 truy vấn DB mỗi request). Ngoài `liveGate`, các thao tác trên một
phiên cụ thể còn kiểm tra **chủ phiên** ngay trong handler
(`session.seller_id == user`) — không phải cứ có quyền live là sửa được phiên
của người khác.

> **Ba lớp bảo vệ cho thao tác host:** `authMw` (đã đăng nhập) → `liveGate`
> (được phép live nói chung) → check **chủ phiên** trong handler (đúng phiên
> của mình). Trượt lớp nào trả lỗi tương ứng (401 / 403 / 403 `NOT_STREAM_OWNER`).

### 12.2. Bảng quyền — Xác thực & tài khoản (`/api/auth`)

| Endpoint | Quyền |
|----------|-------|
| `POST /register`, `/login`, `/refresh`, `/verify-otp`, `/resend-verify-email`, `/forgot-password`, `/reset-password` | Công khai |
| `POST /api/login` *(alias spec mobile: `{username, password}` → `{token, expires, user}`)* | Công khai |
| `GET /google`, `/google/callback`, `/google/exchange` | Công khai (OAuth2 + PKCE) |
| `POST /logout` | Cookie |
| `POST /logout-all`, `GET /me` | `authMw` |

### 12.3. Bảng quyền — Livestream (`/api/live`)

Backend phục vụ **đồng thời hai bộ endpoint** trên cùng tiền tố `/api/live`:

- **Bộ "spec" (hợp đồng app mobile)** — đăng ký bởi `RegisterSpec`.
- **Bộ "legacy /streams"** (UI Flutter hiện hành: sản phẩm, coupon, ghim, stats,
  timeline VOD, chat WebSocket) — đăng ký bởi `Register`. Đây là bộ mà **bản
  PDF mục 4 đang mô tả**.

Cả hai cùng tồn tại và thao tác trên cùng dữ liệu phiên.

**a) Bộ spec (mobile):**

| Method | Đường dẫn | Quyền |
|--------|-----------|-------|
| GET | `/api/live/list` | **Công khai** (rate-limit 120/phút) |
| GET | `/api/live/watch?stream_key=` | **Công khai** |
| GET | `/api/live/chat/history?stream_key=` | **Công khai** |
| GET | `/api/live/gifts` | **Công khai** (catalog quà) |
| GET | `/api/live/gifts/recent?stream_key=` | **Công khai** |
| POST | `/api/live/start` | `authMw` + **`liveGate`** ⭐ (rate-limit 10/giờ) |
| POST | `/api/live/stop` | `authMw` (đóng phiên đang mở của chính mình) |
| GET | `/api/live/my` | `authMw` |
| POST | `/api/live/chat/send` | `authMw` (mọi user đăng nhập; rate-limit 8/3s) |
| POST | `/api/live/gift/send` | `authMw` (mọi user; trừ **điểm tích lũy**) |

**b) Bộ legacy `/streams`** *(bản PDF mục 4)*:

| Nhóm | Quyền |
|------|-------|
| `GET /streams`, `/:id`, `/:id/stats`, `/:id/chat`, `/:id/products`, `/:id/playback`, `/:id/coupons`, `/:id/timeline`, HLS proxy, WS chat/list | **Công khai** |
| `POST /streams/:id/like` | Công khai (rate-limit 60/phút/IP) |
| `POST /streams/:id/join`, `/leave`, `/chat`, `/track-cart-add`, `/track-follow` | `authMw` |
| `POST /streams` (tạo), `/:id/end`, `GET /:id/publish`, `PATCH /:id/bot`, products `POST/PUT/DELETE`, `/:id/pin`, coupons `POST`+`/announce`, `/:id/chat/mute`+`/unmute` | `authMw` + **`liveGate`** + check **chủ phiên** |
| `POST /streams/:id/ai-suggestions`, `/ai-reply` | `authMw` (mọi user đăng nhập) |
| `POST /streams/:id/analyze` (phân tích cảm xúc cho host) | `authMw` + **`liveGate`** |

> **Đính chính bản PDF:** mục 4.1 ghi `POST /api/live/streams` quyền
> *"Seller/Admin"*. Thực tế quyền là **`liveGate`** (chủ shop / thành viên
> approved+can_live / admin), **không phải** mọi seller. Tương tự, `analyze`
> đã chuyển từ `sellerMw` sang `liveGate` để **CTV/nhân viên được duyệt cũng
> dùng được** (trước đây role=buyer bị chặn).

**c) Quản lý thành viên livestream — chỉ chủ shop** ⭐ (bản PDF thiếu hẳn):

| Method | Đường dẫn | Quyền | Mô tả |
|--------|-----------|-------|-------|
| GET | `/api/live/can-live` | `authMw` | Cho app biết có nên hiện nút "Phát live" không → `{can_live, is_admin, shop_id}` |
| GET | `/api/live/members` | `authMw` + **chủ shop** | Danh sách thành viên shop |
| POST | `/api/live/members` | `authMw` + chủ shop | Cấp quyền: body `{identifier(email/SĐT), member_type, can_live, status}` |
| PATCH | `/api/live/members/:userSeq` | `authMw` + chủ shop | Duyệt / tắt: `{status, can_live}` |
| DELETE | `/api/live/members/:userSeq` | `authMw` + chủ shop | Gỡ thành viên |

`:userSeq` = `profiles.seq` (id số). "Chủ shop" được enforce trong handler:
nếu người gọi chưa có shop → `403 "Bạn chưa có shop để quản lý cộng tác viên"`.

### 12.4. Bảng quyền — Shop / Danh mục / Sản phẩm / Thương mại

| Nhóm | Công khai | `authMw` | `sellerMw` (seller/admin) | `adminMw` |
|------|-----------|----------|---------------------------|-----------|
| `/api/shops` | `GET /`, `GET /:slug` *(+optAuth)*, `/:slug/follow-status` | `me/info`, `me/following`, follow/unfollow | `POST /` (tạo), `PATCH /:slug` | — |
| `/api/categories` | `GET /`, `GET /:slug` | — | — | `POST`, `PATCH`, `DELETE` |
| `/api/products` | `GET /`, `/:slug`, `/shop/:id`, `/attributes` | — | `seller/list`, `quick-create`, `:id/status`, `DELETE :id`, `attributes/values` | — |
| `/api/cart` | — | **tất cả** | — | — |
| `/api/orders` | — | **tất cả** (đặt hàng 20/phút) | — | — |
| `/api/coupons` | — | `/available`, `/shop/:id`, `/validate` | — | — |
| `/api/payment` | callbacks/IPN/return *(cổng gọi, xác minh chữ ký)* | init `momo`/`vnpay`/`zalopay` (10/phút) | — | — |
| `/api/upload` | — | — | **tất cả** (seller/admin) | — |
| `/api/srs/*` | — | — | — | — *(shared secret `?secret=`, không phải JWT)* |
| `/health` | Công khai | — | — | — |
| `/metrics`, `/docs/openapi.yaml` | Công khai *(có thể gắn `METRICS_TOKEN`/`DOCS_TOKEN`)* | — | — | — |

> **Kiểm tra quyền sở hữu (BOLA)** áp ở tầng handler cho mọi tài nguyên gắn chủ:
> đơn hàng, sản phẩm, shop, ảnh upload, phiên live. Truy cập tài nguyên không
> thuộc về mình trả **404** (không phải 403) để không lộ sự tồn tại — trừ một
> vài chỗ cố ý trả 403 (`NOT_STREAM_OWNER`, `NOT_ORDER_OWNER` ở payment) để báo
> rõ "đúng có nhưng không phải của bạn".

---

## 13. Các flow nghiệp vụ hoàn chỉnh

### 13.1. Flow tài khoản: đăng ký → xác thực → đăng nhập

```
register (buyer/seller)
   → bcrypt(cost 12) + sinh OTP 6 số (Redis) + phát auth.email_otp
   → worker gửi email OTP
verify-otp
   → email_verified=true + phát user.registered → worker gửi email chào mừng
login
   → JWT access (≈15') + refresh token (cookie HttpOnly + body cho mobile)
   → sai 5 lần ⇒ khóa 15 phút (429 ACCOUNT_LOCKED)
refresh (xoay vòng)
   → cấp token mới, thu hồi token cũ cùng 'family'
   → nếu token đã thu hồi bị dùng lại ⇒ vô hiệu cả family (chống đánh cắp)
```

OAuth Google: `GET /google` → Google → `/google/callback` tạo One-Time-Code
(TTL 60s) → deep-link về app → `/google/exchange` đổi OTC lấy token (xác minh
PKCE S256).

### 13.2. Flow cấp quyền livestream (tầng B)

Đây là flow đặc trưng của Tropia — **không có ở bản PDF**.

```
[Trở thành seller có shop]
   register(role=seller) → POST /api/shops  (mỗi seller đúng 1 shop)
        → từ nay là "chủ shop", mặc định có quyền live cho shop mình

[Chủ shop cấp quyền cho CTV / nhân viên]
   POST /api/live/members
        { identifier:"<email/SĐT của CTV>", member_type:"collaborator"|"staff",
          can_live:true, status:"approved" }
        → upsert shop_live_permissions(status=approved, approved_by=owner)

[CTV / nhân viên (role buyer/seller bất kỳ) lên sóng]
   GET /api/live/can-live           → {can_live:true, shop_id}  (app hiện nút)
   POST /api/live/start
        → liveGate: AuthorizedShop(user) thấy quyền approved+can_live ⇒ CHO PHÉP
        → tạo phiên (seller_id = chính CTV; host{} hiển thị CTV)

[User thường không quyền]
   POST /api/live/start
        → liveGate không thấy ⇒ 403 "Tài khoản chưa được cấp quyền livestream"

[Thu hồi]
   PATCH /api/live/members/:userSeq { can_live:false }   (tắt tạm)
   PATCH /api/live/members/:userSeq { status:"rejected" }
   DELETE /api/live/members/:userSeq                     (gỡ hẳn)
```

### 13.3. Flow một phiên livestream đầy đủ (kèm ai-làm-được-gì)

```
1. Chủ shop / CTV approved / admin   → POST /api/live/start (hoặc /streams)
       liveGate kiểm tra ⇒ tạo phiên 'scheduled/ready', sinh stream_key + publish_token
2. Host                              → đẩy RTMP/WHIP/SRT bằng OBS/Larix/app
       (publish_token bảo vệ: SRS on_publish validate token, từ chối key lạ)
3. SRS                               → POST /api/srs/on_publish (?secret=)
       backend đánh dấu phiên 'live' + đẩy refresh tab Live qua WS /ws/list
4. Người xem (công khai)             → GET /api/live/list, /watch hoặc /streams/:id/playback
       lấy HLS, mở HlsViewer; viewer đăng nhập POST /:id/join để được đếm
5. Tương tác:
       - viewer (authMw):   chat (/chat/send hoặc /:id/chat), like (công khai),
                            tặng quà (/gift/send, trừ điểm), thêm giỏ, đặt hàng
       - host (chủ phiên):  ghim sản phẩm /:id/pin, thêm/sửa sản phẩm,
                            tạo & phát coupon, bật/tắt bot AI /:id/bot,
                            mute/unmute người chat
       - tất cả realtime qua WebSocket /streams/:id/ws/chat
6. Kết thúc                          → host POST /api/live/stop (hoặc /streams/:id/end)
       trạng thái 'ended'; SRS on_unpublish đóng dấu thời điểm (chịu được reconnect)
7. VOD                               → SRS on_dvr → phát recording.created
       → worker ghép phụ đề chat + overlay (ghim/coupon/quà) → MP4 → R2
       → lưu live_sessions.vod_mp4_url để xem lại
```

### 13.4. Flow tặng quà bằng điểm tích lũy (bản PDF thiếu)

```
GET  /api/live/gifts                 → catalog quà (công khai)
POST /api/live/gift/send  (authMw)   { stream_key, gift_id, quantity(1–99) }
       điều kiện: stream 'live', không tự tặng mình, đủ điểm tích lũy
       trừ điểm ⇒ { gift, points_remaining }  + phát realtime + log live_event
       lỗi: 400 "Không đủ điểm. Cần N điểm." / "Quà không tồn tại"
GET  /api/live/gifts/recent?stream_key=   → quà gần đây (công khai)
```

Quà được ghi thành `live_event` để bake overlay banner quà vào VOD.

### 13.5. Flow đặt hàng & thanh toán (tóm tắt, đặt trong ngữ cảnh quyền)

```
buyer (authMw):
   - đặt 1 sản phẩm trong live   → POST /api/orders   (khóa kho Redis, áp coupon, trừ kho)
   - thanh toán giỏ              → POST /api/orders/checkout  (nhiều item, snapshot địa chỉ)
   - init thanh toán             → POST /api/payment/{momo|vnpay|zalopay} (kiểm tra BOLA, đơn chưa trả)
cổng thanh toán (công khai, xác minh chữ ký):
   - browser redirect            → callback/return  (302 về app/web)
   - server-to-server            → IPN/callback → ConfirmPayment (idempotent):
        đánh dấu 'paid' + dọn giỏ + phát payment.success → worker gửi email biên nhận
```

---

## 14. Đính chính & bổ sung so với bản PDF

| Chỗ trong PDF | Trạng thái | Đúng phải là |
|---------------|-----------|--------------|
| 4.1 — `POST /api/live/streams` ghi *Seller/Admin* | ✏️ Đính chính | `authMw` + **`liveGate`** (chủ shop / thành viên approved+can_live / admin) |
| 4.4 — `analyze` ghi *Seller/Admin* | ✏️ Đính chính | `authMw` + **`liveGate`** (CTV/nhân viên approved dùng được) |
| Thiếu mô hình **2 tầng quyền** | ➕ Bổ sung | Mục 11.2 + 12.1 + bảng `shop_live_permissions` |
| Thiếu nhóm **spec mobile** `/list /watch /start /stop /my /chat/send /gift/send /gifts` | ➕ Bổ sung | Mục 12.3a |
| Thiếu nhóm **`/api/live/members`** + `/can-live` | ➕ Bổ sung | Mục 12.3c + flow 13.2 |
| Thiếu **hệ thống quà tặng** bằng điểm | ➕ Bổ sung | Mục 13.4 |
| Thiếu alias `POST /api/login` | ➕ Bổ sung | Mục 12.2 |
| Webhook SRS chỉ nói `?secret=` | ➕ Làm rõ | `on_publish` còn validate `publish_token` của phiên |

---

## 15. Chi tiết JSON & HTTP code (request / response từng endpoint)

> Phần này bổ sung **ví dụ JSON cụ thể + mã HTTP** cho các endpoint mà mục
> 12–13 mới mô tả ở mức quyền/luồng. Các endpoint live spec chung (list,
> watch, chat, gift…) đã có JSON đầy đủ ở **[LIVESTREAM_API.md](LIVESTREAM_API.md)** —
> ở đây chỉ làm rõ những endpoint **đặc thù phân quyền** (login alias,
> `can-live`, `members`) và **bảng mã lỗi chung**.

### 15.1. Envelope & quy ước HTTP code

Mọi response (trừ SRS webhook, HLS, WebSocket, `/health`, `/metrics`,
`/docs/*`) đều được bọc trong envelope chuẩn ở
[backend/internal/httpx/envelope.go](../backend/internal/httpx/envelope.go):

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

- `StatusCode` (string) và `status` (number) **luôn bằng mã HTTP thật** của
  response — proxy/log tooling thấy đúng code (200/400/401/403/404/429/500).
- Khi **lỗi**, wrapper bỏ object lỗi gốc, **`data = null`** và đẩy thông điệp
  người dùng lên `StatusMess`/`message`.
- ⚠️ Envelope **không phơi ra** hằng code nội bộ (`BAD_REQUEST`, `FORBIDDEN`…);
  app phân biệt lỗi bằng `status` + (nếu cần) so khớp `StatusMess`.

**Bảng mã lỗi nội bộ → HTTP** (từ [errors.go](../backend/internal/httpx/errors.go)):

| Hằng `NewXxx` | HTTP | `StatusMess` mặc định (khi handler không set) |
|---------------|------|----------------------------------------------|
| `NewBadRequest` | **400** | Yêu cầu không hợp lệ |
| `NewPayment` | **402** | (thông điệp thanh toán cụ thể) |
| `NewAuth` | **401** | Chưa xác thực hoặc token không hợp lệ |
| `NewForbidden` | **403** | Không có quyền truy cập |
| `NewNotFound` | **404** | Không tìm thấy |
| `NewConflict` | **409** | (thông điệp xung đột cụ thể) |
| `NewValidation` | **422** | (kèm `details` lỗi từng field) |
| `NewRateLimit` | **429** | Quá nhiều yêu cầu, vui lòng thử lại sau |
| `NewInternal` | **500** | Lỗi hệ thống |

> Riêng `NewValidation` (422) là lỗi **duy nhất** kèm payload chi tiết: trước
> khi bị wrapper rút gọn, body có thêm `details` (map field → message). App nên
> ưu tiên đọc `StatusMess` để hiển thị.

### 15.2. `POST /api/login` — alias đăng nhập cho mobile

Quyền: **công khai**. Khác với `/api/auth/login` (dùng `email`), alias này
nhận `{username, password}` (username = SĐT hoặc email) và trả thẳng token.

**Request:**

```json
{ "username": "0901234567", "password": "Password123" }
```

**`200 OK` — `data`:**

```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires": 1717094400,
  "user": {
    "id": 12,
    "username": "0901234567",
    "email": "user@example.com",
    "full_name": "Nguyễn Văn A",
    "so_dien_thoai": "0901234567"
  }
}
```

**`401 Unauthorized` — sai thông tin:**

```json
{
  "Result": false, "StatusCode": "401", "StatusMess": "Sai tài khoản hoặc mật khẩu",
  "status": 401, "message": "Sai tài khoản hoặc mật khẩu", "data": null
}
```

**`429 Too Many Requests` — quá 5 lần sai (khóa 15 phút):**

```json
{
  "Result": false, "StatusCode": "429",
  "StatusMess": "Tài khoản tạm khóa, thử lại sau 15 phút",
  "status": 429, "message": "Tài khoản tạm khóa, thử lại sau 15 phút", "data": null
}
```

### 15.3. `GET /api/live/can-live` — app có nên hiện nút "Phát live"?

Quyền: **`authMw`** (bất kỳ user đăng nhập). Trả về 3 trường để client
ẩn/hiện nút trước khi gọi `live/start` (tránh điền form rồi mới bị 403).

**`200 OK` — chủ shop / thành viên approved:**

```json
{
  "can_live": true,
  "is_admin": false,
  "shop_id": "9f1c2d3e-4a5b-6c7d-8e9f-0a1b2c3d4e5f"
}
```

**`200 OK` — admin (live bất kỳ phiên nào):**

```json
{ "can_live": true, "is_admin": true, "shop_id": null }
```

**`200 OK` — user thường không có quyền:**

```json
{ "can_live": false, "is_admin": false, "shop_id": null }
```

**`401 Unauthorized` — thiếu/sai token:**

```json
{
  "Result": false, "StatusCode": "401", "StatusMess": "Thiếu Authorization token",
  "status": 401, "message": "Thiếu Authorization token", "data": null
}
```

### 15.4. `POST /api/live/start` — lỗi 403 từ `liveGate`

Khi user đăng nhập nhưng **không** thuộc nhóm được live, `liveGate` chặn
**trước khi** vào handler:

```json
{
  "Result": false, "StatusCode": "403",
  "StatusMess": "Tài khoản chưa được cấp quyền livestream. Liên hệ chủ shop để được duyệt.",
  "status": 403,
  "message": "Tài khoản chưa được cấp quyền livestream. Liên hệ chủ shop để được duyệt.",
  "data": null
}
```

`429` khi vượt rate-limit (10 lần `start`/giờ). Response `200` thành công có
shape đầy đủ ở [LIVESTREAM_API.md §5.1](LIVESTREAM_API.md).

### 15.5. Quản lý thành viên — `GET/POST/PATCH/DELETE /api/live/members`

Quyền: **`authMw` + chủ shop**. Người gọi chưa có shop → `403`.

Đối tượng `ShopMember` (dùng cho cả list/add/update) — từ
[shop_member_repo.go](../backend/internal/live/shop_member_repo.go):

| Field | Kiểu | Mô tả |
|-------|------|-------|
| `user_id` | int | `profiles.seq` của thành viên (dùng cho URL PATCH/DELETE = `:userSeq`) |
| `full_name` | string | Tên thành viên |
| `email` | string | Email |
| `so_dien_thoai` | string | SĐT |
| `member_type` | string | `staff` \| `collaborator` |
| `can_live` | bool | Có được lên sóng không |
| `status` | string | `pending` \| `approved` \| `rejected` |
| `approved_at` | string\|absent | Thời điểm duyệt (ẩn nếu chưa duyệt) |
| `created_at` | string | Thời điểm thêm |

#### a) `GET /api/live/members` — danh sách thành viên shop

**`200 OK` — `data`:**

```json
{
  "items": [
    {
      "user_id": 88,
      "full_name": "Trần Thị B",
      "email": "ctv.b@example.com",
      "so_dien_thoai": "0912345678",
      "member_type": "collaborator",
      "can_live": true,
      "status": "approved",
      "approved_at": "2026-06-01 09:30:00",
      "created_at": "2026-06-01 09:00:00"
    },
    {
      "user_id": 91,
      "full_name": "Lê Văn C",
      "email": "staff.c@example.com",
      "so_dien_thoai": "0987654321",
      "member_type": "staff",
      "can_live": false,
      "status": "pending",
      "created_at": "2026-06-02 14:00:00"
    }
  ]
}
```

**`403 Forbidden` — người gọi chưa có shop:**

```json
{
  "Result": false, "StatusCode": "403",
  "StatusMess": "Bạn chưa có shop để quản lý cộng tác viên",
  "status": 403, "message": "Bạn chưa có shop để quản lý cộng tác viên", "data": null
}
```

#### b) `POST /api/live/members` — cấp quyền cho CTV / nhân viên

**Request:**

```json
{
  "identifier": "ctv.b@example.com",
  "member_type": "collaborator",
  "can_live": true,
  "status": "approved"
}
```

| Field | Kiểu | Bắt buộc | Mặc định | Ghi chú |
|-------|------|----------|----------|---------|
| `identifier` | string | **Có** | — | Email (chứa `@`) hoặc SĐT của người được cấp |
| `member_type` | string | Không | `collaborator` | Khác `staff`/`collaborator` → ép về `collaborator` |
| `can_live` | bool | Không | `true` | |
| `status` | string | Không | `approved` | Chủ shop tự duyệt nên mặc định approved |

**`200 OK`** — `StatusMess = "Đã cấp quyền livestream"`, `data` là `ShopMember`:

```json
{
  "Result": true, "StatusCode": "200", "StatusMess": "Đã cấp quyền livestream",
  "status": 200, "message": "Đã cấp quyền livestream",
  "data": {
    "user_id": 88,
    "full_name": "Trần Thị B",
    "email": "ctv.b@example.com",
    "so_dien_thoai": "0912345678",
    "member_type": "collaborator",
    "can_live": true,
    "status": "approved",
    "approved_at": "2026-06-03 10:15:00",
    "created_at": "2026-06-03 10:15:00"
  }
}
```

**`404 Not Found` — không tìm thấy người dùng theo email/SĐT:**

```json
{
  "Result": false, "StatusCode": "404",
  "StatusMess": "Không tìm thấy người dùng với email/SĐT này",
  "status": 404, "message": "Không tìm thấy người dùng với email/SĐT này", "data": null
}
```

**`400 Bad Request` — tự thêm chính mình:**

```json
{
  "Result": false, "StatusCode": "400",
  "StatusMess": "Bạn là chủ shop, không cần thêm chính mình",
  "status": 400, "message": "Bạn là chủ shop, không cần thêm chính mình", "data": null
}
```

(Thiếu `identifier` → `400` với message binding của Gin.)

#### c) `PATCH /api/live/members/:userSeq` — duyệt / tắt / bật

`:userSeq` = `user_id` (profiles.seq). Bỏ field nào thì **giữ nguyên giá trị
hiện tại** của thành viên.

**Request — duyệt + cho live:**

```json
{ "status": "approved", "can_live": true }
```

**Request — thu hồi tạm (giữ thành viên, cấm live):**

```json
{ "can_live": false }
```

**`200 OK` — `data` là `ShopMember` sau cập nhật:**

```json
{
  "Result": true, "StatusCode": "200", "StatusMess": "Success",
  "status": 200, "message": "Success",
  "data": {
    "user_id": 88, "full_name": "Trần Thị B", "email": "ctv.b@example.com",
    "so_dien_thoai": "0912345678", "member_type": "collaborator",
    "can_live": false, "status": "approved",
    "approved_at": "2026-06-03 10:15:00", "created_at": "2026-06-03 10:15:00"
  }
}
```

**`404 Not Found` — thành viên không thuộc shop của bạn:**

```json
{
  "Result": false, "StatusCode": "404",
  "StatusMess": "Thành viên không thuộc shop của bạn",
  "status": 404, "message": "Thành viên không thuộc shop của bạn", "data": null
}
```

**`400 Bad Request` — `userSeq` không phải số:**

```json
{
  "Result": false, "StatusCode": "400", "StatusMess": "userSeq không hợp lệ",
  "status": 400, "message": "userSeq không hợp lệ", "data": null
}
```

#### d) `DELETE /api/live/members/:userSeq` — gỡ hẳn thành viên

**`204 No Content`** — xóa thành công, **không có body** (envelope bỏ qua
204). App coi 2xx là thành công.

**`404 Not Found` — không có bản ghi để xóa:**

```json
{
  "Result": false, "StatusCode": "404",
  "StatusMess": "Thành viên không thuộc shop của bạn",
  "status": 404, "message": "Thành viên không thuộc shop của bạn", "data": null
}
```

### 15.6. Lỗi quyền sở hữu phiên — `403 NOT_STREAM_OWNER`

Với thao tác host trên **phiên cụ thể** (`/streams/:id/end`, `/pin`,
products, coupons…), sau khi qua `liveGate` handler còn check chủ phiên.
Không phải phiên của mình → **403** (cố ý 403, không phải 404):

```json
{
  "Result": false, "StatusCode": "403",
  "StatusMess": "Bạn không phải chủ phiên live này",
  "status": 403, "message": "Bạn không phải chủ phiên live này", "data": null
}
```

> Tương phản với tài nguyên gắn chủ khác (đơn hàng, sản phẩm, shop, ảnh) —
> mặc định trả **404** để không lộ sự tồn tại (xem ghi chú BOLA mục 12.4).

---

## 16. Tham chiếu code

| Việc | File |
|------|------|
| Đăng ký middleware + toàn bộ route | [backend/cmd/api/main.go](../backend/cmd/api/main.go) |
| `authMw`, `sellerMw`, `adminMw`, role | [backend/internal/auth/middleware.go](../backend/internal/auth/middleware.go) |
| `liveGate` (`RequireLivePermission`) + `/members` + `/can-live` | [backend/internal/live/member_handler.go](../backend/internal/live/member_handler.go) |
| Bộ spec mobile (start/stop/my/list/watch/chat/gift) | [backend/internal/live/spec_handler.go](../backend/internal/live/spec_handler.go) |
| Bộ legacy `/streams` | [backend/internal/live/handler.go](../backend/internal/live/handler.go) |
| Quyền + truy vấn `shop_live_permissions` | [backend/internal/live/shop_member_repo.go](../backend/internal/live/shop_member_repo.go) |
| AI endpoints (suggestions/reply/analyze) | [backend/internal/live/ai_handler.go](../backend/internal/live/ai_handler.go) |
| Bảng phân quyền gốc (nguồn tham chiếu) | [docs/ROLES.md](ROLES.md) |
