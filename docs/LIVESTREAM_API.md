# Livestream API — Tài liệu Mobile App

Tài liệu chính thức cho dev làm app **Host (phát live)** và **Viewer (xem live, chat, tặng quà)**.

---

## 1. Base URL & Envelope

**Production (ví dụ):**

```
https://tropia.thienhaisoft.com/index.php?r=api/{endpoint}
```

**Pretty URL (nếu server bật):**

```
https://tropia.thienhaisoft.com/api/{endpoint}
```

**Content-Type:** `application/json` (POST body).

### Envelope chuẩn (mọi API trừ SRS webhook)

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
| `StatusCode` | string | `"200"`, `"400"`, `"401"`, `"404"`, `"500"` |
| `StatusMess` | string | Message tiếng Việt |
| `status` | number | HTTP status số |
| `message` | string | Trùng `StatusMess` |
| `data` | object \| array \| null | Payload |

**Lỗi ví dụ:**

```json
{
  "Result": false,
  "StatusCode": "401",
  "StatusMess": "Thiếu Authorization token",
  "status": 401,
  "message": "Thiếu Authorization token",
  "data": null
}
```

---

## 2. Xác thực (JWT User)

Các API **Host / Chat / Gift** yêu cầu header:

```http
Authorization: Bearer {access_token}
```

Token lấy từ đăng nhập app:

### `POST /api/login`

**Request:**

```json
{
  "username": "0901234567",
  "password": "your_password"
}
```

**Response thành công:**

```json
{
  "Result": true,
  "StatusCode": "200",
  "StatusMess": "Đăng nhập thành công",
  "status": 200,
  "message": "Đăng nhập thành công",
  "data": {
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
}
```

- Lưu `data.token` — dùng cho mọi API live có JWT.
- `expires` = Unix timestamp hết hạn (mặc định ~12h).

---

## 3. Hạ tầng stream (SRS)

| Mục | Giá trị |
|-----|---------|
| RTMP server | `rtmp://103.147.186.97/live` |
| HLS playback | `http://103.147.186.97:8080/live/{stream_key}.m3u8` |
| App SRS | `live` |

**Trạng thái phiên (`status`):**

| Value | Ý nghĩa | App |
|-------|---------|-----|
| `ready` | Đã tạo phiên, chờ push RTMP | Host: bắt đầu encoder |
| `live` | Đang phát (SRS đã on_publish) | Viewer: xem HLS + chat |
| `offline` | Đã dừng | Không push / không xem |

---

## 4. Luồng tổng thể (Mobile)

```
[Host]
  Login → POST live/start → nhận rtmp_url + publish_token
       → Push RTMP (Larix/OBS/SDK) bằng rtmp_url
       → status chuyển live (SRS webhook)
       → POST live/stop khi kết thúc

[Viewer]
  GET live/list hoặc deep link stream_key
       → GET live/watch → hls_url + host info
       → Phát HLS (ExoPlayer / AVPlayer / HLS.js)
       → Poll GET live/chat/history mỗi 3–5s (hoặc WebSocket + Redis)
       → GET live/gifts → POST live/gift/send
```

---

## 5. API Host (phát live)

### 5.1 `POST /api/live/start`

Tạo phiên mới. Đóng phiên `ready`/`live` cũ của cùng user.

| | |
|--|--|
| **Auth** | Bearer JWT (bắt buộc) |
| **Body** | Optional |

**Request:**

```json
{
  "title": "Live sale sáng 31/5"
}
```

| Field | Kiểu | Bắt buộc | Mô tả |
|-------|------|----------|--------|
| `title` | string | Không | Tiêu đề hiển thị viewer |

**Response `data` thành công:**

```json
{
  "id": 15,
  "session_id": "2b1c4d5e-6f70-4812-9a3b-4c5d6e7f8091",
  "stream_key": "user_12_1748678400",
  "publish_token": "xK9mP2vL8nQ4wR7sT1uY3zA5bC6dE8fG0hJ2kL4mN6pQ8rS0tU2vW4xY6zA8bC0dE2f",
  "publish_token_expires_at": "2026-05-31 14:00:00",
  "rtmp_url": "rtmp://103.147.186.97/live/user_12_1748678400?token=xK9mP2vL8nQ4wR7sT1uY3zA5bC6dE8fG0hJ2kL4mN6pQ8rS0tU2vW4xY6zA8bC0dE2f",
  "rtmp_base": "rtmp://103.147.186.97/live",
  "hls_url": "http://103.147.186.97:8080/live/user_12_1748678400.m3u8",
  "status": "ready",
  "title": "Live sale sáng 31/5",
  "created_at": "2026-05-31 12:00:00"
}
```

| Field | Mô tả |
|-------|--------|
| `session_id` | UUID phiên live — dùng cho **Coupon API** (`/api/live/streams/{session_id}/coupons`) |
| `stream_key` | Tên stream trên SRS |
| `publish_token` | Token chống push giả — **bắt buộc** trong URL RTMP |
| `publish_token_expires_at` | Hết hạn token (mặc định +2h) |
| `rtmp_url` | **Dùng nguyên URL này** cho encoder (đã có `?token=`) |
| `rtmp_base` | Server RTMP không key (tham khảo) |
| `hls_url` | Link xem sau khi `status = live` |
| `status` | `ready` — chưa lên sóng |

**RTMP (khuyến nghị):** push full `rtmp_url`.

**Tách OBS/Larix (nếu cần):**

- Server: `rtmp_base` → `rtmp://103.147.186.97/live`
- Stream key: `{stream_key}?token={publish_token}`

**Lỗi thường gặp:**

```json
{
  "Result": false,
  "StatusCode": "401",
  "StatusMess": "Token hết hạn hoặc không hợp lệ",
  "status": 401,
  "message": "Token hết hạn hoặc không hợp lệ",
  "data": null
}
```

---

### 5.2 `POST /api/live/stop`

Dừng phiên đang mở của user (revoke publish token).

| | |
|--|--|
| **Auth** | Bearer JWT |
| **Body** | Không (hoặc `{}`) |

**Response `data`:**

```json
{
  "success": true,
  "stream_key": "user_12_1748678400",
  "ended_at": "2026-05-31 12:45:00"
}
```

**Không có phiên mở:**

```json
{
  "success": true,
  "message": "Không có phiên live đang mở"
}
```

---

### 5.3 `GET /api/live/my`

Phiên `ready` hoặc `live` hiện tại của user đăng nhập.

| | |
|--|--|
| **Auth** | Bearer JWT |
| **Query** | Không |

**Có phiên — `data`:**

