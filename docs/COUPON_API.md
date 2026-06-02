# Coupon API — JSON Format

Mọi response bọc **envelope** chuẩn (`LIVESTREAM_API.md §1`). Phần dữ liệu nằm
trong `data`. Trên Flutter, interceptor đã bóc envelope nên `res.data` chính là
phần `data` dưới đây.

- `NewValidation` trong backend trả **HTTP 422** (không phải 400).
- Khi lỗi, `data` luôn là `null`.

---

## Object Coupon (dùng chung)

```json
{
  "id": "7c9e6b2a-3f4d-4a1b-8c2e-1d2f3a4b5c6d",
  "code": "LIVE250515",
  "discount_type": "percent",
  "discount_value": 10,
  "min_order_value": 100000,
  "max_discount": 50000,
  "max_uses": 100,
  "used_count": 7,
  "expires_at": "2026-06-10T14:00:00Z",
  "is_active": true,
  "session_id": "2b1c4d5e-6f70-4812-9a3b-4c5d6e7f8091",
  "created_by": "a0b1c2d3-e4f5-4607-8819-2a3b4c5d6e7f",
  "created_at": "2026-06-02T12:00:00Z"
}
```

| Field | Kiểu | Ghi chú |
|-------|------|---------|
| `discount_type` | string | `"percent"` \| `"fixed"` |
| `discount_value` | number | percent: % giảm; fixed: số tiền VND |
| `min_order_value` | int | đơn tối thiểu (VND), `0` = không yêu cầu |
| `max_discount` | int \| absent | chỉ percent: trần giảm (VND); vắng khi `null` |
| `max_uses` | int \| absent | tổng lượt dùng; vắng khi `null` (không giới hạn) |
| `session_id` | uuid \| absent | vắng/null = coupon toàn sàn |

---

## 1. GET `/api/coupons/available` — coupon toàn sàn (public)

> Handler bọc thêm 1 lớp `data` → mảng nằm ở **`data.data`**.

**200 — có coupon**
```json
{
  "Result": true,
  "StatusCode": "200",
  "StatusMess": "Success",
  "status": 200,
  "message": "Success",
  "data": {
    "data": [
      {
        "id": "7c9e6b2a-3f4d-4a1b-8c2e-1d2f3a4b5c6d",
        "code": "TROPIA50K",
        "discount_type": "fixed",
        "discount_value": 50000,
        "min_order_value": 300000,
        "used_count": 12,
        "expires_at": "2026-07-01T00:00:00Z",
        "is_active": true,
        "created_by": "a0b1c2d3-e4f5-4607-8819-2a3b4c5d6e7f",
        "created_at": "2026-06-01T08:00:00Z"
      }
    ]
  }
}
```

**200 — không có coupon**
```json
{
  "Result": true,
  "StatusCode": "200",
  "StatusMess": "Success",
  "status": 200,
  "message": "Success",
  "data": { "data": [] }
}
```

**500 — lỗi hệ thống**
```json
{
  "Result": false,
  "StatusCode": "500",
  "StatusMess": "list platform coupons",
  "status": 500,
  "message": "list platform coupons",
  "data": null
}
```

---

## 2. GET `/api/coupons/shop/:shopId` — coupon của shop (public)

**200**
```json
{
  "Result": true,
  "StatusCode": "200",
  "StatusMess": "Success",
  "status": 200,
  "message": "Success",
  "data": {
    "data": [
      {
        "id": "9d8c7b6a-5e4f-4302-8112-0a9b8c7d6e5f",
        "code": "SHOPSALE",
        "discount_type": "percent",
        "discount_value": 15,
        "min_order_value": 0,
        "max_discount": 30000,
        "max_uses": 200,
        "used_count": 41,
        "expires_at": "2026-06-20T17:00:00Z",
        "is_active": true,
        "session_id": "2b1c4d5e-6f70-4812-9a3b-4c5d6e7f8091",
        "created_by": "a0b1c2d3-e4f5-4607-8819-2a3b4c5d6e7f",
        "created_at": "2026-06-02T09:30:00Z"
      }
    ]
  }
}
```

