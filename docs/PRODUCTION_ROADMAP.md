# Tropia Live — Production Roadmap

**Target scale (6 tháng đầu):** 200 host concurrent · 1 000 viewer concurrent · budget ≤ $500/tháng.

Mọi quyết định trong tài liệu này tối ưu cho 3 ràng buộc: **ổn định ↑, latency ↓, $/viewer-hour ↓**. Khi conflict → chọn ổn định.

---

## 1. Architecture target

```
                ┌───────────────┐
                │  Host (mobile)│ ──── RTMP push ────┐
                └───────────────┘                    │
                                                     ▼
                                            ┌──────────────────┐
                                            │  SRS Origin (VN) │
                                            │  Hetzner CCX23   │
                                            └─────────┬────────┘
                                                      │ HLS pull
                              ┌───────────────────────┼───────────────────────┐
                              ▼                       ▼                       ▼
                       ┌─────────────┐         ┌─────────────┐         ┌─────────────┐
                       │ Cloudflare  │         │ nginx proxy │         │ Worker (VOD)│
                       │   Free      │         │ (current)   │         │ FFmpeg → R2 │
                       │ CDN tier    │         └─────────────┘         └─────────────┘
                       └──────┬──────┘
                              │ HLS m3u8 + .ts
                              ▼
                       ┌─────────────┐
                       │   Viewers   │  ← cache hit ratio ≥ 90% kỳ vọng
                       │  (Web/Phone)│
                       └─────────────┘
```

**Tại sao thiết kế này:**
- **Cloudflare Free** cache HLS segments. 1 000 viewer cùng xem 1 stream chỉ tốn ~10 origin fetches/giây (cache hit ratio cao nhờ segment immutable). Free tier cap 100k req/day per zone — đủ cho 1k concurrent ở segment 2s.
- **SRS origin single-node** đủ cho 200 host concurrent (mỗi RTMP ingest tốn ~1 CPU + 2Mbps egress origin → CDN). Không cần edge cluster ở scale này.
- **nginx proxy** vẫn giữ để fix `ERR_ADDRESS_IN_USE` (đã làm hôm nay) + CORS pre-CDN.

---

## 2. Pain points hiện tại → fix cụ thể

### 2.1 RTMP host không ổn định (out app cái ngắt live)

**Hiện tại:** apivideo_live_stream không có exponential backoff reconnect. Out app vài giây → socket đóng → SRS gọi `on_unpublish` → backend chỉ stamp `ended_at`. Khi resume, `_reattachRtmp` chạy lại — nhưng nếu Android kill process trong background thì mất luôn.

**Fix:**
1. **Foreground service Android** giữ RTMP socket sống khi app ở background (5-10 phút). Cần native Kotlin code — apivideo plugin không tự lo. ~2-3 ngày dev.
2. **Backend grace window**: SRS `on_unpublish` chỉ flip `status='ended'` sau 30s không có `on_publish` lại. Hiện đã đúng (chỉ stamp ended_at, status='live') — chỉ thiếu **background cleanup job** kill session sau 5 phút không có RTMP.
3. **Frontend resilience**: `_pollStats` poll `playback_hls` mỗi 5s, nếu URL trả 404 nhiều lần liên tiếp → reattach RTMP tự động (không cần user mở lại app).

**Priority:** P0 (host UX là pain point lớn nhất).

### 2.2 Nhiều viewer đè dập server

**Hiện tại:** SRS serve trực tiếp tất cả viewer. 1.5Mbps × 50 viewer = 75Mbps đã hết bandwidth của VPS 100Mbps phổ thông.

**Fix triệt để: thêm Cloudflare làm CDN miễn phí.**
- Đăng ký domain (vd `live.tropia.vn`) → DNS qua Cloudflare → proxy ON.
- Backend trả `playback.hls = https://live.tropia.vn/live/{key}.m3u8` thay vì `http://192.168.x.x:8090/...`.
- Cloudflare cache `.ts` segments 30s (immutable), `.m3u8` 2s (gần real-time).
- Free tier không cap bandwidth, chỉ cap "video/large file" nhưng .ts <2MB nên KHÔNG bị cap.