```json
{
  "id": 15,
  "stream_key": "user_12_1748678400",
  "rtmp_url": "rtmp://103.147.186.97/live/user_12_1748678400?token=...",
  "hls_url": "http://103.147.186.97:8080/live/user_12_1748678400.m3u8",
  "publish_token": "xK9mP2vL8nQ4...",
  "publish_token_expires_at": "2026-05-31 14:00:00",
  "status": "live",
  "title": "Live sale sáng 31/5",
  "started_at": "2026-05-31 12:05:00"
}
```

**Không có phiên:**

```json
{
  "Result": true,
  "StatusCode": "200",
  "StatusMess": "Không có phiên live",
  "status": 200,
  "message": "Không có phiên live",
  "data": null
}
```

---

## 6. API Viewer (xem live)

### 6.1 `GET /api/live/list`

Danh sách stream đang `live`.

| | |
|--|--|
| **Auth** | Không |
| **Query** | `limit` (optional, default 20, max 50) |

**Request:**

```
GET /api/live/list?limit=20
```

**Response `data`:**

```json
{
  "items": [
    {
      "stream_key": "user_12_1748678400",
      "hls_url": "http://103.147.186.97:8080/live/user_12_1748678400.m3u8",
      "status": "live",
      "title": "Live sale sáng 31/5",
      "started_at": "2026-05-31 12:05:00",
      "viewer_count": 128,
      "host": {
        "id": 12,
        "username": "0901234567",
        "full_name": "Nguyễn Văn A",
        "avatar": "uploads/avatars/12.jpg"
      }
    }
  ]
}
```

| Field | Mô tả |
|-------|--------|
| `viewer_count` | Số viewer (cập nhật manual/cron — có thể 0) |
| `host.avatar` | Relative hoặc full URL — app ghép `baseUrl` nếu cần |

**Danh sách rỗng:**

```json
{
  "items": []
}
```

---

### 6.2 `GET /api/live/watch`

Chi tiết 1 stream để vào màn xem.

| | |
|--|--|
| **Auth** | Không |
| **Query** | `stream_key` (bắt buộc) |

**Request:**

```
GET /api/live/watch?stream_key=user_12_1748678400
```

**Response `data` thành công:**

```json
{
  "stream_key": "user_12_1748678400",
  "hls_url": "http://103.147.186.97:8080/live/user_12_1748678400.m3u8",
  "status": "live",
  "title": "Live sale sáng 31/5",
  "started_at": "2026-05-31 12:05:00",
  "viewer_count": 128,
  "host": {
    "id": 12,
    "username": "0901234567",
    "full_name": "Nguyễn Văn A",
    "avatar": "uploads/avatars/12.jpg"
  }
}
```

**Không live / không tồn tại (404):**

```json
{
  "Result": false,
  "StatusCode": "404",
  "StatusMess": "Stream không live hoặc không tồn tại",
  "status": 404,
  "message": "Stream không live hoặc không tồn tại",
  "data": null
}
```

**App:** chỉ play HLS khi `status === "live"`. Nếu `ready` → hiển thị "Chờ host lên sóng".

---

## 7. API Chat

### 7.1 `POST /api/live/chat/send`

| | |
|--|--|
| **Auth** | Bearer JWT |
| **Rate limit** | ~8 tin / 3 giây / user / room |

**Request:**

```json
{
  "stream_key": "user_12_1748678400",
  "message": "Shop ơi giá bao nhiêu?"
}
```

| Field | Kiểu | Bắt buộc | Max |
|-------|------|----------|-----|
| `stream_key` | string | Có | — |
| `message` | string | Có | 500 ký tự |

**Response `data` (tin vừa gửi):**

```json
{
  "id": 1001,
  "stream_key": "user_12_1748678400",
  "user_id": 99,
  "message": "Shop ơi giá bao nhiêu?",
  "message_type": "text",
  "gift_id": null,
  "display_name": "Trần Thị B",
  "avatar": "",
  "meta": {
    "display_name": "Trần Thị B",
    "avatar": ""
  },
  "created_at": "2026-05-31 12:10:05"
}
```

| `message_type` | Mô tả |
|----------------|--------|
| `text` | Chat thường |
| `gift` | Tin hệ thống khi tặng quà |
| `system` | Thông báo hệ thống |

**Lỗi:**

```json
{
  "Result": false,
  "StatusCode": "400",
  "StatusMess": "Phiên live không tồn tại hoặc đã kết thúc",
  "status": 400,
  "message": "Phiên live không tồn tại hoặc đã kết thúc",
  "data": null
}
```

```json
{
  "Result": false,
  "StatusCode": "400",
  "StatusMess": "Gửi tin quá nhanh, vui lòng thử lại",
  "status": 400,
  "message": "Gửi tin quá nhanh, vui lòng thử lại",
  "data": null
}
```

---

### 7.2 `GET /api/live/chat/history`

Lịch sử chat (poll realtime nếu chưa có WebSocket).

| | |
|--|--|
| **Auth** | Không |
| **Query** | Xem bảng dưới |

| Query | Kiểu | Default | Mô tả |
|-------|------|---------|--------|
| `stream_key` | string | — | Bắt buộc |
| `limit` | int | 50 | Max 100 |
| `before_id` | int | 0 | Phân trang: lấy tin có `id < before_id` |

**Request:**

```
GET /api/live/chat/history?stream_key=user_12_1748678400&limit=50&before_id=0
```

**Response `data`:**

```json
{
  "stream_key": "user_12_1748678400",
  "items": [
    {
      "id": 998,
      "stream_key": "user_12_1748678400",
      "user_id": 12,
      "message": "Chào mọi người!",
      "message_type": "text",
      "gift_id": null,
      "display_name": "Nguyễn Văn A",
      "avatar": "uploads/avatars/12.jpg",
      "meta": {
        "display_name": "Nguyễn Văn A",
        "avatar": "uploads/avatars/12.jpg"
      },
      "created_at": "2026-05-31 12:05:10"
    },
    {
      "id": 999,
      "stream_key": "user_12_1748678400",
      "user_id": 88,
      "message": "Trần Thị B tặng 2x Hoa hồng",
      "message_type": "gift",
      "gift_id": 1,
      "display_name": "Trần Thị B",
      "avatar": "",
      "meta": {
        "display_name": "Trần Thị B",
        "avatar": "",
        "gift": {
          "id": 50,
          "stream_key": "user_12_1748678400",
          "sender_user_id": 88,
          "sender_name": "Trần Thị B",
          "gift_id": 1,
          "gift_code": "rose",
          "gift_name": "Hoa hồng",
          "quantity": 2,
          "total_points": 20,
          "display_value": 20
        }
      },
      "created_at": "2026-05-31 12:08:00"
    }
  ],
  "redis_channel": "live:room:user_121748678400",
  "redis_enabled": false
}
```

