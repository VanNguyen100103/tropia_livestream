# Hướng dẫn Xử lý Đồng thời & Kiến trúc Live Stream – Tropia

> Tài liệu này dành cho backend developer và Flutter developer cấp trung/cao muốn hiểu cách Tropia xử lý các vấn đề concurrency, high-throughput, và tích hợp AI trong module Live & Video.
>
> Backend giả định: **PostgreSQL + Redis + Node.js hoặc Go**
> Frontend: **Flutter 3.x (Dart)**

---

## Mục lục

1. [Race Condition – Mua cùng lúc khi còn 1 sản phẩm](#1-race-condition--mua-cùng-lúc-khi-còn-1-sản-phẩm)
2. [Xử lý Live Stream High Concurrency](#2-xử-lý-live-stream-high-concurrency)
3. [Tránh N+1 Query](#3-tránh-n1-query)
4. [Tự động đặt hàng qua Chat – Cú pháp lệnh](#4-tự-động-đặt-hàng-qua-chat--cú-pháp-lệnh)
5. [Coupon/Voucher trong Live Stream](#5-couponvoucher-trong-live-stream)
6. [AI Integration – Gợi ý câu hỏi trên Live](#6-ai-integration--gợi-ý-câu-hỏi-trên-live)

---

## 1. Race Condition – Mua cùng lúc khi còn 1 sản phẩm

### Vấn đề là gì?

Giả sử sản phẩm "Thịt bò Wagyu 300g" còn **1 cái** trong kho. Hai người dùng Alice và Bob đang xem cùng livestream. Cả hai đều bấm **"Mua ngay"** gần như đồng thời.

Luồng xảy ra nếu không có cơ chế bảo vệ:

```
T=0ms  Alice đọc: stock = 1  ✓ còn hàng
T=0ms  Bob   đọc: stock = 1  ✓ còn hàng
T=5ms  Alice ghi: stock = stock - 1 = 0
T=5ms  Bob   ghi: stock = stock - 1 = -1  ← BUG! Stock âm
T=6ms  Cả hai đều nhận được "Đặt hàng thành công"
```

Kết quả: hệ thống đã bán **2 đơn** cho **1 sản phẩm duy nhất**. Đây là race condition cổ điển trong hệ thống bán hàng.

---

### Giải pháp a) Pessimistic Lock (SELECT FOR UPDATE)

**Khi nào dùng:** Khi tỉ lệ xung đột cao, cần đảm bảo tuyệt đối chỉ 1 người mua được.

**Ý tưởng:** Khóa hàng trong database ngay khi đọc. Người đọc sau phải **chờ** cho đến khi transaction đầu tiên commit/rollback.

```sql
-- Backend (Node.js với pg client hoặc Go với pgx)
BEGIN;

-- Khóa hàng lại ngay khi SELECT – không ai khác đọc được cho đến khi COMMIT
SELECT stock FROM live_products 
WHERE id = $1 
FOR UPDATE;

-- Kiểm tra còn hàng không
-- (Thực hiện ở application layer)
-- IF stock <= 0 THEN ROLLBACK và trả về lỗi "Hết hàng"

-- Giảm tồn kho
UPDATE live_products 
SET stock = stock - 1, updated_at = NOW()
WHERE id = $1;

-- Tạo đơn hàng
INSERT INTO orders (user_id, product_id, stream_id, quantity, status, created_at)
VALUES ($2, $1, $3, 1, 'pending', NOW());

COMMIT;
```

**Ví dụ Node.js đầy đủ:**

```javascript
// backend/services/orderService.js
const { pool } = require('../db/postgres');

async function purchaseProduct({ userId, productId, streamId }) {
  const client = await pool.connect();
  
  try {
    await client.query('BEGIN');
    
    // Pessimistic lock: khóa hàng ngay khi đọc
    const { rows } = await client.query(
      'SELECT id, stock, price, name FROM live_products WHERE id = $1 FOR UPDATE',
      [productId]
    );
    
    if (rows.length === 0) {
      throw new Error('Sản phẩm không tồn tại');
    }
    
    const product = rows[0];
    
    if (product.stock <= 0) {
      // ROLLBACK ngầm khi throw trong try block
      throw new Error('Hết hàng! Sản phẩm này đã bán hết.');
    }
    
    // Giảm tồn kho
    await client.query(
      'UPDATE live_products SET stock = stock - 1, updated_at = NOW() WHERE id = $1',
      [productId]
    );
    
    // Tạo đơn hàng
    const orderResult = await client.query(
      `INSERT INTO orders (user_id, product_id, stream_id, quantity, total_price, status, created_at)
       VALUES ($1, $2, $3, 1, $4, 'pending', NOW())
       RETURNING id`,
      [userId, productId, streamId, product.price]
    );
    
    await client.query('COMMIT');
    
    return {
      success: true,
      orderId: orderResult.rows[0].id,
      message: `Đặt hàng thành công: ${product.name}`
    };
    
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}
```

**Nhược điểm của Pessimistic Lock:**
- Các request khác bị **block** chờ lock giải phóng
- Tạo **bottleneck** khi hàng nghìn người cùng mua 1 sản phẩm hot
- Không phù hợp cho livestream có spike traffic đột biến

---

### Giải pháp b) Optimistic Lock (version column)

**Khi nào dùng:** Khi tỉ lệ xung đột thấp, muốn tránh blocking. Phù hợp khi sản phẩm có stock lớn.

**Ý tưởng:** Không khóa khi đọc. Khi ghi, kiểm tra version có thay đổi chưa. Nếu version đã thay đổi (người khác đã ghi), từ chối và yêu cầu retry.

```sql
-- Bước 1: Đọc (không khóa)
SELECT id, stock, version FROM live_products WHERE id = $1;
-- Giả sử: stock = 5, version = 42

-- Bước 2: Ghi với điều kiện version phải khớp
UPDATE live_products 
SET stock = stock - 1, version = version + 1 
WHERE id = $1 
  AND version = $2    -- version = 42 (giá trị đã đọc)
  AND stock > 0;      -- vẫn còn hàng

-- Nếu rowsAffected == 0: 
--   → version đã thay đổi (người khác đã mua trước) → retry hoặc báo lỗi
-- Nếu rowsAffected == 1:
--   → Thành công, tiếp tục INSERT order
```

**Ví dụ Node.js với retry logic:**

```javascript
// backend/services/orderService.js
async function purchaseProductOptimistic({ userId, productId, streamId }, maxRetries = 3) {
  const client = await pool.connect();
  
  try {
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      // Đọc không cần lock
      const { rows } = await client.query(
        'SELECT id, stock, version, price, name FROM live_products WHERE id = $1',
        [productId]
      );
      
      if (!rows.length) throw new Error('Sản phẩm không tồn tại');
      
      const product = rows[0];
      
      if (product.stock <= 0) {
        throw new Error('Hết hàng!');
      }
      
      // Thử ghi với điều kiện version
      const updateResult = await client.query(
        `UPDATE live_products 
         SET stock = stock - 1, version = version + 1, updated_at = NOW()
         WHERE id = $1 AND version = $2 AND stock > 0`,
        [productId, product.version]
      );
      
      if (updateResult.rowCount === 1) {
        // Thành công
        const orderResult = await client.query(
          `INSERT INTO orders (user_id, product_id, stream_id, quantity, total_price, status, created_at)
           VALUES ($1, $2, $3, 1, $4, 'pending', NOW()) RETURNING id`,
          [userId, productId, streamId, product.price]
        );
        
        return { success: true, orderId: orderResult.rows[0].id };
      }
      
      // Conflict! Thử lại sau delay ngắn
      if (attempt < maxRetries) {
        await new Promise(resolve => setTimeout(resolve, 50 * attempt)); // exponential backoff nhẹ
      }
    }
    
    throw new Error('Đặt hàng thất bại sau nhiều lần thử. Vui lòng thử lại.');
    
  } finally {
    client.release();
  }
}
```

**Nhược điểm của Optimistic Lock:**
- Retry logic phức tạp hơn
- Khi nhiều người cùng xung đột (flash sale), retry storm có thể làm nặng DB

---

### Giải pháp c) Redis Atomic DECR (Nhanh nhất cho Live Stream)

**Khi nào dùng:** Live stream có hàng nghìn người xem, cần reject ngay lập tức nếu hết hàng. **Đây là giải pháp được khuyến nghị cho Tropia.**

**Ý tưởng:** Dùng Redis làm "gatekeeper" tồn kho tạm thời. `DECR` là atomic – chỉ 1 client thực hiện được tại một thời điểm.

```redis
-- Khởi tạo (khi stream bắt đầu hoặc khi admin thêm hàng)
SET product:stock:42 10  EX 86400   -- product_id=42, stock=10, TTL=1 ngày

-- Khi user mua:
-- Dùng WATCH + MULTI/EXEC (transaction trong Redis)
WATCH product:stock:42
  GET product:stock:42          -- Đọc giá trị hiện tại
  -- (Nếu ≤ 0: không cần MULTI, trả về lỗi ngay)
MULTI
  DECR product:stock:42
EXEC
-- Nếu EXEC trả về nil: key đã thay đổi trong lúc WATCH → conflict → retry
-- Nếu EXEC trả về số âm: rollback bằng INCR và báo hết hàng
```

**Ví dụ Node.js với ioredis:**

```javascript
// backend/services/stockService.js
const Redis = require('ioredis');
const redis = new Redis(process.env.REDIS_URL);

const STOCK_KEY = (productId) => `product:stock:${productId}`;
const STOCK_TTL = 86400; // 24 giờ

// Khởi tạo stock trên Redis khi stream bắt đầu
async function initProductStock(productId, stockAmount) {
  await redis.set(STOCK_KEY(productId), stockAmount, 'EX', STOCK_TTL);
}

// Atomic decrement – trả về false nếu hết hàng
async function decrementStock(productId) {
  const key = STOCK_KEY(productId);
  
  // DECR là atomic – an toàn với concurrent requests
  const newStock = await redis.decr(key);
  
  if (newStock < 0) {
    // Rollback: đã bị âm, tức là hết hàng
    await redis.incr(key); // hoàn lại
    return { success: false, reason: 'out_of_stock' };
  }
  
  return { success: true, remainingStock: newStock };
}

// Đồng bộ stock từ Redis về PostgreSQL (chạy định kỳ hoặc sau mỗi đơn)
async function syncStockToPostgres(productId) {
  const redisStock = await redis.get(STOCK_KEY(productId));
  if (redisStock !== null) {
    await pool.query(
      'UPDATE live_products SET stock = $1, updated_at = NOW() WHERE id = $2',
      [parseInt(redisStock), productId]
    );
  }
}
```

**Luồng đặt hàng đầy đủ với Redis:**

```javascript
// backend/routes/orders.js
router.post('/api/orders/live', authenticate, async (req, res) => {
  const { productId, streamId } = req.body;
  const userId = req.user.id;
  
  try {
    // 1. Redis check (cực nhanh, ~0.1ms)
    const stockResult = await decrementStock(productId);
    
    if (!stockResult.success) {
      return res.status(409).json({
        error: 'out_of_stock',
        message: 'Hết hàng! Sản phẩm này đã bán hết.'
      });
    }
    
    // 2. Enqueue order (không chờ DB write)
    await redis.xadd('orders:stream', '*', 
      'userId', userId,
      'productId', productId,
      'streamId', streamId,
      'timestamp', Date.now()
    );
    
    // 3. Trả về 200 ngay (optimistic)
    return res.status(200).json({
      success: true,
      message: 'Đang xử lý đơn hàng...',
      remainingStock: stockResult.remainingStock
    });
    
  } catch (err) {
    console.error('Order error:', err);
    return res.status(500).json({ error: 'Lỗi hệ thống, vui lòng thử lại.' });
  }
});
```

### So sánh 3 giải pháp

| Tiêu chí | Pessimistic Lock | Optimistic Lock | Redis DECR |
|---|---|---|---|
| Độ chính xác | Cao nhất | Cao | Cao (cần sync) |
| Hiệu năng | Thấp (blocking) | Trung bình | Rất cao |
| Độ phức tạp | Thấp | Trung bình | Cao hơn (cần sync) |
| Phù hợp với | Stock thấp, xung đột cao | Stock cao, xung đột thấp | Live stream spike |
| Khuyến nghị Tropia | Dự phòng | Sản phẩm thường | **Sản phẩm live** |

**Kết luận:** Tropia dùng **Redis DECR làm primary** (fast reject, không blocking), **PostgreSQL làm source of truth** (sync sau mỗi đơn hoặc theo batch 5 giây).

---

## 2. Xử lý Live Stream High Concurrency

### Bài toán thực tế

Một buổi livestream của Tropia Fresh Market có thể có:
- **5.000 viewers** xem đồng thời
- **500 likes/giây** (đặc biệt khi host khuyến khích "like x10")
- **200 chat messages/giây**
- **50 đơn hàng/giây** trong flash sale

Nếu ghi tất cả thẳng vào PostgreSQL: **database sẽ sập ngay**.

---

### Kiến trúc tổng thể

```
                        ┌─────────────────────────────┐
                        │      Load Balancer (Nginx)    │
                        └──────────────┬──────────────┘
                                       │
              ┌────────────────────────┼────────────────────────┐
              ▼                        ▼                         ▼
      ┌───────────────┐      ┌───────────────┐       ┌───────────────┐
      │  API Server 1  │      │  API Server 2  │       │  API Server 3  │
      │  (stateless)   │      │  (stateless)   │       │  (stateless)   │
      └───────┬────────┘      └───────┬────────┘       └───────┬────────┘
              └────────────────┬──────┘─────────────────────────┘
                               │
                    ┌──────────┴──────────┐
                    │                      │
             ┌──────▼──────┐      ┌────────▼────────┐
             │    Redis     │      │   Redis Streams  │
             │  (cache,     │      │  / Kafka queue   │
             │   pubsub,    │      │  (orders, events)│
             │   sessions)  │      └────────┬────────┘
             └─────────────┘               │
                                  ┌─────────▼──────────┐
                                  │   Worker Processes   │
                                  │  (order processing,  │
                                  │   notifications)     │
                                  └─────────┬──────────┘
                                            │
                                   ┌────────▼────────┐
                                   │   PostgreSQL     │
                                   │  (source of      │
                                   │   truth)         │
                                   └─────────────────┘
```

---

### a) Event Queue – Orders qua Redis Streams

Thay vì ghi thẳng vào DB, đặt hàng đi qua **queue**. Worker xử lý tuần tự, tránh hammering database.

```javascript
// backend/workers/orderWorker.js
const Redis = require('ioredis');
const redis = new Redis(process.env.REDIS_URL);

const STREAM_KEY = 'orders:stream';
const CONSUMER_GROUP = 'order-processors';
const CONSUMER_NAME = `worker-${process.pid}`;

async function startOrderWorker() {
  // Tạo consumer group (chỉ cần 1 lần)
  try {
    await redis.xgroup('CREATE', STREAM_KEY, CONSUMER_GROUP, '$', 'MKSTREAM');
  } catch (e) {
    if (!e.message.includes('BUSYGROUP')) throw e;
  }
  
  console.log(`Order worker ${CONSUMER_NAME} started`);
  
  while (true) {
    // Đọc batch tối đa 10 orders, chờ tối đa 2 giây
    const results = await redis.xreadgroup(
      'GROUP', CONSUMER_GROUP, CONSUMER_NAME,
      'COUNT', 10,
      'BLOCK', 2000,
      'STREAMS', STREAM_KEY, '>'
    );
    
    if (!results) continue;
    
    const [, messages] = results[0];
    
    for (const [messageId, fields] of messages) {
      const order = {
        userId: fields[fields.indexOf('userId') + 1],
        productId: fields[fields.indexOf('productId') + 1],
        streamId: fields[fields.indexOf('streamId') + 1],
      };
      
      try {
        await processOrder(order);
        // Acknowledge: xóa khỏi pending list
        await redis.xack(STREAM_KEY, CONSUMER_GROUP, messageId);
      } catch (err) {
        console.error(`Order processing failed for message ${messageId}:`, err);
        // Không ACK → sẽ được retry bởi worker khác sau timeout
      }
    }
  }
}

async function processOrder({ userId, productId, streamId }) {
  // Ghi vào PostgreSQL (đã an toàn vì qua queue)
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    
    // Sync stock từ Redis về Postgres
    const redisStock = await redis.get(`product:stock:${productId}`);
    
    const orderResult = await client.query(
      `INSERT INTO orders (user_id, product_id, stream_id, quantity, status, created_at)
       VALUES ($1, $2, $3, 1, 'confirmed', NOW()) RETURNING id`,
      [userId, productId, streamId]
    );
    
    if (redisStock !== null) {
      await client.query(
        'UPDATE live_products SET stock = $1, updated_at = NOW() WHERE id = $2',
        [parseInt(redisStock), productId]
      );
    }
    
    await client.query('COMMIT');
    
    // Gửi notification cho user
    await sendOrderNotification(userId, orderResult.rows[0].id);
    
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

startOrderWorker().catch(console.error);
```

---

### b) Write Coalescing – Gộp Likes mỗi 500ms

Thay vì ghi DB mỗi khi user like, **gom lại** và ghi 1 lần mỗi 500ms.

```javascript
// backend/services/likeService.js
class LikeCoalescer {
  constructor() {
    this.buffer = new Map(); // streamId -> likeCount
    this.flushInterval = 500; // ms
    this.start();
  }
  
  // Ghi vào buffer (instant, không đụng DB)
  async addLike(streamId) {
    const current = this.buffer.get(streamId) || 0;
    this.buffer.set(streamId, current + 1);
    
    // Tăng counter Redis ngay để broadcast realtime
    await redis.incr(`stream:likes:${streamId}`);
    
    return { success: true };
  }
  
  // Flush buffer vào PostgreSQL mỗi 500ms
  start() {
    setInterval(async () => {
      if (this.buffer.size === 0) return;
      
      const snapshot = new Map(this.buffer);
      this.buffer.clear();
      
      const updates = Array.from(snapshot.entries());
      
      // Bulk update một lần (thay vì N queries)
      const values = updates.map(([streamId, count], i) => 
        `($${i * 2 + 1}, $${i * 2 + 2})`
      ).join(', ');
      
      const params = updates.flatMap(([streamId, count]) => [count, streamId]);
      
      try {
        await pool.query(
          `UPDATE live_streams AS ls
           SET like_count = like_count + v.count
           FROM (VALUES ${values}) AS v(count, stream_id)
           WHERE ls.id = v.stream_id::int`,
          params
        );
      } catch (err) {
        console.error('Like flush failed:', err);
        // Merge lại vào buffer để retry
        for (const [streamId, count] of snapshot) {
          this.buffer.set(streamId, (this.buffer.get(streamId) || 0) + count);
        }
      }
    }, this.flushInterval);
  }
}

const likeCoalescer = new LikeCoalescer();
module.exports = { likeCoalescer };
```

---

### c) Fan-out cho Chat – Redis PubSub

Chat messages cần được gửi đến **tất cả viewers** đang xem cùng stream. Dùng Redis PubSub kết hợp WebSocket.

```javascript
// backend/services/chatService.js
const WebSocket = require('ws');
const redis = new Redis(process.env.REDIS_URL);
const redisSub = new Redis(process.env.REDIS_URL); // Redis riêng cho subscribe

const CHAT_CHANNEL = (streamId) => `chat:${streamId}`;

// Map: streamId -> Set of WebSocket connections
const streamConnections = new Map();

function setupWebSocketServer(server) {
  const wss = new WebSocket.Server({ server, path: '/ws/live' });
  
  wss.on('connection', async (ws, req) => {
    const streamId = req.url.split('/').pop();
    
    // Đăng ký connection
    if (!streamConnections.has(streamId)) {
      streamConnections.set(streamId, new Set());
      
      // Subscribe Redis channel cho stream này
      await redisSub.subscribe(CHAT_CHANNEL(streamId));
    }
    streamConnections.get(streamId).add(ws);
    
    ws.on('close', () => {
      streamConnections.get(streamId)?.delete(ws);
    });
  });
  
  // Nhận message từ Redis → broadcast đến tất cả WebSocket clients
  redisSub.on('message', (channel, message) => {
    const streamId = channel.replace('chat:', '');
    const connections = streamConnections.get(streamId);
    
    if (!connections) return;
    
    for (const ws of connections) {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(message);
      }
    }
  });
}

// Gửi chat message
async function sendChatMessage({ streamId, userId, username, text, isCommand }) {
  const message = JSON.stringify({
    type: 'chat',
    userId,
    username,
    text,
    isCommand,
    timestamp: Date.now()
  });
  
  // Publish đến tất cả subscriber (các WebSocket servers khác)
  await redis.publish(CHAT_CHANNEL(streamId), message);
  
  // Lưu vào PostgreSQL async (không block response)
  setImmediate(async () => {
    await pool.query(
      'INSERT INTO chat_messages (stream_id, user_id, content, created_at) VALUES ($1, $2, $3, NOW())',
      [streamId, userId, text]
    );
  });
}
```

---

### d) Circuit Breaker cho Order Service

Khi order service bị quá tải, **dừng gửi thêm request** thay vì để queue tràn.

```javascript
// backend/utils/circuitBreaker.js
class CircuitBreaker {
  constructor(options = {}) {
    this.failureThreshold = options.failureThreshold || 5;
    this.successThreshold = options.successThreshold || 2;
    this.timeout = options.timeout || 30000; // 30 giây
    
    this.state = 'CLOSED'; // CLOSED | OPEN | HALF_OPEN
    this.failures = 0;
    this.successes = 0;
    this.nextAttempt = null;
  }
  
  async call(fn) {
    if (this.state === 'OPEN') {
      if (Date.now() < this.nextAttempt) {
        throw new Error('Service tạm thời không khả dụng. Vui lòng thử lại sau.');
      }
      this.state = 'HALF_OPEN';
    }
    
    try {
      const result = await fn();
      this.onSuccess();
      return result;
    } catch (err) {
      this.onFailure();
      throw err;
    }
  }
  
  onSuccess() {
    this.failures = 0;
    if (this.state === 'HALF_OPEN') {
      this.successes++;
      if (this.successes >= this.successThreshold) {
        this.state = 'CLOSED';
        this.successes = 0;
      }
    }
  }
  
  onFailure() {
    this.failures++;
    if (this.failures >= this.failureThreshold) {
      this.state = 'OPEN';
      this.nextAttempt = Date.now() + this.timeout;
    }
  }
}

const orderCircuitBreaker = new CircuitBreaker({ 
  failureThreshold: 5, 
  timeout: 15000 
});

module.exports = { orderCircuitBreaker };

// Dùng:
// await orderCircuitBreaker.call(() => enqueueOrder(orderData));
```

---

### e) Luồng đặt hàng đầy đủ

```
User bấm "Mua ngay" trong Flutter app
        │
        ▼
API validate JWT token (~1ms)
        │
        ▼
Redis DECR product:stock:{id} (atomic, ~0.1ms)
        │
        ├── Stock < 0? → INCR lại, trả 409 "Hết hàng"
        │
        ▼
Enqueue order vào Redis Stream / Kafka (~0.5ms)
        │
        ▼
Trả về HTTP 200 ngay (optimistic response)
"Đang xử lý đơn hàng của bạn..."
        │
        ▼ (async, background)
Worker dequeue order
        │
        ▼
Ghi vào PostgreSQL orders table
        │
        ▼
Gửi push notification + WebSocket event
"✅ Đặt hàng thành công! Mã đơn: #TRP2024xxxxx"
```

**Tổng thời gian user cảm nhận:** < 50ms (thay vì 500-2000ms nếu ghi thẳng vào DB).

---

## 3. Tránh N+1 Query

### N+1 là gì?

N+1 query xảy ra khi bạn thực hiện **1 query** lấy danh sách, rồi **N query thêm** cho mỗi item trong danh sách.

**Ví dụ xấu trong Tropia:**

```javascript
// BAD: N+1 query – Sẽ gây chậm nghiêm trọng khi có nhiều stream
async function getLiveStreams() {
  // 1 query lấy danh sách streams
  const streams = await pool.query(
    "SELECT * FROM streams WHERE status = 'live'"
  );
  
  // N query lấy products cho mỗi stream
  for (const stream of streams.rows) {
    const products = await pool.query(
      'SELECT * FROM products WHERE stream_id = $1',
      [stream.id]
    );
    stream.products = products.rows;
    
    // N query lấy thông tin seller
    const seller = await pool.query(
      'SELECT * FROM sellers WHERE id = $1',
      [stream.seller_id]
    );
    stream.seller = seller.rows[0];
  }
  
  return streams.rows;
}

// Nếu có 20 streams: 1 + 20 + 20 = 41 queries!
// Nếu có 100 streams: 1 + 100 + 100 = 201 queries!
```

---

### Giải pháp a) JOIN với JSON_AGG (PostgreSQL)

Gộp tất cả dữ liệu trong **1 query duy nhất**:

```sql
SELECT 
  s.id,
  s.title,
  s.status,
  s.viewer_count,
  s.like_count,
  s.thumbnail_url,
  s.started_at,
  -- Nest products dưới dạng JSON array
  COALESCE(
    json_agg(
      json_build_object(
        'id', p.id,
        'slot', p.slot_number,
        'name', p.name,
        'price', p.price,
        'original_price', p.original_price,
        'stock', p.stock,
        'image_url', p.image_url
      )
    ) FILTER (WHERE p.id IS NOT NULL),
    '[]'
  ) AS products,
  -- Nest seller dưới dạng JSON object
  json_build_object(
    'id', sel.id,
    'name', sel.shop_name,
    'avatar_url', sel.avatar_url,
    'verified', sel.is_verified
  ) AS seller
FROM streams s
LEFT JOIN live_products p ON p.stream_id = s.id AND p.is_active = true
JOIN sellers sel ON sel.id = s.seller_id
WHERE s.status = 'live'
  AND s.started_at > NOW() - INTERVAL '6 hours'
GROUP BY s.id, sel.id
ORDER BY s.viewer_count DESC
LIMIT 20;
```

**Ví dụ Node.js:**

```javascript
// backend/services/streamService.js
async function getLiveStreamsWithDetails() {
  const query = `
    SELECT 
      s.id, s.title, s.status, s.viewer_count, s.like_count,
      s.thumbnail_url, s.stream_url, s.started_at,
      COALESCE(
        json_agg(
          json_build_object(
            'id', p.id, 'slot', p.slot_number, 'name', p.name,
            'price', p.price, 'original_price', p.original_price,
            'stock', p.stock, 'image_url', p.image_url
          )
        ) FILTER (WHERE p.id IS NOT NULL), '[]'
      ) AS products,
      json_build_object(
        'id', sel.id, 'name', sel.shop_name,
        'avatar_url', sel.avatar_url, 'verified', sel.is_verified
      ) AS seller
    FROM streams s
    LEFT JOIN live_products p ON p.stream_id = s.id AND p.is_active = true
    JOIN sellers sel ON sel.id = s.seller_id
    WHERE s.status = 'live'
    GROUP BY s.id, sel.id
    ORDER BY s.viewer_count DESC
    LIMIT 20
  `;
  
  const { rows } = await pool.query(query);
  return rows; // Trả về đúng 1 query, không N+1
}
```

---

### Giải pháp b) Batch Loading (DataLoader pattern)

Khi dùng GraphQL hoặc cần load dữ liệu theo batch:

```javascript
// backend/loaders/productLoader.js
const DataLoader = require('dataloader');

// Batch function: nhận mảng stream IDs, trả về mảng products
const batchLoadProducts = async (streamIds) => {
  const { rows } = await pool.query(
    'SELECT * FROM live_products WHERE stream_id = ANY($1) AND is_active = true ORDER BY slot_number',
    [streamIds]
  );
  
  // Group by stream_id
  const grouped = {};
  for (const product of rows) {
    if (!grouped[product.stream_id]) grouped[product.stream_id] = [];
    grouped[product.stream_id].push(product);
  }
  
  // Trả về đúng thứ tự với streamIds
  return streamIds.map(id => grouped[id] || []);
};

const productLoader = new DataLoader(batchLoadProducts);

// Dùng trong resolver:
// const products = await productLoader.load(stream.id);
// DataLoader tự động gom nhiều .load() thành 1 query
```

---

### Giải pháp c) Cache tại API Layer

```javascript
// backend/services/streamService.js
const STREAM_CACHE_KEY = 'live:streams:list';
const STREAM_CACHE_TTL = 30; // 30 giây – đủ tươi cho live data

async function getCachedLiveStreams() {
  // 1. Thử đọc từ Redis cache
  const cached = await redis.get(STREAM_CACHE_KEY);
  if (cached) {
    return JSON.parse(cached);
  }
  
  // 2. Cache miss: query DB
  const streams = await getLiveStreamsWithDetails();
  
  // 3. Lưu vào cache 30 giây
  await redis.setex(STREAM_CACHE_KEY, STREAM_CACHE_TTL, JSON.stringify(streams));
  
  return streams;
}

// Invalidate cache khi có thay đổi quan trọng
async function invalidateStreamCache() {
  await redis.del(STREAM_CACHE_KEY);
}
```

---

### Tóm tắt chống N+1

| Kỹ thuật | Dùng khi | Số queries |
|---|---|---|
| JOIN + JSON_AGG | REST API, dữ liệu có cấu trúc | 1 |
| DataLoader | GraphQL | 1 per type |
| Eager loading (ORM) | Dùng Sequelize/Prisma | 1-2 |
| Redis cache | Read-heavy, chấp nhận stale data | 0 (cache hit) |

---

## 4. Tự động đặt hàng qua Chat – Cú pháp lệnh

### Thiết kế cú pháp

Module chat của Tropia hỗ trợ **chat command** – người dùng gõ lệnh trực tiếp vào ô chat để thực hiện các hành động mua sắm.

#### Cú pháp đặt hàng

```
/mua [số_sản_phẩm] [số_lượng]

Ví dụ:
  /mua 5        → mua sản phẩm số 5, số lượng = 1 (mặc định)
  /mua 5 2      → mua sản phẩm số 5, số lượng = 2
  /mua 5 x2     → mua sản phẩm số 5, số lượng = 2 (cú pháp thay thế)
  /mua 3 x10    → mua sản phẩm số 3, số lượng = 10
```

#### Cú pháp xem sản phẩm

```
/sp [số]    → xem chi tiết sản phẩm số [số] (ảnh, mô tả, giá)
/gia [số]   → xem giá sản phẩm số [số]
/con [số]   → xem còn bao nhiêu sản phẩm số [số] trong kho
```

#### Cú pháp voucher

```
/voucher        → xem danh sách voucher đang có trong stream
/luu [code]     → lưu voucher vào tài khoản
              Ví dụ: /luu FRESH20  → lưu voucher giảm 20%
```

#### Cú pháp giỏ hàng

```
/giohang      → xem giỏ hàng hiện tại
/xoa [số]     → xóa sản phẩm số [số] khỏi giỏ hàng
/dat          → xác nhận đặt tất cả sản phẩm trong giỏ
```

---

### Flutter: ChatCommandParser

```dart
// lib/features/live/utils/chat_command_parser.dart

/// Các loại lệnh chat được hỗ trợ
abstract class ChatCommand {
  const ChatCommand();
}

class BuyCommand extends ChatCommand {
  final int productSlot;
  final int quantity;
  const BuyCommand({required this.productSlot, required this.quantity});
}

class ViewProductCommand extends ChatCommand {
  final int productSlot;
  const ViewProductCommand({required this.productSlot});
}

class ViewPriceCommand extends ChatCommand {
  final int productSlot;
  const ViewPriceCommand({required this.productSlot});
}

class ViewStockCommand extends ChatCommand {
  final int productSlot;
  const ViewStockCommand({required this.productSlot});
}

class VoucherListCommand extends ChatCommand {
  const VoucherListCommand();
}

class SaveVoucherCommand extends ChatCommand {
  final String code;
  const SaveVoucherCommand({required this.code});
}

class CartCommand extends ChatCommand {
  const CartCommand();
}

class RemoveFromCartCommand extends ChatCommand {
  final int productSlot;
  const RemoveFromCartCommand({required this.productSlot});
}

class CheckoutCommand extends ChatCommand {
  const CheckoutCommand();
}

/// Parser chuyển text thành ChatCommand
class ChatCommandParser {
  // Patterns regex cho từng lệnh
  static final _buyPattern = RegExp(
    r'^/mua\s+(\d+)(?:\s+x?(\d+))?$',
    caseSensitive: false,
  );
  static final _viewPattern = RegExp(
    r'^/sp\s+(\d+)$',
    caseSensitive: false,
  );
  static final _pricePattern = RegExp(
    r'^/gia\s+(\d+)$',
    caseSensitive: false,
  );
  static final _stockPattern = RegExp(
    r'^/con\s+(\d+)$',
    caseSensitive: false,
  );
  static final _voucherListPattern = RegExp(
    r'^/voucher$',
    caseSensitive: false,
  );
  static final _saveVoucherPattern = RegExp(
    r'^/luu\s+([A-Za-z0-9_\-]+)$',
    caseSensitive: false,
  );
  static final _cartPattern = RegExp(
    r'^/giohang$',
    caseSensitive: false,
  );
  static final _removePattern = RegExp(
    r'^/xoa\s+(\d+)$',
    caseSensitive: false,
  );
  static final _checkoutPattern = RegExp(
    r'^/dat$',
    caseSensitive: false,
  );

  /// Parse text thành ChatCommand, trả về null nếu không phải lệnh
  static ChatCommand? parse(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('/')) return null;

    // /mua 5 hoặc /mua 5 2 hoặc /mua 5 x2
    final buyMatch = _buyPattern.firstMatch(trimmed);
    if (buyMatch != null) {
      final slot = int.parse(buyMatch.group(1)!);
      final qty = int.tryParse(buyMatch.group(2) ?? '1') ?? 1;
      return BuyCommand(
        productSlot: slot,
        quantity: qty.clamp(1, 99),
      );
    }

    // /sp 3
    final viewMatch = _viewPattern.firstMatch(trimmed);
    if (viewMatch != null) {
      return ViewProductCommand(productSlot: int.parse(viewMatch.group(1)!));
    }

    // /gia 3
    final priceMatch = _pricePattern.firstMatch(trimmed);
    if (priceMatch != null) {
      return ViewPriceCommand(productSlot: int.parse(priceMatch.group(1)!));
    }

    // /con 3
    final stockMatch = _stockPattern.firstMatch(trimmed);
    if (stockMatch != null) {
      return ViewStockCommand(productSlot: int.parse(stockMatch.group(1)!));
    }

    // /voucher
    if (_voucherListPattern.hasMatch(trimmed)) {
      return const VoucherListCommand();
    }

    // /luu CODE
    final saveVoucherMatch = _saveVoucherPattern.firstMatch(trimmed);
    if (saveVoucherMatch != null) {
      return SaveVoucherCommand(code: saveVoucherMatch.group(1)!.toUpperCase());
    }

    // /giohang
    if (_cartPattern.hasMatch(trimmed)) {
      return const CartCommand();
    }

    // /xoa 2
    final removeMatch = _removePattern.firstMatch(trimmed);
    if (removeMatch != null) {
      return RemoveFromCartCommand(productSlot: int.parse(removeMatch.group(1)!));
    }

    // /dat
    if (_checkoutPattern.hasMatch(trimmed)) {
      return const CheckoutCommand();
    }

    return null; // Lệnh không hợp lệ
  }
}
```

---

### Flutter: Xử lý command trong LiveProvider

```dart
// lib/features/live/providers/live_provider.dart (phần bổ sung)

/// Model cho chat message (bao gồm system messages từ bot)
class ChatMessage {
  final String userId;
  final String username;
  final String text;
  final bool isCommand;
  final bool isSystemMessage; // true = bot response
  final DateTime timestamp;

  const ChatMessage({
    required this.userId,
    required this.username,
    required this.text,
    this.isCommand = false,
    this.isSystemMessage = false,
    required this.timestamp,
  });
}

// Trong LiveProvider:
Future<void> sendComment(String text) async {
  if (text.trim().isEmpty) return;

  AppLogger.logUserEvent(
    action: 'chat_message_sent',
    context: 'LiveProvider',
    metadata: {'text': text, 'streamId': currentStream?.id},
  );

  // Parse command trước
  final command = ChatCommandParser.parse(text.trim());

  // Thêm message của user vào chat (luôn hiển thị, dù là command)
  _addChatMessage(ChatMessage(
    userId: _currentUserId,
    username: _currentUsername,
    text: text,
    isCommand: command != null,
    isSystemMessage: false,
    timestamp: DateTime.now(),
  ));

  // Xử lý command nếu có
  if (command != null) {
    await _handleChatCommand(command);
  }

  notifyListeners();
}

Future<void> _handleChatCommand(ChatCommand command) async {
  switch (command) {
    case BuyCommand(:final productSlot, :final quantity):
      await _handleBuyCommand(productSlot, quantity);

    case ViewProductCommand(:final productSlot):
      await _handleViewProductCommand(productSlot);

    case ViewPriceCommand(:final productSlot):
      await _handleViewPriceCommand(productSlot);

    case ViewStockCommand(:final productSlot):
      await _handleViewStockCommand(productSlot);

    case VoucherListCommand():
      await _handleVoucherListCommand();

    case SaveVoucherCommand(:final code):
      await _handleSaveVoucherCommand(code);

    case CartCommand():
      await _handleCartCommand();

    case RemoveFromCartCommand(:final productSlot):
      await _handleRemoveFromCartCommand(productSlot);

    case CheckoutCommand():
      await _handleCheckoutCommand();
  }
}

Future<void> _handleBuyCommand(int slot, int quantity) async {
  final product = _getProductBySlot(slot);

  if (product == null) {
    _addBotMessage('❌ Không tìm thấy sản phẩm số $slot. Gõ /sp [số] để xem danh sách.');
    return;
  }

  if (product.stock <= 0) {
    _addBotMessage('⚠️ Hết hàng! Sản phẩm số $slot (${product.name}) đã bán hết.');
    AppLogger.logUserEvent(
      action: 'buy_command_failed_out_of_stock',
      context: 'LiveProvider',
      metadata: {'slot': slot, 'productId': product.id},
    );
    return;
  }

  if (quantity > product.stock) {
    _addBotMessage(
      '⚠️ Chỉ còn ${product.stock} sản phẩm. '
      'Đang thêm ${product.stock} vào giỏ.'
    );
  }

  final actualQty = quantity.clamp(1, product.stock);
  final totalPrice = product.salePrice * actualQty;
  final formattedPrice = _formatCurrency(totalPrice);

  // Thêm vào giỏ hàng (mock)
  _cart.addOrUpdate(product, actualQty);

  _addBotMessage(
    '🛒 Đã thêm ${product.name} x$actualQty vào giỏ hàng! '
    'Giá: $formattedPrice'
  );

  AppLogger.logUserEvent(
    action: 'buy_command_success',
    context: 'LiveProvider',
    metadata: {
      'slot': slot,
      'productId': product.id,
      'quantity': actualQty,
      'totalPrice': totalPrice,
    },
  );
}

Future<void> _handleViewProductCommand(int slot) async {
  final product = _getProductBySlot(slot);
  if (product == null) {
    _addBotMessage('❌ Không tìm thấy sản phẩm số $slot');
    return;
  }
  
  // Mở popup sản phẩm
  selectedProduct = product;
  showProductPopup = true;
  _addBotMessage('📦 ${product.name} – ${_formatCurrency(product.salePrice)}');
}

Future<void> _handleCheckoutCommand() async {
  if (_cart.isEmpty) {
    _addBotMessage('🛒 Giỏ hàng của bạn đang trống. Gõ /mua [số] để thêm sản phẩm.');
    return;
  }

  // Simulate API call
  await Future.delayed(const Duration(seconds: 1));
  final orderId = 'TRP${DateTime.now().millisecondsSinceEpoch}';

  _addBotMessage('✅ Đặt hàng thành công! Mã đơn: #$orderId');
  _cart.clear();

  AppLogger.logUserEvent(
    action: 'checkout_command_success',
    context: 'LiveProvider',
    metadata: {'orderId': orderId},
  );
}

/// Helper: thêm bot response vào chat
void _addBotMessage(String text) {
  _addChatMessage(ChatMessage(
    userId: 'bot',
    username: 'Tropia Bot',
    text: text,
    isSystemMessage: true,
    timestamp: DateTime.now(),
  ));
}

LiveProduct? _getProductBySlot(int slot) {
  try {
    return currentStream?.products.firstWhere((p) => p.slotNumber == slot);
  } catch (_) {
    return null;
  }
}
```

---

### Flutter: UI hiển thị chat có system messages

```dart
// lib/features/live/widgets/live_chat_widget.dart (phần message item)

Widget _buildChatMessage(ChatMessage message) {
  if (message.isSystemMessage) {
    // Bot messages: nổi bật hơn
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.primaryGreen.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.smart_toy_outlined, size: 14, color: AppColors.primaryGreen),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Normal chat message
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
    child: RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '${message.username} ',
            style: TextStyle(
              color: message.isCommand ? AppColors.accentOrange : Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(
            text: message.text,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
```

---

## 5. Coupon/Voucher trong Live Stream

### Thiết kế Database

```sql
-- Bảng voucher cho live stream
CREATE TABLE live_vouchers (
  id          SERIAL PRIMARY KEY,
  stream_id   INTEGER REFERENCES streams(id) ON DELETE CASCADE,
  code        VARCHAR(50) UNIQUE NOT NULL,
  type        VARCHAR(20) NOT NULL, -- 'percent', 'fixed', 'freeship'
  value       DECIMAL(10, 2) NOT NULL, -- Phần trăm hoặc số tiền
  min_order   DECIMAL(10, 2) DEFAULT 0,
  max_claims  INTEGER NOT NULL DEFAULT 100,
  claimed_count INTEGER NOT NULL DEFAULT 0,
  starts_at   TIMESTAMP NOT NULL,
  expires_at  TIMESTAMP NOT NULL,
  is_flash    BOOLEAN DEFAULT false, -- Flash voucher (đếm ngược)
  created_at  TIMESTAMP DEFAULT NOW()
);

-- Index để tăng tốc lookup
CREATE INDEX idx_live_vouchers_stream ON live_vouchers(stream_id);
CREATE INDEX idx_live_vouchers_code ON live_vouchers(code);

-- Bảng lưu voucher của user
CREATE TABLE user_saved_vouchers (
  id          SERIAL PRIMARY KEY,
  user_id     INTEGER REFERENCES users(id) ON DELETE CASCADE,
  voucher_id  INTEGER REFERENCES live_vouchers(id) ON DELETE CASCADE,
  saved_at    TIMESTAMP DEFAULT NOW(),
  used_at     TIMESTAMP,
  UNIQUE(user_id, voucher_id) -- Không lưu trùng
);
```

---

### Atomic Voucher Claim – Chống race condition

```sql
-- Lưu voucher: atomic, tự động từ chối nếu đã hết
UPDATE live_vouchers 
SET claimed_count = claimed_count + 1
WHERE id = $1 
  AND claimed_count < max_claims    -- Còn slot
  AND expires_at > NOW()             -- Chưa hết hạn
RETURNING id, code, type, value, expires_at;

-- 0 rows returned = voucher đã hết hoặc hết hạn
```

**Ví dụ Node.js:**

```javascript
// backend/services/voucherService.js
async function saveVoucher({ userId, voucherCode, streamId }) {
  const client = await pool.connect();
  
  try {
    await client.query('BEGIN');
    
    // Tìm voucher trong stream
    const { rows: vouchers } = await client.query(
      `SELECT id, code, type, value, max_claims, claimed_count, expires_at
       FROM live_vouchers 
       WHERE code = $1 AND stream_id = $2`,
      [voucherCode, streamId]
    );
    
    if (!vouchers.length) {
      throw new Error('Mã voucher không hợp lệ trong stream này.');
    }
    
    const voucher = vouchers[0];
    
    // Kiểm tra user đã lưu chưa
    const { rows: existing } = await client.query(
      'SELECT id FROM user_saved_vouchers WHERE user_id = $1 AND voucher_id = $2',
      [userId, voucher.id]
    );
    
    if (existing.length > 0) {
      throw new Error('Bạn đã lưu voucher này rồi.');
    }
    
    // Atomic claim: tăng claimed_count với điều kiện
    const { rows: claimed } = await client.query(
      `UPDATE live_vouchers 
       SET claimed_count = claimed_count + 1
       WHERE id = $1 
         AND claimed_count < max_claims 
         AND expires_at > NOW()
       RETURNING id`,
      [voucher.id]
    );
    
    if (!claimed.length) {
      throw new Error('Voucher đã hết lượt lưu hoặc đã hết hạn!');
    }
    
    // Lưu cho user
    await client.query(
      'INSERT INTO user_saved_vouchers (user_id, voucher_id) VALUES ($1, $2)',
      [userId, voucher.id]
    );
    
    await client.query('COMMIT');
    
    return {
      success: true,
      voucher: {
        code: voucher.code,
        type: voucher.type,
        value: voucher.value,
        expiresAt: voucher.expires_at
      },
      message: `Đã lưu voucher ${voucher.code}!`
    };
    
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}
```

---

### Flash Voucher với Redis (Countdown)

```javascript
// backend/services/flashVoucherService.js

// Khởi tạo flash voucher trên Redis khi stream host phát
async function launchFlashVoucher(voucherId, maxClaims, durationSeconds) {
  const key = `flash_voucher:${voucherId}`;
  
  // Set count và TTL đồng thời
  await redis.pipeline()
    .set(`${key}:remaining`, maxClaims)
    .expire(`${key}:remaining`, durationSeconds)
    .set(`${key}:active`, '1')
    .expire(`${key}:active`, durationSeconds)
    .exec();
  
  // Broadcast tới tất cả viewers qua WebSocket
  await redis.publish(`stream:${streamId}:events`, JSON.stringify({
    type: 'flash_voucher_launched',
    voucherId,
    maxClaims,
    expiresIn: durationSeconds,
  }));
}

// Claim flash voucher
async function claimFlashVoucher(userId, voucherId) {
  const remainingKey = `flash_voucher:${voucherId}:remaining`;
  
  // Atomic decrement
  const remaining = await redis.decr(remainingKey);
  
  if (remaining < 0) {
    await redis.incr(remainingKey); // rollback
    return { success: false, reason: 'voucher_exhausted' };
  }
  
  // Persist vào PostgreSQL async
  setImmediate(async () => {
    await saveVoucherToDb(userId, voucherId);
  });
  
  return { success: true, remaining };
}
```

---

### Flutter: Voucher stacking rules

```dart
// lib/features/live/models/voucher_model.dart

enum VoucherType { percent, fixed, freeShip }
enum VoucherCategory { live, platform, seller }

class Voucher {
  final String id;
  final String code;
  final VoucherType type;
  final double value;
  final double minOrder;
  final VoucherCategory category;
  final DateTime expiresAt;

  const Voucher({
    required this.id,
    required this.code,
    required this.type,
    required this.value,
    required this.minOrder,
    required this.category,
    required this.expiresAt,
  });
}

// Stacking rules validator
class VoucherStackingValidator {
  /// Tropia cho phép tối đa: 1 live voucher + 1 platform voucher
  static List<Voucher> validateStack(List<Voucher> selected) {
    Voucher? liveVoucher;
    Voucher? platformVoucher;
    
    for (final voucher in selected) {
      if (voucher.category == VoucherCategory.live) {
        liveVoucher = voucher;
      } else if (voucher.category == VoucherCategory.platform) {
        platformVoucher = voucher;
      }
    }
    
    return [
      if (liveVoucher != null) liveVoucher,
      if (platformVoucher != null) platformVoucher,
    ];
  }
  
  static double calculateDiscount(List<Voucher> vouchers, double orderTotal) {
    double discount = 0;
    double remaining = orderTotal;
    
    for (final voucher in vouchers) {
      if (remaining < voucher.minOrder) continue;
      
      switch (voucher.type) {
        case VoucherType.percent:
          discount += remaining * (voucher.value / 100);
        case VoucherType.fixed:
          discount += voucher.value;
        case VoucherType.freeShip:
          // Handled separately in shipping calculation
          break;
      }
    }
    
    return discount.clamp(0, orderTotal);
  }
}
```

---

## 6. AI Integration – Gợi ý câu hỏi trên Live

### Tổng quan tính năng

Trong khi xem livestream, AI phân tích sản phẩm đang được giới thiệu và 10 tin nhắn chat gần nhất, sau đó gợi ý 3 câu hỏi phù hợp mà viewer có thể tap để gửi ngay.

**Luồng:**
```
Product thay đổi hoặc mỗi 30 giây
        │
        ▼
Flutter gọi POST /api/live/{streamId}/ai-suggestions
Body: { currentProductId, recentComments: [...last10] }
        │
        ▼
Backend gọi Claude Haiku API (nhanh + rẻ)
        │
        ▼
Response: { suggestions: ["câu 1", "câu 2", "câu 3"] }
        │
        ▼
Flutter hiển thị 3 chips bên trên ô nhập chat
        │
        ▼
User tap chip → auto-fill vào ô chat (có thể sửa trước khi gửi)
```

---

### Backend: Claude API Integration

```javascript
// backend/services/aiSuggestionService.js
// LƯU Ý: KHÔNG BAO GIỜ đặt API key trong Flutter app
// API key chỉ tồn tại trên server

const Anthropic = require('@anthropic-ai/sdk');

const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY,
});

async function generateLiveSuggestions({ product, recentComments }) {
  const commentsSummary = recentComments.length > 0
    ? recentComments.slice(-10).join('; ')
    : 'Chưa có chat nào';
  
  const prompt = `Bạn là trợ lý cho người xem livestream bán hàng tại Việt Nam.
Sản phẩm đang được giới thiệu: ${product.name}
Giá: ${product.price.toLocaleString('vi-VN')}đ
Mô tả ngắn: ${product.description || 'Không có'}
Chat gần đây: ${commentsSummary}

Hãy đề xuất đúng 3 câu hỏi ngắn (dưới 15 từ mỗi câu) mà người xem Việt Nam có thể hỏi seller.
Câu hỏi phải tự nhiên, thực tế, liên quan đến sản phẩm.
Trả về JSON thuần túy, không markdown:
{"questions": ["câu hỏi 1", "câu hỏi 2", "câu hỏi 3"]}`;

  try {
    const response = await anthropic.messages.create({
      model: 'claude-haiku-4-5-20251001', // Nhanh + rẻ cho suggestions
      max_tokens: 200,
      messages: [{ role: 'user', content: prompt }],
    });
    
    const content = response.content[0].text.trim();
    const parsed = JSON.parse(content);
    
    if (!Array.isArray(parsed.questions) || parsed.questions.length !== 3) {
      throw new Error('Invalid response format');
    }
    
    return parsed.questions;
    
  } catch (err) {
    console.error('AI suggestion failed:', err);
    // Fallback: câu hỏi mặc định
    return [
      'Shop có giao nhanh không ạ?',
      'Sản phẩm còn hàng không shop?',
      'Có voucher giảm thêm không ạ?',
    ];
  }
}

// Rate limiting để không spam API
const suggestionCache = new Map(); // streamId+productId -> { suggestions, cachedAt }
const CACHE_DURATION = 30_000; // 30 giây

async function getCachedSuggestions({ streamId, productId, recentComments, product }) {
  const cacheKey = `${streamId}:${productId}`;
  const cached = suggestionCache.get(cacheKey);
  
  if (cached && Date.now() - cached.cachedAt < CACHE_DURATION) {
    return cached.suggestions;
  }
  
  const suggestions = await generateLiveSuggestions({ product, recentComments });
  
  suggestionCache.set(cacheKey, {
    suggestions,
    cachedAt: Date.now(),
  });
  
  return suggestions;
}

module.exports = { getCachedSuggestions };
```

**API endpoint:**

```javascript
// backend/routes/ai.js
router.post('/api/live/:streamId/ai-suggestions', authenticate, async (req, res) => {
  const { streamId } = req.params;
  const { currentProductId, recentComments = [] } = req.body;
  
  try {
    // Lấy thông tin sản phẩm
    const { rows } = await pool.query(
      'SELECT id, name, price, description FROM live_products WHERE id = $1',
      [currentProductId]
    );
    
    if (!rows.length) {
      return res.status(404).json({ error: 'Sản phẩm không tìm thấy' });
    }
    
    const suggestions = await getCachedSuggestions({
      streamId,
      productId: currentProductId,
      product: rows[0],
      recentComments,
    });
    
    return res.json({ suggestions });
    
  } catch (err) {
    console.error('AI suggestions error:', err);
    return res.status(500).json({
      suggestions: [
        'Sản phẩm giao trong bao lâu ạ?',
        'Còn hàng không shop ơi?',
        'Có combo không shop?',
      ]
    });
  }
});
```

---

### Flutter: UI gợi ý câu hỏi

```dart
// lib/features/live/widgets/live_suggestion_chips_widget.dart

class LiveSuggestionChipsWidget extends StatefulWidget {
  final String streamId;
  final String? currentProductId;
  final List<String> recentComments;
  final TextEditingController commentController;

  const LiveSuggestionChipsWidget({
    super.key,
    required this.streamId,
    this.currentProductId,
    required this.recentComments,
    required this.commentController,
  });

  @override
  State<LiveSuggestionChipsWidget> createState() =>
      _LiveSuggestionChipsWidgetState();
}

class _LiveSuggestionChipsWidgetState
    extends State<LiveSuggestionChipsWidget> {
  List<String> _suggestions = [];
  bool _isLoading = false;
  Timer? _refreshTimer;
  String? _lastProductId;

  @override
  void initState() {
    super.initState();
    _fetchSuggestions();
    // Refresh mỗi 30 giây
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _fetchSuggestions(),
    );
  }

  @override
  void didUpdateWidget(LiveSuggestionChipsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Fetch mới khi product thay đổi
    if (widget.currentProductId != _lastProductId) {
      _fetchSuggestions();
    }
  }

  Future<void> _fetchSuggestions() async {
    if (_isLoading || widget.currentProductId == null) return;

    setState(() => _isLoading = true);
    _lastProductId = widget.currentProductId;

    try {
      final response = await http.post(
        Uri.parse(
          '${AppUrls.baseUrl}/api/live/${widget.streamId}/ai-suggestions',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode({
          'currentProductId': widget.currentProductId,
          'recentComments': widget.recentComments.take(10).toList(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _suggestions = List<String>.from(data['suggestions'] ?? []);
          });
        }
      }
    } catch (e) {
      AppLogger.logError('LiveSuggestionChips', 'Fetch failed', e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_suggestions.isEmpty && !_isLoading) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: SizedBox(
                height: 28,
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _suggestions.map((suggestion) {
                return ActionChip(
                  label: Text(
                    suggestion,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                    ),
                  ),
                  backgroundColor: Colors.white.withOpacity(0.15),
                  side: BorderSide(
                    color: Colors.white.withOpacity(0.3),
                    width: 0.5,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onPressed: () {
                    // Auto-fill vào ô chat (user có thể sửa trước khi gửi)
                    widget.commentController.text = suggestion;
                    widget.commentController.selection =
                        TextSelection.fromPosition(
                      TextPosition(
                        offset: suggestion.length,
                      ),
                    );

                    AppLogger.logUserEvent(
                      action: 'ai_suggestion_tapped',
                      context: 'LiveSuggestionChips',
                      metadata: {'suggestion': suggestion},
                    );
                  },
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
```

---

### Flutter: Tích hợp vào LiveStreamScreen

```dart
// lib/features/live/screens/live_stream_screen.dart (phần comment input)

Widget _buildCommentInput(LiveProvider provider) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      // AI suggestion chips (bên trên ô nhập)
      LiveSuggestionChipsWidget(
        streamId: widget.streamId,
        currentProductId: provider.currentStream?.currentProductId,
        recentComments: provider.chatMessages
            .where((m) => !m.isSystemMessage)
            .map((m) => m.text)
            .take(10)
            .toList(),
        commentController: _commentController,
      ),

      // Ô nhập comment
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Nhập /mua [số] để đặt hàng...',
                  hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 13,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: (text) {
                  provider.sendComment(text);
                  _commentController.clear();
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send, color: AppColors.primaryGreen),
              onPressed: () {
                if (_commentController.text.trim().isNotEmpty) {
                  provider.sendComment(_commentController.text);
                  _commentController.clear();
                }
              },
            ),
          ],
        ),
      ),
    ],
  );
}
```

---

## Tổng kết & Best Practices

### Checklist cho developer Tropia

**Race Condition:**
- [ ] Dùng Redis DECR cho tồn kho sản phẩm live (atomic, nhanh)
- [ ] PostgreSQL là source of truth, sync sau mỗi đơn
- [ ] Pessimistic lock chỉ dùng khi cần đảm bảo tuyệt đối (stock thấp)
- [ ] Không bao giờ để stock âm – kiểm tra sau DECR

**High Concurrency:**
- [ ] API servers stateless – có thể scale ngang bất kỳ lúc nào
- [ ] Orders đi qua queue (Redis Streams) – không ghi thẳng vào DB
- [ ] Likes dùng write coalescing, batch mỗi 500ms
- [ ] Chat qua Redis PubSub + WebSocket

**N+1 Query:**
- [ ] Mọi list endpoint phải dùng JOIN hoặc JSON_AGG
- [ ] Thêm Redis cache 30s cho stream list
- [ ] Explain Analyze mọi query trước khi deploy
- [ ] Không dùng ORM lazy loading trong production

**Chat Commands:**
- [ ] Validate input nghiêm ngặt trước khi xử lý lệnh
- [ ] Bot responses luôn rõ ràng – thành công hay thất bại
- [ ] Log mọi command với AppLogger.logUserEvent()
- [ ] Không cho phép số lượng âm hoặc > 99

**Voucher:**
- [ ] Atomic claim với UPDATE...WHERE...RETURNING
- [ ] Stacking rules: tối đa 1 live + 1 platform voucher
- [ ] Flash voucher dùng Redis DECR + TTL
- [ ] Sync claimed_count về PostgreSQL sau mỗi claim

**AI Suggestions:**
- [ ] API key KHÔNG BAO GIỜ trong Flutter app
- [ ] Cache suggestions 30s để tránh spam Claude API
- [ ] Luôn có fallback khi AI call thất bại
- [ ] Dùng claude-haiku-4-5-20251001 (nhanh + rẻ) cho suggestions

---

*Tài liệu được tạo cho Tropia – Vietnamese Fresh Grocery & Live Shopping App*
*Phiên bản: 1.0 | Ngày cập nhật: 2026-05-08*