**Kết quả kỳ vọng:** Origin egress giảm 90-95%. SRS chỉ serve ~50 fetch/giây cho 1k viewer thay vì 1k fetch/giây.

**Priority:** P0. Đây là blocker duy nhất để vượt 50 viewer/stream.

### 2.3 Lag/giật khi xem

**Nguyên nhân tổng hợp đã debug:**
- `Connection: close` → port exhaust → đã fix bằng nginx proxy + Cloudflare CDN tới đây sẽ triệt để.
- DISCONTINUITY tags do GOP ngắn → đã giảm bằng hls.js retry config.
- Buffer underrun do `hls_window 4` → đã tăng lên 20s.

**Production check sau khi triển khai CDN:**
- p50 buffer health ≥ 5s (Cloudflare DevTools `X-Cache-Status: HIT` chiếm >90%).
- Stall rate < 1 lần/10 phút xem.

**Priority:** P0 (đã làm, cần verify production).

### 2.4 Latency cao (5-10s)

**Truth:** HLS không thể xuống dưới 4-5s glass-to-glass. Shopee Live thực tế 8-15s, không phải <2s. Đây là user expectation issue, không phải tech issue.

**Lựa chọn nếu thực sự cần <2s:**
- **WebRTC (WHEP)** — SRS đã support, frontend cần thay HlsViewer bằng RTCPeerConnection. ~3-5 ngày dev. Latency 200-500ms.
- **Trade-off:** WebRTC không cache CDN được → mỗi viewer = 1 connection trực tiếp tới SRS → chỉ chứa ~50-100 viewer/origin. Hỗn hợp: WebRTC cho viewer "premium" muốn low latency, HLS cho mass.

**Priority:** P2. Để sau khi mass scale ổn định.

---

## 3. Cost breakdown ($500/tháng cap)

| Item | Provider | Cost/tháng | Note |
|---|---|---|---|
| **Origin VPS** | Hetzner CCX23 (4 vCPU, 16GB, 20TB egress) | $35 | SRS + Postgres + Redis + Go API tất cả ở đây. EU hoặc HK (gần VN). |
| **CDN** | Cloudflare Free | $0 | Có thể upgrade Pro ($25) nếu cần Polish/cache rules nâng cao. |
| **Object storage VOD** | Cloudflare R2 | ~$50 | 10GB free, sau đó $0.015/GB. 200 stream × 1h × 700MB ≈ 140GB/tháng = ~$2. Phần lớn là retrieval — R2 KHÔNG charge egress (lợi thế lớn vs S3). |
| **Domain** | Cloudflare Registrar | $10/năm | Cost-price domain. |
| **Email transactional** | Resend Free tier | $0 | 3k email/tháng free. |
| **DeepSeek AI** | API | $5-20 | Chỉ chạy khi host bật bot. |
| **Monitoring** | UptimeRobot Free + Grafana Cloud Free | $0 | 5k metrics/month free. |
| **Backup DB** | wal-g → R2 | ~$5 | Postgres point-in-time recovery. |
| **Slack/headroom** | — | $50-100 | Spike handling. |
| **TOTAL** | | **~$150-200/tháng** | Vượt budget $500 KHÔNG xảy ra ở scale 1k viewer. |

**Khi nào budget tăng:**
- 5k viewer concurrent → cần Cloudflare Pro $25 + có thể phải đổi sang BunnyCDN ($0.005/GB) khi traffic vượt CF free policy → ~$300/tháng.
- 20k viewer concurrent → cần 2-3 SRS edge node (mỗi $35) + BunnyCDN bandwidth thật ~$1.5k → tổng ~$2k/tháng.

---

## 4. Roadmap thực thi (6 tuần)