- `items`: sắp xếp **cũ → mới** (ASC theo thời gian).
- Poll: gọi lại mỗi 3–5s; hoặc dùng `before_id` = `id` tin cũ nhất để load thêm.
- `redis_enabled: true` → team WS subscribe `redis_channel` (Phase sau).

---

## 8. API Gift (tặng quà)

Điểm trừ từ bảng `user_loyalty.points` (cùng hệ thống tích điểm app).

### 8.1 `GET /api/live/gifts`

Danh mục quà.

| | |
|--|--|
| **Auth** | Không |

**Response `data`:**

```json
{
  "items": [
    {
      "id": 1,
      "code": "rose",
      "name": "Hoa hồng",
      "icon_url": null,
      "point_cost": 10,
      "display_value": 10
    },
    {
      "id": 2,
      "code": "heart",
      "name": "Trái tim",
      "icon_url": null,
      "point_cost": 50,
      "display_value": 50
    },
    {
      "id": 3,
      "code": "star",
      "name": "Ngôi sao",
      "icon_url": null,
      "point_cost": 100,
      "display_value": 100
    },
    {
      "id": 4,
      "code": "rocket",
      "name": "Tên lửa",
      "icon_url": null,
      "point_cost": 500,
      "display_value": 500
    },
    {
      "id": 5,
      "code": "crown",
      "name": "Vương miện",
      "icon_url": null,
      "point_cost": 1000,
      "display_value": 1000
    }
  ]
}
```

| Field | Mô tả |
|-------|--------|
| `point_cost` | Điểm loyalty trừ mỗi 1 quà |
| `display_value` | Giá trị hiển thị UI (animation tier) |

---

### 8.2 `POST /api/live/gift/send`

| | |
|--|--|
| **Auth** | Bearer JWT |
| **Điều kiện** | Stream `status = live`; không tự tặng host |

**Request:**

```json
{
  "stream_key": "user_12_1748678400",
  "gift_id": 1,
  "quantity": 2
}
```

| Field | Kiểu | Bắt buộc | Ghi chú |
|-------|------|----------|---------|
| `stream_key` | string | Có | |
| `gift_id` | int | Có | Từ `live/gifts` |
| `quantity` | int | Không | Default 1, max 99 |

**Response `data` thành công:**

```json
{
  "gift": {
    "id": 50,
    "stream_key": "user_12_1748678400",
    "sender_user_id": 99,
    "sender_name": "Trần Thị B",
    "sender_avatar": "",
    "gift_id": 1,
    "gift_code": "rose",
    "gift_name": "Hoa hồng",
    "gift_icon_url": null,
    "quantity": 2,
    "total_points": 20,
    "display_value": 20,
    "created_at": "2026-05-31 12:10:30"
  },
  "points_remaining": 480,
  "redis_channel": "live:room:user_121748678400"
}
```

| Field | Mô tả |
|-------|--------|
| `total_points` | `point_cost * quantity` đã trừ |
| `points_remaining` | Điểm loyalty còn lại sau tặng |
| `display_value` | `display_value_catalog * quantity` — dùng animation |

**Lỗi:**

```json
{
  "Result": false,
  "StatusCode": "400",
  "StatusMess": "Chỉ tặng quà khi stream đang live",
  "status": 400,
  "message": "Chỉ tặng quà khi stream đang live",
  "data": null
}
```

```json
{
  "Result": false,
  "StatusCode": "400",
  "StatusMess": "Không đủ điểm. Cần 20 điểm.",
  "status": 400,
  "message": "Không đủ điểm. Cần 20 điểm.",
  "data": null
}
```

```json
{
  "Result": false,
  "StatusCode": "400",
  "StatusMess": "Không thể tự tặng quà cho chính mình",
  "status": 400,
  "message": "Không thể tự tặng quà cho chính mình",
  "data": null
}
```

```json
{
  "Result": false,
  "StatusCode": "400",
  "StatusMess": "Bạn chưa có điểm tích lũy",
  "status": 400,
  "message": "Bạn chưa có điểm tích lũy",
  "data": null
}
```

---

### 8.3 `GET /api/live/gifts/recent`

Quà vừa tặng trên stream (hiệu ứng overlay).

| | |
|--|--|
| **Auth** | Không |
| **Query** | `stream_key` (bắt buộc), `limit` (optional, default 30) |

**Request:**

```
GET /api/live/gifts/recent?stream_key=user_12_1748678400&limit=30
```

**Response `data`:**

```json
{
  "stream_key": "user_12_1748678400",
  "items": [
    {
      "id": 50,
      "sender_user_id": 99,
      "sender_name": "Trần Thị B",
      "sender_avatar": "",
      "gift_id": 1,
      "gift_code": "rose",
      "gift_name": "Hoa hồng",
      "gift_icon_url": null,
      "quantity": 2,
      "total_points": 20,
      "display_value": 20,
      "created_at": "2026-05-31 12:10:30"
    }
  ]
}
```

- `items`: **mới nhất trước** (DESC).
- Poll overlay: 2–3s khi chưa có WS.

---

## 9. Redis realtime (tùy chọn)

Khi server bật `redis.enabled = true`, backend `PUBLISH` channel:

```
live:room:{stream_key_sanitized}
```

**Message JSON (WebSocket server forward cho app):**

```json
{
  "type": "chat",
  "stream_key": "user_12_1748678400",
  "ts": 1748678430,
  "data": {
    "id": 1001,
    "user_id": 99,
    "message": "Hello",
    "message_type": "text",
    "display_name": "Trần Thị B",
    "created_at": "2026-05-31 12:10:05"
  }
}
```

```json
{
  "type": "gift",
  "stream_key": "user_12_1748678400",
  "ts": 1748678430,
  "data": {
    "id": 50,
    "sender_user_id": 99,
    "sender_name": "Trần Thị B",
    "gift_code": "rose",
    "gift_name": "Hoa hồng",
    "quantity": 2,
    "display_value": 20
  }
}
```

**Mobile Phase 1:** không cần WS — poll `chat/history` + `gifts/recent`.

---

## 10. Bảng endpoint nhanh