**422 — shopId không hợp lệ**
```json
{
  "Result": false,
  "StatusCode": "422",
  "StatusMess": "invalid shop id",
  "status": 422,
  "message": "invalid shop id",
  "data": null
}
```

**500**
```json
{
  "Result": false,
  "StatusCode": "500",
  "StatusMess": "list shop coupons",
  "status": 500,
  "message": "list shop coupons",
  "data": null
}
```

---

## 3. POST `/api/coupons/validate` — kiểm tra mã (cần JWT)

> Endpoint này dùng **camelCase** cho cả request lẫn response.

**Request**
```json
{
  "code": "LIVE250515",
  "orderTotal": 250000
}
```

**200 — hợp lệ**
```json
{
  "Result": true,
  "StatusCode": "200",
  "StatusMess": "Success",
  "status": 200,
  "message": "Success",
  "data": {
    "couponId": "7c9e6b2a-3f4d-4a1b-8c2e-1d2f3a4b5c6d",
    "code": "LIVE250515",
    "discountType": "percent",
    "discountValue": 10,
    "discountAmount": 25000
  }
}
```

**401 — thiếu/sai token**
```json
{
  "Result": false,
  "StatusCode": "401",
  "StatusMess": "Chưa xác thực hoặc token không hợp lệ",
  "status": 401,
  "message": "Chưa xác thực hoặc token không hợp lệ",
  "data": null
}
```

**422 — sai body** (vd thiếu `orderTotal`)
```json
{
  "Result": false,
  "StatusCode": "422",
  "StatusMess": "Key: 'validateReq.OrderTotal' Error:Field validation for 'OrderTotal' failed on the 'required' tag",
  "status": 422,
  "message": "Key: 'validateReq.OrderTotal' Error:Field validation for 'OrderTotal' failed on the 'required' tag",
  "data": null
}
```

**422 — mã không tồn tại**
```json
{
  "Result": false,
  "StatusCode": "422",
  "StatusMess": "coupon not found",
  "status": 422,
  "message": "coupon not found",
  "data": null
}
```

**422 — mã ngừng hoạt động**
```json
{ "Result": false, "StatusCode": "422", "StatusMess": "coupon inactive", "status": 422, "message": "coupon inactive", "data": null }
```

**422 — mã hết hạn**
```json
{ "Result": false, "StatusCode": "422", "StatusMess": "coupon expired", "status": 422, "message": "coupon expired", "data": null }
```

**422 — hết lượt dùng**
```json
{ "Result": false, "StatusCode": "422", "StatusMess": "coupon usage limit reached", "status": 422, "message": "coupon usage limit reached", "data": null }
```

**422 — chưa đạt đơn tối thiểu**
```json
{ "Result": false, "StatusCode": "422", "StatusMess": "order total below minimum", "status": 422, "message": "order total below minimum", "data": null }
```

---

## 4. POST `/api/live/streams/:id/coupons` — host tạo coupon (seller, chủ session)

**Request** (snake_case)
```json
{
  "code": "LIVE250515",
  "discount_type": "percent",
  "discount_value": 10,
  "min_order_value": 100000,
  "max_uses": 100,
  "expires_at": "2026-06-10T14:00:00Z"
}
```

**201 — tạo thành công**
```json
{
  "Result": true,
  "StatusCode": "201",
  "StatusMess": "Success",
  "status": 201,
  "message": "Success",
  "data": {
    "coupon": {
      "id": "7c9e6b2a-3f4d-4a1b-8c2e-1d2f3a4b5c6d",
      "code": "LIVE250515",
      "discount_type": "percent",
      "discount_value": 10,
      "min_order_value": 100000,
      "max_uses": 100,
      "used_count": 0,
      "expires_at": "2026-06-10T14:00:00Z",
      "is_active": true,
      "session_id": "2b1c4d5e-6f70-4812-9a3b-4c5d6e7f8091",
      "created_by": "a0b1c2d3-e4f5-4607-8819-2a3b4c5d6e7f",
      "created_at": "2026-06-02T12:00:00Z"
    }
  }
}
```

**401 — chưa đăng nhập**
```json
{ "Result": false, "StatusCode": "401", "StatusMess": "Chưa xác thực hoặc token không hợp lệ", "status": 401, "message": "Chưa xác thực hoặc token không hợp lệ", "data": null }
```

