# SRS – HƯỚNG DẪN CHO NGƯỜI MỚI

> **Dành cho:** Người mới vào dự án Tropia, chưa từng làm việc với media server.
> **Mục tiêu:** Đọc xong hiểu SRS là gì, tại sao Tropia dùng nó, dữ liệu
> video "chảy" qua hệ thống như thế nào, và mỗi file code/cấu hình làm gì.
> **Cập nhật:** 2026-06-05

---

## MỤC LỤC

1. [SRS là gì? (giải thích như cho người ngoài ngành)](#1-srs-là-gì)
2. [Tại sao Tropia cần SRS?](#2-tại-sao-tropia-cần-srs)
3. [Các giao thức video — đừng sợ mấy chữ viết tắt](#3-các-giao-thức-video)
4. [Bức tranh tổng thể trong Tropia](#4-bức-tranh-tổng-thể)
5. [Luồng đầy đủ: từ lúc seller bấm "Live" đến lúc người mua xem được](#5-luồng-đầy-đủ)
6. [File cấu hình `srs.conf` đọc từng dòng](#6-file-cấu-hình-srsconf)
7. [Webhooks: SRS "gọi điện" về backend](#7-webhooks)
8. [HLS proxy: tại sao Tropia không cho xem trực tiếp từ SRS](#8-hls-proxy)
9. [Bảo mật: stream key, publish token, webhook secret](#9-bảo-mật)
10. [DVR & VOD: ghi lại buổi live để xem lại](#10-dvr--vod)
11. [Bảng tra cứu nhanh cổng & endpoint](#11-bảng-tra-cứu-nhanh)
12. [Chạy & test ở máy local](#12-chạy--test-ở-local)
13. [Lỗi thường gặp & cách xử lý](#13-lỗi-thường-gặp)
14. [Bảng thuật ngữ](#14-bảng-thuật-ngữ)

---

## 1. SRS là gì?

**SRS = Simple Realtime Server** — một **media server** mã nguồn mở
(https://ossrs.io). Hãy hình dung nó như một **"tổng đài video trực tiếp"**:

- **Một đầu** nhận tín hiệu video từ người phát (seller dùng OBS / điện thoại).
- **Đầu kia** phát lại tín hiệu đó cho hàng trăm/nghìn người xem cùng lúc.

Vì sao không tự làm bằng Go? Vì việc nhận luồng video, đóng gói lại, cắt
thành từng mẩu nhỏ, đẩy đi cho nhiều người xem… là bài toán cực kỳ phức tạp
(timestamp, codec, buffer, độ trễ thấp). SRS là phần mềm chuyên dụng đã giải
quyết hết — Tropia chỉ cần **dùng** nó và **điều phối** nó từ backend Go.

> **Một câu chốt:** Backend Go quản lý *nghiệp vụ* (ai được live, sản phẩm
> nào, đơn hàng, chat). SRS chỉ lo phần *truyền video thô*. Hai bên nói
> chuyện với nhau qua webhook và URL.

Trong Tropia, SRS chạy bằng Docker, image `ossrs/srs:5` — xem
[infra/docker-compose.yml](infra/docker-compose.yml).

---

## 2. Tại sao Tropia cần SRS?

Tropia là sàn **mua sắm qua livestream kiểu Shopee Live**. Tính năng cốt lõi:
seller phát video trực tiếp giới thiệu sản phẩm, người mua vừa xem vừa chốt
đơn. Để làm được điều đó cần một thứ đứng giữa:

```
   Seller phát video                          Người mua xem video
   (OBS / điện thoại)                          (app Flutter)
          │                                          ▲
          │  đẩy luồng lên                           │  kéo luồng về
          ▼                                          │
        ┌─────────────────────────────────────────────┐
        │                    SRS                        │
        │   nhận 1 luồng  →  phát cho N người xem        │
        └─────────────────────────────────────────────┘
```

Nếu không có SRS, seller sẽ phải gửi video thẳng cho từng người xem — bất
khả thi. SRS làm nhiệm vụ **"nhân bản"** một luồng vào thành nhiều luồng ra.

---

## 3. Các giao thức video

Đây là phần làm người mới sợ nhất, nhưng thực ra chỉ cần nhớ: có **giao thức
để ĐẨY LÊN (ingest)** và **giao thức để XEM (playback)**. SRS hỗ trợ nhiều
loại để tương thích với mọi thiết bị.

### Nhóm ĐẨY LÊN (seller → SRS)

| Giao thức | Là gì | Ai dùng | Cổng |
|---|---|---|---|
| **RTMP** | Chuẩn cũ, phổ biến nhất | OBS Studio, Larix Broadcaster | 1935 |
| **SRT** | Mới, độ trễ thấp, chịu mạng yếu tốt | Thiết bị phát chuyên nghiệp | 10080/udp |
| **WHIP** | WebRTC để phát từ trình duyệt | Phát thẳng từ web (tương lai) | 1985 |

### Nhóm XEM (SRS → người mua)

| Giao thức | Là gì | Độ trễ | Tropia dùng? |
|---|---|---|---|
| **HLS** | Cắt video thành mẩu `.ts` 2 giây + file danh mục `.m3u8`. Chạy mọi nơi. | ~5–8 giây | ✅ **Mặc định** |
| **HTTP-FLV** | Luồng FLV liên tục, trễ thấp hơn HLS | ~2–3 giây | Có nhưng ít dùng |
| **WHEP** | WebRTC để xem, trễ cực thấp | <1 giây | Có nhưng ít dùng |

> **Tropia mặc định dùng HLS** vì nó chạy được trên *mọi* trình duyệt và
> điện thoại mà không cần plugin. Đánh đổi là trễ ~5–8 giây — chấp nhận được
> cho bán hàng (xem [infra/srs/srs.conf](infra/srs/srs.conf) phần `hls`).

**HLS hoạt động ra sao?** SRS liên tục cắt video thành các file nhỏ:

```
playlist.m3u8   ← "danh mục": liệt kê các mẩu hiện có, cập nhật mỗi 2s
live_xxx-1.ts   ← mẩu video 2 giây
live_xxx-2.ts   ← mẩu video 2 giây
live_xxx-3.ts   ← ...
```

Player (trình phát) đọc `.m3u8` để biết phải tải mẩu `.ts` nào tiếp theo,
ghép lại thành video liền mạch. Cứ 2 giây nó tải lại `.m3u8` để lấy mẩu mới.

---

## 4. Bức tranh tổng thể

Đây là sơ đồ **đầy đủ** của Tropia. Đừng lo nếu chưa hiểu hết — phần 5 sẽ đi
qua từng mũi tên.

```
┌──────────────┐   ① POST /api/live/streams        ┌─────────────────────┐
│   SELLER     │ ─────────────────────────────────▶│   BACKEND GO (:3000) │
│ (OBS/phone)  │   ◀── trả về {rtmp_url, hls_url} ──│  - tạo session       │
└──────┬───────┘                                    │  - sinh stream_key   │
       │                                            │  - sinh publish token│
       │ ② đẩy RTMP                                  └───────┬─────────────┘
       │ rtmp://host:1935/live/{key}?token=…                │ ▲
       ▼                                                    │ │ webhooks
┌─────────────────────────────────────────┐  ③ on_publish  │ │ (HTTP)
│                  SRS                      │ ───────────────┘ │
│  - nhận RTMP                              │  ⑤ on_dvr ───────┘
│  - cắt thành HLS (.m3u8 + .ts)            │
│  - ghi DVR (.flv) để lưu VOD              │
└───────┬───────────────────────────────────┘
        │ HLS thô (cổng 8080)
        ▼
┌─────────────────┐   ┌───────────────────────────────────────────┐
│  nginx :8090    │◀──│  BACKEND GO — HLS proxy                     │
│ (gom kết nối,   │   │  /api/live/streams/:id/hls/playlist.m3u8    │
│  cache)         │   │  - giấu stream_key                          │
└─────────────────┘   │  - viết lại đường dẫn trong .m3u8           │
                      └───────────────────┬───────────────────────┘
                                          │ ④ HLS đã ẩn danh
                                          ▼
                                  ┌────────────────┐
                                  │  NGƯỜI MUA      │
                                  │  (app Flutter)  │
                                  └────────────────┘

           Sau khi live kết thúc:
   ⑤ on_dvr → backend → Redis Stream "recording.created"
            → WORKER (cmd/worker): FFmpeg ghép FLV→MP4 + chèn chat
            → upload Cloudflare R2 → lưu vod_mp4_url để xem lại
```

**Điểm mấu chốt cần nhớ:** Người mua **không bao giờ** kết nối thẳng tới SRS.
Họ luôn đi qua backend Go (`/api/live/.../hls/...`). Lý do ở [phần 8](#8-hls-proxy).

---

## 5. Luồng đầy đủ

Theo dấu một buổi live từ đầu đến cuối. Số khoanh tròn khớp với sơ đồ trên.

### ① Seller bấm "Bắt đầu live"

App gọi `POST /api/live/streams` (cần quyền seller). Backend:

1. Sinh **stream_key** — một chuỗi ngẫu nhiên không đoán được, ví dụ
   `live_a3f8...` (256-bit). Xem
   [streamkey_provider.go](backend/internal/live/streamkey_provider.go).
   Đây là "tên kênh" mà SRS dùng để định danh luồng.
2. Sinh **publish token** — vé một lần để chứng minh "đúng là chủ kênh đang
   đẩy". Token được nhúng vào URL RTMP.
3. Trả về cho seller các URL (xem [service.go](backend/internal/live/service.go)):
   - `rtmp_url`: `rtmp://host:1935/live/{stream_key}?token={publish_token}`
   - `hls_url`: đường dẫn để xem lại sau.

### ② Seller đẩy luồng lên SRS

Seller dán `rtmp_url` vào OBS (hoặc app dùng Larix) và bấm "Start Streaming".
OBS bắt đầu đẩy video lên `rtmp://host:1935/live/{key}`.

### ③ SRS báo về backend: "có người bắt đầu phát!"

Ngay khi SRS nhận luồng, nó **gọi webhook** `POST /api/srs/on_publish` về
backend (xem [webhook.go](backend/internal/srs/webhook.go)). Backend kiểm tra:

- stream_key này có tồn tại không? (nếu không → từ chối)
- publish token có hợp lệ không? (chống mạo danh)
- đã có người khác đang phát kênh này chưa? (chống cướp sóng — dùng khóa Redis)

Nếu OK, backend đánh dấu session là **`live`** và đẩy thông báo cho tab Live
của mọi người mua để card live hiện lên ngay.

### ④ Người mua mở phòng live và xem

App Flutter gọi `GET /api/live/streams/:id/playback` → nhận về đường dẫn HLS
**của backend** (không phải URL SRS). App nạp đường dẫn này vào player HLS.

Khi player tải `playlist.m3u8`, request đi qua **HLS proxy của backend**
([hls_proxy.go](backend/internal/live/hls_proxy.go)):

1. Backend tra session theo `:id`, kiểm tra đang `live`.
2. Backend lấy `.m3u8` thật từ SRS (qua nginx :8090).
3. Backend **viết lại** nội dung `.m3u8`: thay các dòng chứa stream_key bằng
   đường dẫn ẩn danh `s/<số>.ts`.
4. Trả manifest đã viết lại cho player.
5. Player tải từng mẩu `.ts` cũng qua backend → backend kéo từ SRS → trả về.

### ⑤ Seller kết thúc live → ghi lại VOD

- Seller bấm "Kết thúc" → `POST /api/live/streams/:id/end`, hoặc OBS ngắt
  → SRS gọi `on_unpublish` → backend đánh dấu session `offline`/`ended`.
- SRS đã bật **DVR**, nên trong suốt buổi live nó ghi một file `.flv` ra đĩa.
  Khi file đóng lại, SRS gọi `on_dvr` về backend.
- Backend đẩy một sự kiện `recording.created` vào **Redis Stream**.
- **Worker** ([cmd/worker/main.go](backend/cmd/worker/main.go)) nhận sự kiện,
  dùng **FFmpeg** ghép `.flv` thành `.mp4` (chèn cả phụ đề chat), upload lên
  **Cloudflare R2**, rồi lưu `vod_mp4_url` để người mua xem lại sau.

---

## 6. File cấu hình `srs.conf`

Toàn bộ hành vi của SRS nằm trong [infra/srs/srs.conf](infra/srs/srs.conf).
Dưới đây là các khối quan trọng, giải thích bằng tiếng Việt:

```nginx
listen 1935;          # cổng nhận RTMP (đẩy lên)

http_api { listen 1985; }      # API trạng thái + WHIP/WHEP
http_server { listen 8080; }   # phục vụ file HLS (.m3u8/.ts) + HTTP-FLV
rtc_server { listen 8000; }    # WebRTC (UDP)
srt_server { listen 10080; }   # SRT (UDP)

vhost __defaultVhost__ {
    hls {
        enabled        on;
        hls_fragment   2;    # mỗi mẩu .ts dài 2 giây
        hls_window     60;   # giữ 60 giây video gần nhất (30 mẩu)
        hls_wait_keyframe on; # cắt mẩu tại keyframe → tránh giật
        ...
    }
    http_hooks {            # SRS gọi webhook về backend Go khi có sự kiện
        on_publish   http://host.docker.internal:3000/api/srs/on_publish?secret=dev-secret;
        on_unpublish ...
        on_dvr       ...
    }
    dvr { enabled on; dvr_path .../[stream].[timestamp].flv; }  # ghi VOD
}
```

**Vài chỗ "tế nhị" mà người mới hay vấp** (đều có ghi chú dài trong file):

- `hls_window 60` (không phải 20): nếu cửa sổ quá ngắn, người xem vào giữa
  chừng sẽ xin mẩu `.ts` mà SRS đã xóa → lỗi *"Lỗi phát video"*.
- `hls_ctx off` / `hls_ts_ctx off`: SRS 5 mặc định bật, khiến lần đầu tải
  `.m3u8` trả về một "master playlist" rỗng. HLS proxy của Tropia không xử lý
  được dạng đó → phải tắt để SRS trả thẳng media playlist.
- `host.docker.internal`: vì SRS chạy trong Docker còn backend Go chạy ở máy
  host, đây là cách container "gọi ra ngoài" tới `localhost:3000`.
- `?secret=dev-secret`: chuỗi bí mật để backend biết webhook đến *thật sự*
  từ SRS. Xem [phần 9](#9-bảo-mật).

---

## 7. Webhooks

**Webhook** = SRS chủ động gọi HTTP về backend khi có sự kiện. Đây là cách
backend biết chuyện gì đang xảy ra bên trong SRS mà không cần hỏi liên tục.

Tất cả webhook được xử lý ở [webhook.go](backend/internal/srs/webhook.go),
đăng ký dưới nhóm route `/api/srs`:

| Webhook | Khi nào SRS gọi | Backend làm gì |
|---|---|---|
| `on_publish` | Host bắt đầu phát | Kiểm tra key + token, đánh dấu `live`, báo tab Live |
| `on_unpublish` | Host ngừng phát | Đánh dấu `offline`/`ended`, nhả khóa publisher |
| `on_play` | Có người xem kết nối | (hiện chỉ trả OK) |
| `on_stop` | Người xem rời đi | (hiện chỉ trả OK) |
| `on_dvr` | File ghi `.flv` đóng lại | Phát sự kiện `recording.created` cho worker xử lý VOD |

**Quy ước trả lời quan trọng:** SRS chờ HTTP 200 với **body = `"0"`** nghĩa là
*"cho phép"*, body khác `0` nghĩa là *"từ chối"*. Vì thế khi backend muốn chặn
một luồng giả mạo, nó trả `"1"` chứ không phải mã lỗi HTTP — xem hàm `ok()` và
`deny()` trong [webhook.go](backend/internal/srs/webhook.go).

---

## 8. HLS proxy

> **Câu hỏi của người mới:** SRS đã phát HLS ở cổng 8080 rồi, sao không cho
> app xem thẳng cho nhanh?

Có **hai vấn đề** nên Tropia bắt người xem đi vòng qua backend:

### Vấn đề 1 — Lộ stream_key (bảo mật)

SRS định danh luồng bằng đường dẫn URL. Nếu cho xem thẳng, URL sẽ là
`http://host:8080/live/<stream_key>.m3u8`. Ai mở DevTools cũng thấy
`stream_key`, rồi dùng chính key đó để **đẩy luồng giả mạo lên RTMP** → cướp
sóng. **Giải pháp:** backend proxy che key đi, URL người mua thấy chỉ là
`/api/live/streams/<session_id>/hls/playlist.m3u8` — không có key nào cả.
Code: [hls_proxy.go](backend/internal/live/hls_proxy.go), hàm
`rewriteHLSManifest`.

### Vấn đề 2 — Cạn cổng TCP trên Windows (kỹ thuật)

SRS gắn `Connection: close` vào mọi response, nên mỗi mẩu `.ts` mở một socket
TCP mới. Trên Windows, sau ~10 phút xem là cạn dải cổng tạm → Chrome báo
`ERR_ADDRESS_IN_USE`, video chết. **Giải pháp:** đặt **nginx** ở cổng 8090
trước SRS để gom kết nối (keep-alive) + cache. Xem
[hls-proxy.conf](infra/nginx/hls-proxy.conf) và phần ghi chú trong
[docker-compose.yml](infra/docker-compose.yml).

### Vậy có mấy lớp proxy?

```
App Flutter
   │  /api/live/.../hls/playlist.m3u8
   ▼
Backend Go (giấu key, viết lại manifest)   ← hls_proxy.go
   │  http://localhost:8090/live/<key>.m3u8
   ▼
nginx :8090 (gom kết nối + cache)            ← hls-proxy.conf
   │  http://srs:8080/live/<key>.m3u8
   ▼
SRS :8080 (file HLS thật)
```

> **Đánh đổi:** mỗi mẩu video đi thêm 1–2 chặng → tốn băng thông backend và
> trễ thêm ~50–100ms. Ở quy mô MVP thì ổn; khi >1k người xem đồng thời nên
> chuyển sang CDN chuyên dụng (đã ghi chú trong code).

---

## 9. Bảo mật

Tropia phòng 3 mối đe dọa chính quanh SRS:

| Cơ chế | Chống điều gì | Ở đâu |
|---|---|---|
| **stream_key 256-bit ngẫu nhiên** | Đoán mò tên kênh | [streamkey_provider.go](backend/internal/live/streamkey_provider.go) |
| **Publish token** (vé một lần, nhúng `?token=` vào RTMP) | Mạo danh đẩy luồng dù biết key | kiểm ở `on_publish`, [webhook.go](backend/internal/srs/webhook.go) |
| **Khóa publisher trên Redis** | Hai người cùng đẩy 1 kênh (cướp sóng) | `on_publish`/`on_unpublish` |
| **HLS proxy giấu key** | Lộ key qua DevTools để cướp sóng/leech | [hls_proxy.go](backend/internal/live/hls_proxy.go) |
| **Webhook secret** (`?secret=…`) | Kẻ gian gọi webhook giả để fake `on_publish`/`on_dvr` | `verifySecret` trong webhook.go |
| **Token signer (HMAC)** *(tùy chọn)* | URL bị rò vẫn hết hạn sau TTL | [token.go](backend/internal/live/token.go) |

**Hai điều BẮT BUỘC khi lên production** (backend tự kiểm tra và **từ chối
khởi động** nếu thiếu — xem [cmd/api/main.go](backend/cmd/api/main.go)):

- `SRS_WEBHOOK_SECRET` phải được đặt (nếu không, ai cũng forge được webhook).
- Phải dùng giá trị secret entropy cao, **không** dùng `dev-secret` như local.

Token signer (`token.go`) hiện **mặc định tắt** vì định dạng HMAC còn chờ đội
infra xác nhận để cấu hình phía SRS cho khớp. Bật bằng các biến môi trường
`SRS_TOKEN_KEYS_JSON` + `SRS_TOKEN_CURRENT_KID`.

---

## 10. DVR & VOD

**DVR** (Digital Video Recording) là tính năng của SRS: vừa phát live, vừa
ghi luôn ra file `.flv` trên đĩa. Tropia bật DVR theo `dvr_plan session` →
**một file cho mỗi buổi live**.

Quy trình biến file ghi thành video xem lại (VOD):

```
SRS ghi xong .flv
   │  on_dvr webhook
   ▼
Backend: phát sự kiện "recording.created" vào Redis Stream
   ▼
Worker (cmd/worker) nhận sự kiện:
   1. Tải session + lịch sử chat + sự kiện từ Postgres
   2. vod.Bake(): FFmpeg ghép FLV→MP4, "đốt" phụ đề chat vào khung hình
   3. Upload MP4 lên Cloudflare R2: videos/vod/<sessionId>/<ts>.mp4
   4. Lưu live_sessions.vod_mp4_url
```

Code: [handleRecording trong cmd/worker/main.go](backend/cmd/worker/main.go).

**Lưu ý về thư mục chia sẻ:** SRS ghi file *bên trong container* tại
`./objs/nginx/html/dvr/...`, nhưng được **bind-mount** ra host ở `infra/dvr`
(xem [docker-compose.yml](infra/docker-compose.yml)) để worker chạy ở host đọc
được. Backend cắt bỏ tiền tố đường dẫn container trước khi đưa cho worker.

Worker còn có 3 "người dọn dẹp" chạy nền:
- **DVR sweeper**: xóa `.flv` mồ côi (remux lỗi/crash) sau 2 giờ.
- **Live duration sweeper**: ép kết thúc buổi live bị bỏ quên (mặc định >2h).
- **R2 retention sweeper**: xóa VOD trên R2 sau 30 ngày.

---

## 11. Bảng tra cứu nhanh

### Cổng SRS (xem [docker-compose.yml](infra/docker-compose.yml))

| Cổng | Giao thức | Dùng để |
|---|---|---|
| `1935` | RTMP | Seller đẩy luồng (OBS) |
| `8080` | HTTP | SRS phát HLS/FLV thô (nội bộ) |
| `8090` | HTTP | **nginx proxy** trước SRS (backend kéo HLS từ đây) |
| `1985` | HTTP | SRS API + WHIP/WHEP |
| `8000/udp` | UDP | WebRTC media |
| `10080/udp` | UDP | SRT |

### URL mẫu

```
# Seller đẩy RTMP
rtmp://localhost:1935/live/{stream_key}?token={publish_token}

# HLS thô của SRS (KHÔNG đưa cho người mua)
http://localhost:8080/live/{stream_key}.m3u8

# HLS mà người mua thực sự dùng (qua backend, đã giấu key)
GET /api/live/streams/{session_id}/hls/playlist.m3u8
GET /api/live/streams/{session_id}/hls/s/{seq}.ts
```

### Biến môi trường liên quan (xem [config.go](backend/internal/config/config.go))

| Biến | Mặc định | Ý nghĩa |
|---|---|---|
| `SRS_RTMP_HOST` | `rtmp://localhost:1935` | Host RTMP trả cho seller |
| `SRS_HLS_HOST` | `http://localhost:8090` | Host HLS backend kéo về (nginx) |
| `SRS_WHIP_HOST` | `http://localhost:1985` | Host WHIP/WHEP |
| `SRS_WEBHOOK_SECRET` | *(rỗng ở dev)* | Bí mật xác thực webhook; **bắt buộc ở prod** |
| `SRS_TOKEN_KEYS_JSON` | *(rỗng)* | Bật token signer HMAC (tùy chọn) |

### File quan trọng

| File | Vai trò |
|---|---|
| [infra/srs/srs.conf](infra/srs/srs.conf) | Toàn bộ cấu hình SRS |
| [infra/docker-compose.yml](infra/docker-compose.yml) | Khởi chạy SRS + nginx + Postgres + Redis |
| [infra/nginx/hls-proxy.conf](infra/nginx/hls-proxy.conf) | nginx gom kết nối + cache HLS |
| [backend/internal/srs/webhook.go](backend/internal/srs/webhook.go) | Xử lý webhook từ SRS |
| [backend/internal/live/service.go](backend/internal/live/service.go) | Sinh URL publish/playback |
| [backend/internal/live/hls_proxy.go](backend/internal/live/hls_proxy.go) | Proxy + viết lại manifest HLS |
| [backend/internal/live/streamkey_provider.go](backend/internal/live/streamkey_provider.go) | Sinh stream_key |
| [backend/internal/live/token.go](backend/internal/live/token.go) | Token signer HMAC |
| [backend/cmd/worker/main.go](backend/cmd/worker/main.go) | Xử lý VOD từ file DVR |

---

## 12. Chạy & test ở local

### Khởi động cả stack (SRS + nginx + DB + Redis)

```bash
cd infra
docker compose up -d
docker compose logs -f srs      # xem log SRS realtime
```

### Đẩy một luồng test bằng FFmpeg (không cần OBS)

```bash
ffmpeg -re -stream_loop -1 -i test.mp4 -c copy -f flv \
  rtmp://localhost:1935/live/test
```

> Lưu ý: kênh `test` này **không qua backend** nên sẽ bị `on_publish` từ chối
> (vì không có session/token tương ứng). Để test xuyên suốt, hãy tạo session
> thật qua `POST /api/live/streams` rồi đẩy bằng `rtmp_url` nó trả về.

### Xem thử luồng thô

Mở `http://localhost:8080/live/test.m3u8` bằng VLC hoặc trình duyệt.

### Kiểm tra SRS còn sống

```bash
curl http://localhost:1985/api/v1/streams      # liệt kê luồng đang chạy
docker compose ps                              # trạng thái container
```

### Reset sạch (xóa cả DB + bản ghi DVR)

```bash
cd infra
docker compose down -v
```

Tham khảo thêm: [infra/README.md](infra/README.md).

---

## 13. Lỗi thường gặp

| Triệu chứng | Nguyên nhân thường gặp | Cách xử lý |
|---|---|---|
| **"Lỗi phát video"** ngay khi mở phòng | SRS chưa kịp tạo mẩu HLS đầu tiên (~4–6s sau khi host phát) | Bình thường — proxy đã có cơ chế "cold-start" chờ tối đa ~6s trong [hls_proxy.go](backend/internal/live/hls_proxy.go); chờ chút sẽ lên |
| **"Lỗi phát video"** giữa chừng | Người xem xin mẩu `.ts` đã bị SRS xóa | Đảm bảo `hls_window 60` trong srs.conf; client vào quá trễ |
| Video **giật/đứng** liên tục | Encoder phát GOP/keyframe không đều → nhiều `#EXT-X-DISCONTINUITY` | Sửa từ phía encoder (đặt keyframe interval đều); client đã cấu hình hls.js chịu đựng |
| `on_publish` **bị từ chối** | Sai/thiếu publish token, hoặc stream_key không tồn tại | Tạo session qua API và dùng đúng `rtmp_url` trả về |
| Webhook **không tới backend** | SRS trong Docker không gọi được `localhost` của host | Dùng `host.docker.internal:3000` (đã set trong srs.conf) |
| `ERR_ADDRESS_IN_USE` trên Windows | Bỏ qua nginx, xem thẳng SRS :8080 | Luôn xem qua backend / nginx :8090 |
| Backend **không khởi động ở prod** | Thiếu `SRS_WEBHOOK_SECRET` | Đặt biến môi trường này (bắt buộc ở release mode) |
| VOD **không xuất hiện** sau live | Worker chưa chạy, thiếu `ffmpeg`, hoặc chưa cấu hình R2 | Chạy `make worker`; cài ffmpeg; kiểm tra creds R2 |

---

## 14. Bảng thuật ngữ

| Thuật ngữ | Giải thích ngắn |
|---|---|
| **SRS** | Simple Realtime Server — media server nhận & phát video trực tiếp |
| **Ingest** | Việc seller đẩy luồng video *lên* server |
| **Playback** | Việc người mua kéo luồng *về* để xem |
| **stream_key** | Chuỗi ngẫu nhiên định danh một kênh live trên SRS |
| **publish token** | Vé một lần chứng minh quyền đẩy luồng, nhúng vào URL RTMP |
| **RTMP** | Giao thức đẩy luồng phổ biến (OBS dùng) |
| **HLS** | Giao thức xem: cắt video thành mẩu `.ts` + danh mục `.m3u8` |
| **`.m3u8`** | File "danh mục" liệt kê các mẩu `.ts`, cập nhật liên tục |
| **`.ts`** | Một mẩu video ~2 giây |
| **WHIP / WHEP** | WebRTC để phát / để xem (trễ cực thấp) |
| **SRT** | Giao thức đẩy luồng chống mạng yếu, độ trễ thấp |
| **DVR** | Tính năng SRS ghi luồng live ra file `.flv` |
| **VOD** | Video On Demand — bản ghi để xem lại sau buổi live |
| **Webhook** | SRS gọi HTTP về backend khi có sự kiện |
| **Proxy** | Lớp trung gian; ở đây backend & nginx đứng giữa người xem và SRS |
| **Manifest** | Tên gọi khác của file `.m3u8` |
| **Cold-start** | Khoảng ~4–6s đầu khi SRS chưa kịp tạo mẩu HLS |

---

> **Bước tiếp theo nên đọc:**
> - [CLAUDE.md](CLAUDE.md) — tổng quan kiến trúc & quy ước toàn dự án.
> - [docs/SETUP_GUIDE.md](docs/SETUP_GUIDE.md) — cài đặt môi trường chạy app.
> - [backend/AUDIT.md](backend/AUDIT.md) — lịch sử port từ Node.js sang Go.
> - Trực tiếp đọc [webhook.go](backend/internal/srs/webhook.go) và
>   [hls_proxy.go](backend/internal/live/hls_proxy.go) — comment trong code
>   rất chi tiết và là nguồn chân lý mới nhất.