| # | Method | Endpoint | Auth | Màn app |
|---|--------|----------|------|---------|
| 1 | POST | `login` | — | Đăng nhập |
| 2 | POST | `live/start` | JWT | Host: bắt đầu live |
| 3 | POST | `live/stop` | JWT | Host: kết thúc |
| 4 | GET | `live/my` | JWT | Host: tiếp tục phiên |
| 5 | GET | `live/list` | — | Tab live / discovery |
| 6 | GET | `live/watch` | — | Player + room info |
| 7 | POST | `live/chat/send` | JWT | Gửi chat |
| 8 | GET | `live/chat/history` | — | Danh sách chat |
| 9 | GET | `live/gifts` | — | Chọn quà |
| 10 | POST | `live/gift/send` | JWT | Tặng quà |
| 11 | GET | `live/gifts/recent` | — | Overlay quà |

*(Endpoint SRS `live/validate`, `live/on-publish`, `live/on-unpublish` — server SRS gọi, app không gọi.)*

---

## 11. Phát HLS trên app

**URL:** `data.hls_url` từ `live/watch` hoặc `live/list`.

| Platform | Gợi ý |
|----------|--------|
| Android | ExoPlayer + HLS |
| iOS | AVPlayer / `AVPlayerItem(url: hlsUrl)` |
| Flutter | `video_player` + hls hoặc `better_player` |

**Lưu ý:** HTTP cleartext — Android cần `usesCleartextTraffic` hoặc CDN HTTPS sau này.

---

## 12. Checklist tích hợp dev

- [ ] Lưu JWT sau login
- [ ] Host: `live/start` → push `rtmp_url` (có token)
- [ ] Host: `live/stop` khi thoát
- [ ] Viewer: `live/watch` → play khi `status == live`
- [ ] Chat: `chat/send` + poll `chat/history`
- [ ] Gift: `gifts` → `gift/send`, overlay từ `gifts/recent`
- [ ] Coupon: lưu `session_id` → tạo/announce coupon (`COUPON_API.md`)
- [ ] Checkout: `coupons/validate` (camelCase)
- [ ] Xử lý envelope `Result === false` + hiển thị `StatusMess`
- [ ] Không gọi API SRS webhook từ app

---

## 13. Coupon API (live + checkout)

Xem chi tiết JSON: **[COUPON_API.md](COUPON_API.md)** — validate mã, coupon session live, coupon toàn sàn/shop.

---

## 14. Tham chiếu backend

- Schema: `migrations/live_stream_table.sql`, `migrations/live_stream_phase3.sql`, `migrations/live_coupon_tables.sql`
- Ops: `docs/LIVESTREAM_BACKEND.md`

**Liên hệ backend** khi đổi domain / CDN / bật Redis WS.

---
---

# Phần B — Go backend (`/api/live/streams/*`)

App Flutter trong repo dùng bộ API này (đầy đủ hơn Phần A). Cùng envelope §1.
Base = `{BACKEND_URL}` (dev `http://localhost:3000`). `:id` = **`session_id` (UUID)**.

> **Lưu ý lỗi:** handler `/streams/*` validate sai định dạng → **HTTP 422**
> (`message` tiếng Anh: `invalid id`, `session not found`, `not the owner`).
> Quyền live = admin / chủ shop / member `can_live`; thiếu → 403.

## B1. Bảng endpoint

| Method | Endpoint | Auth | Mô tả |
|--------|----------|------|--------|
| GET | `/api/live/streams` | — | DS phiên live (cursor) |
| GET | `/api/live/streams/:id` | — | Chi tiết 1 phiên |
| GET | `/api/live/streams/:id/stats` | — | Counter realtime |
| GET | `/api/live/streams/:id/products` | — | Sản phẩm trong phiên |
| GET | `/api/live/streams/:id/playback` | — | URL phát (HLS/FLV/WHEP) |
| GET | `/api/live/streams/:id/chat` | — | Lịch sử chat |
| GET | `/api/live/streams/:id/coupons` | — | Coupon của phiên |
| GET | `/api/live/streams/:id/timeline` | — | Timeline VOD replay |
| GET | `/api/live/streams/:id/hls/playlist.m3u8` · `/hls/s/*name` | — | HLS proxy |
| POST | `/api/live/streams/:id/like` | — | +1 like (60/phút/IP) |
| GET | `/api/live/streams/:id/ws/chat` | — | WS: chat + stats + coupon |
| GET | `/api/live/ws/list` | — | WS: list thay đổi |
| GET | `/api/live/replays` | JWT | Replay của chính mình |
| POST | `/api/live/streams/:id/join` · `/leave` | JWT | Vào/rời phòng |
| POST | `/api/live/streams/:id/chat` | JWT | Gửi chat (30/phút) |
| POST | `/api/live/streams/:id/track-cart-add` · `/track-follow` | JWT | Đếm giỏ / follow |
| POST | `/api/live/streams` | live | Tạo phiên (10/giờ) |
| POST | `/api/live/streams/:id/end` | live | Kết thúc |
| GET | `/api/live/streams/:id/publish` | live | Lấy lại URL push |
| PATCH | `/api/live/streams/:id/bot` | live | Bật/tắt bot AI |
| POST/PUT | `/api/live/streams/:id/products` | live | Thêm / thay sản phẩm |
| DELETE | `/api/live/streams/:id/products/:productId` | live | Gỡ sản phẩm |
| POST | `/api/live/streams/:id/pin` | live | Ghim "đang giới thiệu" |
| POST | `/api/live/streams/:id/coupons` | live | Tạo + announce coupon |
| POST | `/api/live/streams/:id/coupons/:couponId/announce` | live | Phát lại coupon |
| POST | `/api/live/streams/:id/chat/mute` · `/chat/unmute` | live | Khoá / mở chat |
| POST | `/api/live/streams/:id/ai-suggestions` · `/ai-reply` | JWT | Gợi ý / auto-reply |
| POST | `/api/live/streams/:id/analyze` | live | Sentiment + tips |
| GET | `/api/live/can-live` | JWT | Có được phát live? |
| GET/POST | `/api/live/members` | JWT | DS / cấp quyền CTV |
| PATCH/DELETE | `/api/live/members/:userSeq` | JWT | Sửa / gỡ CTV |
| POST | `/api/srs/on_publish`… | secret | SRS callback (app không gọi) |

---

## B2. Host

### B2.1 `POST /api/live/streams` — tạo phiên (live, 10/giờ)

**Request:**

```json
{
  "title": "Live sale rau củ sạch",
  "description": "Giảm tới 50% khung 20h",
  "cover_image_url": "https://cdn.tropia.vn/covers/abc.jpg",
  "category": "Thực phẩm tươi sống"
}
```

`title` bắt buộc (1–200). Còn lại optional.

**Response `data` (201):**