**403 — không phải seller/admin**
```json
{ "Result": false, "StatusCode": "403", "StatusMess": "Không có quyền truy cập", "status": 403, "message": "Không có quyền truy cập", "data": null }
```

**422 — session id sai**
```json
{ "Result": false, "StatusCode": "422", "StatusMess": "invalid id", "status": 422, "message": "invalid id", "data": null }
```

**404 — session không tồn tại**
```json
{ "Result": false, "StatusCode": "404", "StatusMess": "session not found", "status": 404, "message": "session not found", "data": null }
```

**403 — không phải chủ session**
```json
{ "Result": false, "StatusCode": "403", "StatusMess": "not session owner", "status": 403, "message": "not session owner", "data": null }
```

**422 — sai body** (thiếu field / `discount_type` không phải percent|fixed / `max_uses < 1`)
```json
{ "Result": false, "StatusCode": "422", "StatusMess": "Key: 'createCouponReq.MaxUses' Error:Field validation for 'MaxUses' failed on the 'required' tag", "status": 422, "message": "Key: 'createCouponReq.MaxUses' Error:Field validation for 'MaxUses' failed on the 'required' tag", "data": null }
```

**422 — sai định dạng ngày**
```json
{ "Result": false, "StatusCode": "422", "StatusMess": "expires_at must be RFC3339", "status": 422, "message": "expires_at must be RFC3339", "data": null }
```

**500 — lỗi DB (vd trùng code)**
```json
{ "Result": false, "StatusCode": "500", "StatusMess": "create coupon", "status": 500, "message": "create coupon", "data": null }
```

---

## 5. GET `/api/live/streams/:id/coupons` — list coupon của session (public)

**200**
```json
{
  "Result": true,
  "StatusCode": "200",
  "StatusMess": "Success",
  "status": 200,
  "message": "Success",
  "data": {
    "coupons": [
      {
        "id": "7c9e6b2a-3f4d-4a1b-8c2e-1d2f3a4b5c6d",
        "code": "LIVE250515",
        "discount_type": "percent",
        "discount_value": 10,
        "min_order_value": 100000,
        "max_uses": 100,
        "used_count": 0,
        "expires_at": "2026-06-10T14:00:00Z",
        "is_active": true,
        "session_id": "2b1c4d5e-6f70-4812-9a3b-4c5d6e7f8091",
        "created_by": "a0b1c2d3-e4f5-4607-8819-2a3b4c5d6e7f",
        "created_at": "2026-06-02T12:00:00Z"
      }
    ]
  }
}
```

**200 — không có coupon**
```json
{ "Result": true, "StatusCode": "200", "StatusMess": "Success", "status": 200, "message": "Success", "data": { "coupons": [] } }
```

**422 — session id sai**
```json
{ "Result": false, "StatusCode": "422", "StatusMess": "invalid id", "status": 422, "message": "invalid id", "data": null }
```

**500**
```json
{ "Result": false, "StatusCode": "500", "StatusMess": "list coupons", "status": 500, "message": "list coupons", "data": null }
```

---

## 6. POST `/api/live/streams/:id/coupons/:couponId/announce` — phát lại coupon (seller)

Không có body.

**204 — thành công** (envelope hoá HTTP 204)
```json
{ "Result": true, "StatusCode": "204", "StatusMess": "Success", "status": 204, "message": "Success", "data": null }
```

**404 — coupon không thuộc session**
```json
{ "Result": false, "StatusCode": "404", "StatusMess": "coupon not found in session", "status": 404, "message": "coupon not found in session", "data": null }
```

**403 — không phải chủ session**
```json
{ "Result": false, "StatusCode": "403", "StatusMess": "not session owner", "status": 403, "message": "not session owner", "data": null }
```

**422 — id sai**
```json
{ "Result": false, "StatusCode": "422", "StatusMess": "invalid couponId", "status": 422, "message": "invalid couponId", "data": null }
```

**404 — session không tồn tại**
```json
{ "Result": false, "StatusCode": "404", "StatusMess": "session not found", "status": 404, "message": "session not found", "data": null }
```
