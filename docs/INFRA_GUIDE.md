# HẠ TẦNG LIVESTREAM – DỰNG TỪ SỐ 0

> **Dành cho:** Đội mới (kiểu tropia.thienhaisoft.com) chưa từng làm livestream,
> cần biết **cần những gì** và **dựng hạ tầng ra sao** — cả ở máy local lẫn
> production.
> **Mục tiêu:** Đọc 15 phút là dựng được một stack livestream chạy thật.
> **Bổ trợ:** [SRS_GUIDE.md](SRS_GUIDE.md) (hiểu media server),
> [SETUP_GUIDE.md](SETUP_GUIDE.md) (chạy app),
> [infra/README.md](../infra/README.md), [k8s/README.md](../k8s/README.md).
> **Cập nhật:** 2026-06-07

---

## 1. Livestream cần những "cục lego" gì?

Đừng nghĩ phức tạp. Một nền tảng live-shopping chỉ là **4 cục lego**:

| # | Cục lego | Vai trò (nói cho người ngoài ngành) | Tropia dùng |
|---|---|---|---|
| 1 | **Đầu phát (ingest)** | Nhận video từ người bán | OBS / điện thoại → đẩy **RTMP/SRT/WHIP** |
| 2 | **Media server** | "Tổng đài video": nhận 1 luồng, phát lại cho ngàn người, cắt thành mẩu nhỏ | **SRS 5** |
| 3 | **Lớp phát lại (delivery)** | Đưa video tới trình duyệt/app người xem, chịu tải | **nginx proxy → HLS**, (prod: + CDN) |
| 4 | **Bộ não (control + data)** | Ai được live, sản phẩm nào, chat, đơn hàng, lưu video xem lại | **Go backend + Postgres + Redis + R2** |

Chỉ cần ghép đủ 4 cục này là có livestream. Phần còn lại của doc chỉ là
"lắp 4 cục đó ở local" rồi "lắp lại ở production".

---

## 2. Video "chảy" qua hệ thống thế nào (1 hình)

```
  Người bán (OBS / app)                              Người mua (app / web)
        │                                                     ▲
        │ ① RTMP/SRT/WHIP push                                │ ⑤ xem HLS
        ▼                                                     │
   ┌─────────┐   ② báo "đã live"   ┌──────────┐              │
   │   SRS   │ ───────────────────▶│ Go backend│◀── ④ xin link xem
   │ (media) │   (webhook)          │  (Postgres│
   └────┬────┘                      │  + Redis) │
        │ ③ cắt video → HLS (.m3u8 + .ts)        └────┬─────┘
        ▼                                              │
   ┌──────────┐                                        │ ⑥ DVR xong → upload
   │  nginx   │◀── người mua kéo segment qua đây        ▼
   │ hls-proxy│                                   ┌──────────┐
   └──────────┘                                   │ R2 (VOD) │ xem lại
                                                  └──────────┘
```

1. Seller bấm "Live" → backend tạo session, trả về URL push (RTMP/SRT/WHIP).
2. Seller đẩy video vào SRS → SRS gọi webhook `on_publish` báo backend "đã live".
3. SRS cắt luồng thành HLS (playlist `.m3u8` + các mẩu `.ts`).
4. Người mua mở app → xin link xem → backend trả URL HLS.
5. App phát HLS, **kéo qua nginx proxy** (không xem trực tiếp từ SRS — xem §6).
6. Hết live, SRS ghi file DVR → worker upload lên R2 để xem lại (VOD).

> Muốn hiểu sâu từng bước, đọc [SRS_GUIDE.md §5](SRS_GUIDE.md).

---

## 3. Bộ đồ nghề tối thiểu phải chuẩn bị

Trước khi gõ lệnh, chuẩn bị sẵn:

**Để chạy LOCAL (1 máy, để dev/test):**
- [ ] Docker Desktop (đã bật, có `docker compose`).
- [ ] Go 1.26+ (chạy backend) và Flutter 3.x (chạy app) — xem SETUP_GUIDE.
- [ ] OBS Studio **hoặc** app Larix Broadcaster trên điện thoại (để test push).
- Không cần domain, không cần CDN, không cần tài khoản thanh toán.