### Tuần 1: Infrastructure baseline
- [ ] Domain + Cloudflare proxy cho HLS host.
- [ ] Hetzner VPS provision + Ansible playbook deploy SRS/nginx/Postgres/Redis/Go API.
- [ ] HTTPS với Cloudflare Origin Certificate (free, không cần Let's Encrypt).
- [ ] `make deploy` script.

### Tuần 2: Reliability
- [ ] Foreground Service Android cho RTMP keep-alive (host out app vẫn live).
- [ ] Backend background job: end session sau 5 phút không RTMP.
- [ ] Frontend auto-reattach khi playback URL 404 nhiều lần.
- [ ] Grafana dashboard: viewer count, stream count, origin egress, CDN hit ratio.

### Tuần 3: Monitoring + alerts
- [ ] UptimeRobot ping `/health`.
- [ ] Slack webhook khi: CPU >80% / disk <10GB free / Postgres connections >80%.
- [ ] Sentry frontend + backend (free tier).

### Tuần 4: Load test + tuning
- [ ] `k6` script giả lập 1k concurrent viewers (HLS GET).
- [ ] Tune nginx `keepalive_requests`, `proxy_cache_lock_age`, `worker_connections`.
- [ ] Tune SRS `hls_window`, GOP nếu cần.
- [ ] Verify CDN hit ratio ≥90%.

### Tuần 5: Cost optimization
- [ ] Pre-warm CDN cho stream phổ biến (lookup cron).
- [ ] Image optimization với Cloudflare Polish.
- [ ] DB query tuning (`EXPLAIN ANALYZE` các endpoint hot path).
- [ ] R2 lifecycle: VOD >30 ngày → cold storage class.

### Tuần 6: Beta launch
- [ ] Invite 20 host pilot.
- [ ] Theo dõi metrics 1 tuần.
- [ ] Iterate dựa trên real data.

---

## 5. Quy tắc kiểm soát chi phí

1. **Never serve HLS từ origin trực tiếp ra Internet.** Luôn qua CDN. (Single biggest cost-saver.)
2. **VOD không transcode lại.** SRS DVR → FFmpeg remux (`-c copy`) → R2. KHÔNG re-encode (re-encode tốn ~5× CPU).
3. **Chat poll 3s, list 15s.** Không tăng tần suất. WebSocket có thể giảm nhưng tăng dev cost — chưa cần ở scale 1k.
4. **AI bot only when host enables.** Mỗi DeepSeek call ~$0.0002. 200 host × 100 reply/buổi = $4/buổi. Cấp host quota ngầm để tránh spam.
5. **Image asset qua Cloudflare Images** ($5/100k images stored, $1/100k delivered). Hiện tại dùng picsum placeholder — chuyển sang Cloudflare Images khi có ảnh thật.
6. **Khi cost spike đột ngột** → tự động fallback sang HLS-only (tắt LL-HLS, tăng `hls_fragment` lên 4s, giảm origin egress 50%).

---

## 6. Stability checklist (Go/No-go cho production)

- [ ] Backend health check pass 100% trong 24h.
- [ ] Origin SRS chịu được 200 RTMP host concurrent (load test).
- [ ] CDN cache hit ratio ≥ 90% với 1k viewer test.
- [ ] Host out app + vào lại trong 60s vẫn giữ stream (KHÔNG tự end).
- [ ] Viewer xem 30 phút liên tục không gặp "Lỗi phát video" (>95%).
- [ ] DB connection pool không exhaust khi 1k concurrent /chat poll.
- [ ] Bot AI reply trong 5s (p95).
- [ ] VOD upload R2 thành công trong 5 phút sau khi end stream (>98%).
- [ ] Postgres backup hằng ngày → R2.
- [ ] Runbook cho 5 incident phổ biến: SRS crash, Postgres lock, R2 4xx, Cloudflare 5xx, host RTMP drop.

---

**Owner:** Backend (Go) + DevOps shared.
**Review cadence:** mỗi 2 tuần trong 3 tháng đầu, sau đó mỗi tháng.