```json
{
  "session": {
    "id": "2b1c4d5e-6f70-4812-9a3b-4c5d6e7f8091",
    "seller_id": "9a1b2c3d-...",
    "title": "Live sale rau củ sạch",
    "description": "Giảm tới 50% khung 20h",
    "category": "Thực phẩm tươi sống",
    "stream_key": "live_7f3c0a9e...",
    "status": "scheduled",
    "started_at": "2026-06-07T12:00:00Z",
    "viewer_count": 0, "like_count": 0, "order_count": 0, "revenue": 0,
    "cart_add_count": 0, "follow_count": 0,
    "ai_bot_enabled": false, "pinned_product_id": null,
    "created_at": "2026-06-07T12:00:00Z"
  },
  "publish": {
    "rtmp": "rtmp://103.147.186.97:1935/live/live_7f3c0a9e...?expire=1717764000&sign=ab12...",
    "whip": "http://103.147.186.97:1985/rtc/v1/whip/?app=live&stream=live_7f3c0a9e...",
    "srt":  "srt://103.147.186.97:10080?streamid=%23!::r%3Dlive%2Flive_7f3c0a9e...%2Cm%3Dpublish"
  }
}
```

`session.id` = `session_id` cho mọi route `/streams/:id/*`. `stream_key` chỉ trả cho chủ phiên.

**Lỗi 403 (chưa cấp quyền live):**

```json
{ "Result": false, "StatusCode": "403", "StatusMess": "Tài khoản chưa được cấp quyền livestream. Liên hệ chủ shop để được duyệt.", "status": 403, "message": "...", "data": null }
```

**Lỗi 422 (thiếu title):**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "Key: 'createReq.Title' Error:Field validation for 'Title' failed on the 'required' tag", "status": 422, "message": "...", "data": null }
```

**Lỗi 401 (chưa đăng nhập):**

```json
{ "Result": false, "StatusCode": "401", "StatusMess": "missing Authorization header", "status": 401, "message": "missing Authorization header", "data": null }
```

**Lỗi 429 (vượt rate limit):**

```json
{ "Result": false, "StatusCode": "429", "StatusMess": "too many requests", "status": 429, "message": "too many requests", "data": null }
```

### B2.2 `POST /api/live/streams/:id/end` — kết thúc (live)

**Thành công 204:**

```json
{ "Result": true, "StatusCode": "204", "StatusMess": "Success", "status": 204, "message": "Success", "data": null }
```

**Lỗi:**

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "session not found", "status": 404, "message": "session not found", "data": null }
```
```json
{ "Result": false, "StatusCode": "403", "StatusMess": "not the owner", "status": 403, "message": "not the owner", "data": null }
```

### B2.3 `GET /api/live/streams/:id/publish` — lấy lại URL push (live)

**Response `data`:** `{ "session": { … }, "publish": { "rtmp": "…", "whip": "…", "srt": "…" } }`
(giống B2.1).

**Lỗi:**

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "session not found", "status": 404, "message": "session not found", "data": null }
```

```json
{ "Result": false, "StatusCode": "403", "StatusMess": "not the owner", "status": 403, "message": "not the owner", "data": null }
```

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "invalid id", "status": 422, "message": "invalid id", "data": null }
```

### B2.4 `PATCH /api/live/streams/:id/bot` — bật/tắt bot AI (live)

**Request:** `{ "enabled": true }` → **Response `data`:** `{ "ai_bot_enabled": true }`.

**Lỗi:**

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "session not found", "status": 404, "message": "session not found", "data": null }
```

```json
{ "Result": false, "StatusCode": "403", "StatusMess": "not the owner", "status": 403, "message": "not the owner", "data": null }
```

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "invalid id", "status": 422, "message": "invalid id", "data": null }
```

---

## B3. Viewer

### B3.1 `GET /api/live/streams?limit=50&cursor=` — DS phiên live

**Response `data`:**

```json
{
  "sessions": [
    {
      "id": "2b1c4d5e-...",
      "seller_id": "9a1b2c3d-...",
      "title": "Live sale rau củ sạch",
      "status": "live",
      "started_at": "2026-06-07T12:05:00Z",
      "viewer_count": 128, "like_count": 540, "order_count": 12, "revenue": 3500000,
      "cart_add_count": 30, "follow_count": 8,
      "ai_bot_enabled": true, "pinned_product_id": "aa11bb22-...",
      "seller_name": "Nông sản Đà Lạt", "seller_avatar": "https://cdn.tropia.vn/avatars/a.jpg",
      "shop_id": "cc33dd44-...", "shop_name": "Nông sản Đà Lạt", "shop_logo_url": "https://cdn.tropia.vn/logos/logo.jpg",
      "created_at": "2026-06-07T12:00:00Z",
      "playback_hls": "/api/live/streams/2b1c4d5e-.../hls/playlist.m3u8",
      "products": [ { "id": "aa11bb22-...", "product_name": "Cà chua bi", "sale_price": 25000, "is_pinned": true } ]
    }
  ],
  "next_cursor": "1717761900000:2b1c4d5e-..."
}
```

`next_cursor` = `null` khi hết trang (truyền lại vào `?cursor=`). `playback_hls` là path tương đối, không lộ `stream_key`.

**Lỗi 429 (scraper, > 600 req/10 phút):**

```json
{ "Result": false, "StatusCode": "429", "StatusMess": "too many requests — please slow down", "status": 429, "message": "...", "data": null }
```

### B3.2 `GET /api/live/streams/:id` — chi tiết

**Response `data`:** `{ "session": { … object session như B3.1, không kèm stream_key } }`.

**Lỗi:**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "invalid id", "status": 422, "message": "invalid id", "data": null }
```

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "session not found", "status": 404, "message": "session not found", "data": null }
```

### B3.3 `GET /api/live/streams/:id/playback` — URL phát

**Response `data`:**

```json
{
  "session": { "id": "2b1c4d5e-...", "status": "live" },
  "playback": {
    "hls":  "/api/live/streams/2b1c4d5e-.../hls/playlist.m3u8",
    "flv":  "http://103.147.186.97:8080/live/live_7f3c0a9e....flv?expire=...&sign=...",
    "whep": "http://103.147.186.97:1985/rtc/v1/whep/?app=live&stream=live_7f3c0a9e..."
  }
}
```

App phát `hls` (proxy, ẩn key).

**Lỗi:**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "invalid id", "status": 422, "message": "invalid id", "data": null }
```

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "session not found", "status": 404, "message": "session not found", "data": null }
```

### B3.4 HLS proxy `GET /streams/:id/hls/playlist.m3u8` & `/hls/s/*name`