**Để chạy PRODUCTION:**
- [ ] 1 cụm **Kubernetes** (managed: GKE/EKS/AKS, hoặc tự dựng).
- [ ] 2 domain trỏ vào cụm: `api.tropia.vn` (API) + `hls.tropia.vn` (xem live).
- [ ] **NGINX Ingress Controller** + **cert-manager** (TLS Let's Encrypt) đã cài.
- [ ] 1 **container registry** để push image backend (Docker Hub / GHCR / registry riêng).
- [ ] Tài khoản **Cloudflare R2** (lưu VOD + ảnh) → lấy 5 giá trị `R2_*`.
- [ ] (Tuỳ chọn) cổng thanh toán MoMo/VNPay/ZaloPay, Google OAuth, SMTP, DeepSeek.

> Mẹo: production **không bắt buộc** đủ thanh toán/AI ngay từ đầu. Để trống
> các secret đó là được; livestream vẫn chạy. Bắt buộc nhất là: Postgres
> password, 2 JWT secret, và `SRS_WEBHOOK_SECRET`.

---

## 4. Dựng ở LOCAL — 1 lệnh là xong hạ tầng

Toàn bộ 4 cục lego đã đóng gói trong [infra/docker-compose.yml](../infra/docker-compose.yml):

```bash
cd infra
docker compose up -d        # bật Postgres + Redis + SRS + nginx hls-proxy
docker compose ps           # kiểm tra 4 container "healthy"
```

Sau lệnh này bạn đã có:

| Service | Cổng (host) | Dùng để |
|---|---|---|
| Postgres | `5433` | DB chính (5432 hay trùng pg sẵn có) |
| Redis | `6380` | chat / cache / rate-limit |
| SRS | `1935` RTMP · `1985` API+WHIP · `8080` HLS thô · `8000/udp` WebRTC · `10080/udp` SRT | media server |
| nginx hls-proxy | `8090` | link HLS cho người xem |

Rồi bật bộ não (backend) + app (xem [SETUP_GUIDE.md](SETUP_GUIDE.md)):

```bash
cd ../backend && make run        # backend Go ở :3000, đọc .env.development
cd ../frontend && make dev-web   # app Flutter
```

**Test push thử không cần seller thật** — đẩy 1 file mp4 vào SRS bằng ffmpeg:

```bash
ffmpeg -re -stream_loop -1 -i test.mp4 -c copy -f flv rtmp://localhost:1935/live/test
# Mở xem: http://localhost:8080/live/test.m3u8  (VLC hoặc trình duyệt)
```

> Wi-Fi đổi / test trên điện thoại thật? Dùng `make dev-api` + `make dev-mobile`
> — script tự dò IP LAN, không hardcode IP ở đâu cả (xem CLAUDE.md §2).

Xong. Local là chỗ để hiểu hệ thống trước khi đụng production.

---

## 5. Dựng ở PRODUCTION — Kubernetes theo thứ tự

Tất cả manifest nằm trong [k8s/](../k8s/). Mỗi cục lego = 1 file:

| File | Là cục lego nào |
|---|---|
| `namespace.yaml` | tạo namespace `tropia` |
| `secrets.example.yaml` | mẫu secret → copy thành `secrets.yaml` rồi điền |
| `postgres.yaml` + `postgres-init-configmap.yaml` | DB (StatefulSet + ổ đĩa 20Gi) |
| `pgbouncer.yaml` | gom kết nối DB (xem §7) |
| `redis.yaml` | cache / pub-sub |
| `srs.yaml` | **media server** (LoadBalancer cho OBS/người xem) |
| `backend.yaml` | bộ não Go (2 pod, tự scale 2→20 theo CPU) |
| `worker.yaml` | chạy nền: upload VOD lên R2 |
| `ingress.yaml` | cửa vào HTTPS: `api.` + `hls.` |
| `network-policy.yaml` | tường lửa nội bộ (mặc định chặn hết, mở đúng luồng cần) |
| `prometheus.yaml` + `grafana.yaml` | giám sát |

### Các bước (chạy đúng thứ tự)

```bash
# 1. Namespace
kubectl apply -f k8s/namespace.yaml

# 2. Secret — copy mẫu, ĐIỀN giá trị thật, KHÔNG commit file thật
cp k8s/secrets.example.yaml k8s/secrets.yaml
#   sinh JWT secret:  openssl rand -hex 32
#   điền: postgres-password, JWT_*, R2_*  (các mục khác để trống cũng được)
kubectl apply -f k8s/secrets.yaml

# 3. Nén init.sql (schema DB lần đầu) thành ConfigMap
kubectl create configmap postgres-init \
  --from-file=init.sql=infra/postgres/init.sql \
  -n tropia --dry-run=client -o yaml > k8s/postgres-init-configmap.yaml

# 4. Build & push image backend (đổi registry thành của bạn)
docker build -t <registry>/backend:v1 ./backend
docker push  <registry>/backend:v1
#   rồi sửa `image:` trong k8s/backend.yaml và k8s/worker.yaml

# 5. Bật tất cả phần còn lại
kubectl apply -f k8s/

# 6. Xem nó lên
kubectl -n tropia get pods -w
```

### Sau khi pod chạy: 3 việc bắt buộc

1. **Trỏ domain:** lấy IP của Ingress (`kubectl -n tropia get ingress`) → tạo
   bản ghi DNS A cho `api.tropia.vn` và `hls.tropia.vn`. cert-manager tự cấp TLS.
2. **CORS:** sửa `CORS_ORIGIN` trong `backend.yaml` thành domain frontend thật
   (release mode **từ chối boot** nếu để trống hoặc `*`).
3. **Webhook secret:** đảm bảo `SRS_WEBHOOK_SECRET` (trong secret) **khớp** với
   `?secret=…` trong `http_hooks` của `srs.yaml`. Lệch nhau → SRS báo live mà
   backend bỏ qua → "đã phát mà app không thấy live".

> Muốn thử production mà chưa có cụm thật? Docker Desktop có sẵn Kubernetes:
> bật trong Settings, `docker build -t tropia/backend:dev ./backend`,
> `kubectl apply -f k8s/`, rồi `port-forward` (xem [k8s/README.md](../k8s/README.md)).

---

## 6. Vì sao có nginx proxy trước SRS? (đừng bỏ)

SRS gắn `Connection: close` vào **mọi** response. Trình duyệt xem live phải tải
liên tục hàng trăm mẩu `.ts` → mỗi mẩu mở 1 TCP mới → trên Windows cạn sạch
cổng ephemeral sau ~10 phút, Chrome báo `ERR_ADDRESS_IN_USE`, video chết.

**nginx hls-proxy** ([infra/nginx/hls-proxy.conf](../infra/nginx/hls-proxy.conf))
giữ keep-alive với người xem, gộp socket tới SRS, **cache** playlist 1s + segment
30s → nhiều người xem cùng lúc chỉ "đập" SRS một lần. Vì thế backend luôn trả
`SRS_HLS_HOST = nginx (cổng 8090)`, **không** trả SRS thô (8080).

Production: đặt thêm **Cloudflare CDN** trước `hls.tropia.vn` (cache `.m3u8` TTL ngắn
~2s, `.ts` TTL dài) để chịu tải ngàn người xem.

---

## 7. Vì sao có PgBouncer? (production)

Mỗi backend pod mở tới 200 kết nối DB. 3 pod = 600 → Postgres "ngộp" (>300 là
đuối). [pgbouncer.yaml](../k8s/pgbouncer.yaml) gom 600 client đó xuống ~50 kết
nối thật (transaction mode). Vì thế `DATABASE_URL` của backend trỏ vào
`pgbouncer:6432`, **không** trỏ thẳng `postgres:5432`. (Local 1 backend thì
không cần, nối thẳng Postgres.)

---

## 8. Kiểm tra "đã chạy thật" (smoke test)

```bash
# Backend sống chưa
curl https://api.tropia.vn/health           # prod
curl http://localhost:3000/health           # local

# Seed dữ liệu mẫu (1 admin + seller + buyer + shop + sản phẩm + 1 live)
cd backend && make seed                     # account đều dùng pass Password123

# Test luồng live đầy đủ:
#  1) đăng nhập seller → tạo stream → lấy URL RTMP
#  2) OBS push vào URL đó
#  3) mở app bằng buyer → thấy stream "đang live" và xem được
```

Giám sát: `kubectl -n tropia port-forward svc/grafana 3001:3000` → mở
http://localhost:3001 (user `admin`). Metrics backend ở `/metrics`.

---

## 9. Lỗi hay gặp & cách sửa

| Triệu chứng | Nguyên nhân thường gặp |
|---|---|
| Push được mà app **không thấy live** | `SRS_WEBHOOK_SECRET` (backend) ≠ `?secret=` trong `srs.conf`/`srs.yaml` |
| App báo "Lỗi phát video" | Xem HLS thẳng từ SRS thay vì qua nginx; hoặc segment đã bị xoá (chỉnh `hls_window`) — xem [SRS_GUIDE.md §13](SRS_GUIDE.md) |
| Backend prod **không khởi động** | `CORS_ORIGIN` để trống/`*`, hoặc thiếu `SRS_WEBHOOK_SECRET`, hoặc JWT secret < 32 byte |
| OBS không kết nối được (prod) | SRS Service phải là `LoadBalancer` và firewall mở cổng 1935 |
| DB chậm / hết kết nối (prod) | Backend nối thẳng Postgres thay vì qua PgBouncer |

---

## 10. Tóm tắt 1 phút

- Livestream = **4 cục lego**: đầu phát → SRS → nginx/HLS → backend+DB+Redis+R2.
- **Local:** `cd infra && docker compose up -d` là có hết hạ tầng; `make run` +
  `make dev-web` là chạy app.
- **Production:** `kubectl apply -f k8s/` theo thứ tự (namespace → secret →
  postgres-init → build image → apply hết), rồi trỏ domain + sửa `CORS_ORIGIN`
  + khớp `SRS_WEBHOOK_SECRET`.
- 2 thứ "lạ" nhưng **đừng bỏ**: **nginx hls-proxy** (giữ video không chết) và
  **PgBouncer** (giữ DB không ngộp).
- Đọc tiếp khi cần hiểu sâu: [SRS_GUIDE.md](SRS_GUIDE.md),
  [LIVESTREAM_API.md](LIVESTREAM_API.md), [SECURITY.md](SECURITY.md).