Trả thẳng media (không envelope). Manifest `Content-Type: application/vnd.apple.mpegurl`,
segment `video/MP2T`. Vừa lên live, manifest tự poll SRS ~6s rồi trả; chưa sẵn → `404`.
Player chỉ cần `playback_hls`. **Lỗi:** route HLS trả **HTTP status thuần, KHÔNG
có body JSON** — `404` (session not found / stream not live), `422` (invalid id /
invalid segment), `500` (SRS upstream chết).

### B3.5 `GET /api/live/streams/:id/stats` — counter realtime

**Response `data`:**

```json
{ "viewer_count": 128, "like_count": 540, "order_count": 12, "revenue": 3500000, "cart_add_count": 30, "follow_count": 8, "status": "live", "pinned_product_id": "aa11bb22-..." }
```

**Lỗi:**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "invalid id", "status": 422, "message": "invalid id", "data": null }
```

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "session not found", "status": 404, "message": "session not found", "data": null }
```

### B3.6 Tracking (JWT) — đều trả `204`

| Endpoint | Tác dụng |
|----------|----------|
| `POST /streams/:id/join` · `/leave` | +/− viewer (host không tự đếm) |
| `POST /streams/:id/like` | +like (ẩn danh OK, 60/phút/IP) |
| `POST /streams/:id/track-cart-add` | +cart_add |
| `POST /streams/:id/track-follow` | +follow (dedupe theo user) |

```json
{ "Result": true, "StatusCode": "204", "StatusMess": "Success", "status": 204, "message": "Success", "data": null }
```

---

## B4. Sản phẩm

### B4.1 `GET /api/live/streams/:id/products`

**Response `data`:**

```json
{
  "products": [
    {
      "id": "aa11bb22-...",
      "session_id": "2b1c4d5e-...",
      "product_id": "p0010000-...",
      "product_name": "Cà chua bi 500g",
      "image_url": "https://cdn.tropia.vn/products/ca.jpg",
      "original_price": 35000, "sale_price": 25000, "discount_pct": 28.5,
      "stock_left": 40, "sold_count": 12, "unit": "hộp", "category": "Rau củ",
      "sort_order": 0, "is_pinned": true
    }
  ]
}
```

`id` = `live_session_products.id` (dùng cho pin/delete). `product_id` có thể `null`.

**Lỗi:**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "invalid id", "status": 422, "message": "invalid id", "data": null }
```

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "session not found", "status": 404, "message": "session not found", "data": null }
```

### B4.2 `POST` / `PUT /api/live/streams/:id/products` (live)

`POST` = thêm; `PUT` = thay toàn bộ (cho phép list rỗng để xoá hết).

**Request:**

```json
{
  "products": [
    {
      "product_id": "p0010000-...",
      "product_name": "Cà chua bi 500g",
      "image_url": "https://cdn.tropia.vn/products/ca.jpg",
      "original_price": 35000, "sale_price": 25000, "discount_pct": 28.5,
      "stock_left": 40, "unit": "hộp", "is_pinned": true
    }
  ]
}
```

`product_name` bắt buộc; `product_id` optional (`null` = ad-hoc).

**Response `data`:** `{ "products": [ … như B4.1 ] }`.

**Lỗi:**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "invalid id", "status": 422, "message": "invalid id", "data": null }
```

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "session not found", "status": 404, "message": "session not found", "data": null }
```

```json
{ "Result": false, "StatusCode": "403", "StatusMess": "not the owner", "status": 403, "message": "not the owner", "data": null }
```

### B4.3 `DELETE /api/live/streams/:id/products/:productId` (live)

`:productId` = `live_session_products.id`. **Thành công:** `204`.

**Lỗi:**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "invalid productId", "status": 422, "message": "invalid productId", "data": null }
```

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "session not found", "status": 404, "message": "session not found", "data": null }
```

```json
{ "Result": false, "StatusCode": "403", "StatusMess": "not the owner", "status": 403, "message": "not the owner", "data": null }
```

### B4.4 `POST /api/live/streams/:id/pin` (live) — "đang giới thiệu"

**Request (ghim):** `{ "product_id": "aa11bb22-..." }` · **Bỏ ghim:** `{ "product_id": null }` (hoặc body rỗng).

**Response `data`:** `{ "pinned_product_id": "aa11bb22-..." }`.

**Lỗi:**

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "product not in this session", "status": 404, "message": "product not in this session", "data": null }
```

**Lỗi khác:**

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "session not found", "status": 404, "message": "session not found", "data": null }
```

```json
{ "Result": false, "StatusCode": "403", "StatusMess": "not the owner", "status": 403, "message": "not the owner", "data": null }
```

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "invalid id", "status": 422, "message": "invalid id", "data": null }
```

---

## B5. Chat (REST + WebSocket)

### B5.1 `GET /api/live/streams/:id/chat?limit=50` — lịch sử (cũ→mới)

**Response `data`:**

```json
{
  "messages": [
    {
      "id": "m-uuid",
      "session_id": "2b1c4d5e-...",
      "user_id": "u-uuid",
      "username": "Trần Thị B",
      "avatar_url": "https://cdn.tropia.vn/avatars/b.jpg",
      "message": "Shop ơi còn hàng không?",
      "is_host": false,
      "type": "text",
      "created_at": "2026-06-07T12:10:05Z"
    }
  ]
}
```

`type`: `text` | `bot` | `bot_error` | `system`.

**Lỗi:**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "invalid id", "status": 422, "message": "invalid id", "data": null }
```

### B5.2 `POST /api/live/streams/:id/chat` (JWT, 30/phút)

**Request:** `{ "message": "Shop ơi còn hàng không?" }` (1–500 ký tự).

**Response `data` (201):** object ChatMessage như B5.1 (server tự gán `is_host`).

**Lỗi 404 (không tìm thấy phiên):**

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "session not found", "status": 404, "message": "session not found", "data": null }
```

**Lỗi 422 (dính cụm scam → auto-mute 60s):**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "tin nhắn chứa nội dung không được phép", "status": 422, "message": "...", "data": null }
```

**Lỗi 403 (đang bị mute — envelope rút `data: null`):**

```json
{ "Result": false, "StatusCode": "403", "StatusMess": "bạn đang bị tạm khoá chat", "status": 403, "message": "bạn đang bị tạm khoá chat", "data": null }
```

### B5.3 WebSocket `GET /api/live/streams/:id/ws/chat`

Server **chỉ push** (client vẫn `POST /chat` để gửi). Ping 30s. Các message:

```json
{ "type": "chat", "message": { "...": "ChatMessage như B5.1" } }
```
```json
{ "type": "stats", "viewer_count": 129, "like_count": 541, "order_count": 12, "cart_add_count": 30, "follow_count": 8, "status": "live", "pinned_product_id": "aa11bb22-..." }
```
```json
{ "type": "coupon_announce", "coupon": { "id": "f0f1f2f3-...", "code": "LIVE0607", "discount_type": "percent", "discount_value": 10, "min_order_value": 100000, "max_uses": 100, "expires_at": "2026-06-07T14:00:00Z" } }
```

### B5.4 WebSocket `GET /api/live/ws/list`

```json
{ "type": "list_change", "reason": "session_live" }
```

`reason`: `session_created` | `session_ended` | `session_live` | `session_offline` | `products_changed`.
Nhận được → re-fetch `/api/live/streams`.

### B5.5 `POST /api/live/streams/:id/chat/mute` · `/chat/unmute` (live)

**Mute request:** `{ "user_id": "u-uuid", "duration_seconds": 300, "reason": "spam" }`
(`duration_seconds` 10–86400).

**Response `data`:** `{ "user_id": "u-uuid", "muted_until": "2026-06-07T12:20:00Z" }`.

**Unmute request:** `{ "user_id": "u-uuid" }` → `204`.

**Lỗi:**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "cannot mute the host", "status": 422, "message": "cannot mute the host", "data": null }
```

**Lỗi khác:**

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "session not found", "status": 404, "message": "session not found", "data": null }
```

```json
{ "Result": false, "StatusCode": "403", "StatusMess": "not the host", "status": 403, "message": "not the host", "data": null }
```

---

## B6. Coupon trong phiên (host)

> Validate khi checkout / coupon sàn-shop: xem **[COUPON_API.md](COUPON_API.md)**.

### B6.1 `POST /api/live/streams/:id/coupons` — tạo + tự announce (live, chủ phiên)

**Request:**

```json
{
  "code": "LIVE0607",
  "discount_type": "percent",
  "discount_value": 10,
  "min_order_value": 100000,
  "max_uses": 100,
  "expires_at": "2026-06-07T14:00:00Z"
}
```

`code` 3–32 (tự uppercase); `discount_type` = `percent|fixed`; `max_uses` ≥ 1 bắt buộc; `expires_at` RFC3339.

**Response `data` (201):**

```json
{
  "coupon": {
    "id": "f0f1f2f3-...",
    "code": "LIVE0607",
    "discount_type": "percent", "discount_value": 10, "min_order_value": 100000,
    "max_discount": null, "max_uses": 100, "used_count": 0,
    "expires_at": "2026-06-07T14:00:00Z", "is_active": true,
    "session_id": "2b1c4d5e-...", "shop_id": null,
    "created_by": "9a1b2c3d-...", "created_at": "2026-06-07T12:30:00Z"
  }
}
```

**Lỗi:**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "expires_at must be RFC3339", "status": 422, "message": "expires_at must be RFC3339", "data": null }
```

**Lỗi khác:**

```json
{ "Result": false, "StatusCode": "403", "StatusMess": "not session owner", "status": 403, "message": "not session owner", "data": null }
```

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "session not found", "status": 404, "message": "session not found", "data": null }
```

### B6.2 `POST /api/live/streams/:id/coupons/:couponId/announce` (live)

Phát lại coupon → **thành công `204`**:

```json
{ "Result": true, "StatusCode": "204", "StatusMess": "Success", "status": 204, "message": "Success", "data": null }
```

**Lỗi:**

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "coupon not found in session", "status": 404, "message": "coupon not found in session", "data": null }
```

```json
{ "Result": false, "StatusCode": "403", "StatusMess": "not session owner", "status": 403, "message": "not session owner", "data": null }
```

### B6.3 `GET /api/live/streams/:id/coupons` (public)

**Response `data`:** `{ "coupons": [ { "id": "f0f1f2f3-...", "code": "LIVE0607", "discount_type": "percent", "discount_value": 10, "min_order_value": 100000, "max_uses": 100, "used_count": 3, "expires_at": "2026-06-07T14:00:00Z", "is_active": true } ] }`.

---

## B7. VOD replay

### B7.1 `GET /api/live/streams/:id/timeline` (public)

**Response `data`:**

```json
{
  "session_id": "2b1c4d5e-...",
  "started_at": "2026-06-07T12:05:00Z",
  "vod_mp4_url": "https://r2.tropia.vn/vod/2b1c4d5e.mp4",
  "duration_sec": 2400,
  "entries": [
    { "t": 0,      "type": "chat",           "payload": { "id": "m-uuid", "username": "Trần Thị B", "avatar_url": "...", "message": "Chào shop", "is_host": false, "type": "text" } },
    { "t": 35000,  "type": "product_pin",    "payload": { "product_id": "aa11bb22-...", "product_name": "Cà chua bi", "image_url": "...", "sale_price": 25000 } },
    { "t": 90000,  "type": "bot_toggle",     "payload": { "enabled": true } },
    { "t": 120000, "type": "coupon_publish", "payload": { "coupon_id": "f0f1f2f3-...", "code": "LIVE0607", "discount_type": "percent", "discount_value": 10 } },
    { "t": 150000, "type": "product_unpin",  "payload": {} },
    { "t": 180000, "type": "gift",           "payload": { "sender_name": "Trần Thị B", "gift_name": "Hoa hồng", "gift_code": "rose", "quantity": 2 } }
  ]
}
```

`t` = offset (ms) so với `started_at`. `vod_mp4_url` `null` nếu chưa bake; `duration_sec` `0` khi còn live.

**Lỗi:**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "invalid id", "status": 422, "message": "invalid id", "data": null }
```

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "session not found", "status": 404, "message": "session not found", "data": null }
```

### B7.2 `GET /api/live/replays?limit=30&offset=0` (JWT)

Replay đã ghi của chính mình. **Response `data`:** `{ "sessions": [ … object session đã ended kèm vod_mp4_url ] }`.

---

## B8. AI (DeepSeek)

### B8.1 `POST /api/live/streams/:id/ai-suggestions` (JWT)

**Request (optional):** `{ "product_name": "Cà chua bi", "category": "Rau củ", "recent_comments": ["giá sao shop"] }`

**Response `data`:**

```json
{ "suggestions": ["Cà chua bi giá bao nhiêu shop?", "Có ship tỉnh không ạ?", "Bảo quản được mấy ngày?", "Còn size 1kg không shop?"] }
```

**Lỗi:**

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "session not found", "status": 404, "message": "session not found", "data": null }
```

```json
{ "Result": false, "StatusCode": "500", "StatusMess": "ai suggestions", "status": 500, "message": "ai suggestions", "data": null }
```

### B8.2 `POST /api/live/streams/:id/ai-reply` (JWT)

**Request:** `{ "question": "Cà chua này hữu cơ không shop?", "product_name": "Cà chua bi", "category": "Rau củ" }` (`question` bắt buộc).

**Response `data`:** `{ "reply": "Dạ cà chua bi nhà em trồng hữu cơ, có giấy chứng nhận ạ!" }`.

**Lỗi:**

```json
{ "Result": false, "StatusCode": "422", "StatusMess": "Key: 'aiReplyReq.Question' Error:Field validation for 'Question' failed on the 'required' tag", "status": 422, "message": "...", "data": null }
```

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "session not found", "status": 404, "message": "session not found", "data": null }
```

```json
{ "Result": false, "StatusCode": "500", "StatusMess": "ai reply", "status": 500, "message": "ai reply", "data": null }
```

### B8.3 `POST /api/live/streams/:id/analyze` (live, no body)

**Response `data`:**

```json
{
  "sentiment": "tích cực",
  "summary": "Phiên thu hút tốt, tương tác cao quanh sản phẩm cà chua.",
  "tips": ["Ghim thêm combo", "Phát coupon phút cao điểm", "Trả lời nhanh câu hỏi ship", "Nhắc số lượng còn để tạo khan hiếm"]
}
```

`sentiment` ∈ `tích cực|trung bình|cần cải thiện`.

**Lỗi:**

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "session not found", "status": 404, "message": "session not found", "data": null }
```

```json
{ "Result": false, "StatusCode": "403", "StatusMess": "Tài khoản chưa được cấp quyền livestream. Liên hệ chủ shop để được duyệt.", "status": 403, "message": "...", "data": null }
```

```json
{ "Result": false, "StatusCode": "500", "StatusMess": "ai analyze", "status": 500, "message": "ai analyze", "data": null }
```

---

## B9. Quản lý cộng tác viên (chủ shop)

> Lỗi nghiệp vụ ở đây dùng **HTTP 400** (không phải 422). Không có shop → `403`.

### B9.1 `GET /api/live/can-live` (JWT)

**Response `data`:** `{ "can_live": true, "is_admin": false, "shop_id": "cc33dd44-..." }`
(admin → `is_admin:true, shop_id:null`; không được phép → `can_live:false`).

### B9.2 `GET /api/live/members` (chủ shop)

**Response `data`:**

```json
{
  "items": [
    {
      "user_id": 42,
      "full_name": "Nguyễn Văn C",
      "email": "c@example.com",
      "so_dien_thoai": "0907654321",
      "member_type": "collaborator",
      "can_live": true,
      "status": "approved",
      "approved_at": "2026-06-07T10:00:00Z",
      "created_at": "2026-06-07T09:55:00Z"
    }
  ]
}
```

`user_id` = seq số nguyên (chính là `:userSeq`).

**Lỗi 403:**

```json
{ "Result": false, "StatusCode": "403", "StatusMess": "Bạn chưa có shop để quản lý cộng tác viên", "status": 403, "message": "...", "data": null }
```

### B9.3 `POST /api/live/members` — cấp quyền (chủ shop)

**Request:** `{ "identifier": "0901234567", "member_type": "collaborator", "can_live": true, "status": "approved" }`

`identifier` = email/SĐT (bắt buộc); `member_type` = `staff|collaborator` (mặc định collaborator); `status` mặc định `approved`.

**Response `data`:** object ShopMember như B9.2 (StatusMess `"Đã cấp quyền livestream"`).

**Lỗi:**

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "Không tìm thấy người dùng với email/SĐT này", "status": 404, "message": "...", "data": null }
```
```json
{ "Result": false, "StatusCode": "400", "StatusMess": "Bạn là chủ shop, không cần thêm chính mình", "status": 400, "message": "...", "data": null }
```

### B9.4 `PATCH` / `DELETE /api/live/members/:userSeq` (chủ shop)

`:userSeq` = `user_id` ở B9.2. **PATCH:** `{ "status": "approved", "can_live": true }` (field bỏ trống = giữ nguyên) → object ShopMember. **DELETE:** `204`.

**Lỗi:**

```json
{ "Result": false, "StatusCode": "404", "StatusMess": "Thành viên không thuộc shop của bạn", "status": 404, "message": "...", "data": null }
```

---

## B10. SRS webhook (server gọi, app KHÔNG gọi)

`/api/srs/*` kèm `?secret=…` (khớp `SRS_WEBHOOK_SECRET`). Trả body thuần `"0"` (cho phép) / khác `0` (từ chối). Payload SRS:

```json
{ "action": "on_publish", "client_id": "108", "ip": "1.2.3.4", "app": "live", "stream": "live_7f3c0a9e...", "param": "?token=xxxx", "file": "...flv", "duration": 67 }
```

| Action | Backend |
|--------|---------|
| `on_publish` | validate `?token=` + chống publisher trùng → `status=live` + push `list_change` |
| `on_unpublish` | nhả lock → `status=offline` + push `list_change` |
| `on_play` / `on_stop` | no-op |
| `on_dvr` | publish `recording.created` → worker bake VOD |

---

## B11. Mapping Phần A ↔ Phần B

| | Phần A | Phần B |
|--|--------|--------|
| Mở phiên | `POST live/start` | `POST /streams` |
| Định danh | `stream_key` / `id` (số) | `session_id` (UUID) |
| Xem | `GET live/watch?stream_key=` | `GET /streams/:id` + `/playback` |
| HLS | URL SRS trực tiếp | proxy ẩn key (`/streams/:id/hls/...`) |
| Chat | `chat/send` + poll | `POST/GET /streams/:id/chat` + WS |
| Kết thúc | `POST live/stop` | `POST /streams/:id/end` |

`POST live/start` trả kèm `session_id` (UUID) → host chuyển sang dùng route Phần B.

---

## B12. Tham chiếu code

| Chủ đề | File |
|--------|------|
| Route | `cmd/api/main.go` (`RegisterSpec` + `Register`) |
| Spec (A) | `internal/live/spec_handler.go`, `spec_repo.go`, `spec_chat_gift_repo.go` |
| Rich (B) | `internal/live/handler.go`, `session_repo.go` |
| URL push/playback | `internal/live/service.go`, `token.go` |
| HLS proxy | `internal/live/hls_proxy.go` |
| WebSocket | `internal/live/chathub.go` |
| AI | `internal/live/ai_handler.go`, `internal/ai/deepseek.go` |
| Member | `internal/live/member_handler.go`, `shop_member_repo.go` |
| VOD | `internal/live/events_log.go`, `internal/vod/*` |
| SRS | `internal/srs/webhook.go` |
| Envelope | `internal/httpx/envelope.go` |
| OpenAPI | `backend/docs/openapi.yaml` |
