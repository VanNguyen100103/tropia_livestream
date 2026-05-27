package commerce

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tropia/backend/internal/auth"
	"github.com/tropia/backend/internal/cache"
	"github.com/tropia/backend/internal/httpx"
)

type Order struct {
	ID             uuid.UUID  `json:"id"`
	SessionID      *uuid.UUID `json:"session_id,omitempty"`
	ProductID      *uuid.UUID `json:"product_id,omitempty"`
	ProductName    *string    `json:"product_name,omitempty"`
	BuyerID        uuid.UUID  `json:"buyer_id"`
	BuyerName      *string    `json:"buyer_name,omitempty"`
	BuyerAvatar    *string    `json:"buyer_avatar,omitempty"`
	Quantity       int        `json:"quantity"`
	UnitPrice      int        `json:"unit_price"`
	TotalPrice     int        `json:"total_price"`
	DiscountAmount int        `json:"discount_amount"`
	CouponID       *uuid.UUID `json:"coupon_id,omitempty"`
	Status         string     `json:"status"`
	PaymentStatus  string     `json:"payment_status"`
	PaymentMethod  string     `json:"payment_method"`
	TransactionID  *string    `json:"transaction_id,omitempty"`
	PaidAt         *time.Time `json:"paid_at,omitempty"`
	TrackingCode   *string    `json:"tracking_code,omitempty"`
	ShippedAt      *time.Time `json:"shipped_at,omitempty"`
	DeliveredAt    *time.Time `json:"delivered_at,omitempty"`
	// Shipping address snapshot taken at checkout. Nullable to keep
	// older COD orders + the live-stream "buy now" path (no address
	// prompt) working unchanged.
	ShippingName    *string   `json:"shipping_name,omitempty"`
	ShippingPhone   *string   `json:"shipping_phone,omitempty"`
	ShippingAddress *string   `json:"shipping_address,omitempty"`
	CreatedAt       time.Time `json:"created_at"`
}

type OrderRepository struct{ pool *pgxpool.Pool }

func NewOrderRepository(pool *pgxpool.Pool) *OrderRepository {
	return &OrderRepository{pool: pool}
}

func (r *OrderRepository) Insert(ctx context.Context, o Order) (*Order, error) {
	const q = `
		INSERT INTO live_orders (session_id, product_id, product_name, buyer_id, buyer_name, buyer_avatar,
		                          quantity, unit_price, total_price, discount_amount, coupon_id,
		                          status, payment_status, payment_method,
		                          shipping_name, shipping_phone, shipping_address)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 'confirmed', 'pending', $12, $13, $14, $15)
		RETURNING id, session_id, product_id, product_name, buyer_id, buyer_name, buyer_avatar,
		          quantity, unit_price, total_price, discount_amount, coupon_id,
		          status, payment_status, payment_method, transaction_id, paid_at,
		          tracking_code, shipped_at, delivered_at,
		          shipping_name, shipping_phone, shipping_address, created_at
	`
	row := r.pool.QueryRow(ctx, q,
		o.SessionID, o.ProductID, o.ProductName, o.BuyerID, o.BuyerName, o.BuyerAvatar,
		o.Quantity, o.UnitPrice, o.TotalPrice, o.DiscountAmount, o.CouponID,
		o.PaymentMethod,
		o.ShippingName, o.ShippingPhone, o.ShippingAddress,
	)
	var out Order
	if err := scanOrder(row, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

func (r *OrderRepository) GetByID(ctx context.Context, id uuid.UUID) (*Order, error) {
	const q = `
		SELECT id, session_id, product_id, product_name, buyer_id, buyer_name, buyer_avatar,
		       quantity, unit_price, total_price, discount_amount, coupon_id,
		       status, payment_status, payment_method, transaction_id, paid_at,
		       tracking_code, shipped_at, delivered_at,
		       shipping_name, shipping_phone, shipping_address, created_at
		FROM live_orders WHERE id = $1
	`
	var o Order
	if err := scanOrder(r.pool.QueryRow(ctx, q, id), &o); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("order not found")
		}
		return nil, err
	}
	return &o, nil
}

func (r *OrderRepository) ListByBuyer(ctx context.Context, buyerID uuid.UUID, limit, offset int) ([]Order, int, error) {
	var total int
	if err := r.pool.QueryRow(ctx, `SELECT COUNT(*) FROM live_orders WHERE buyer_id = $1`, buyerID).Scan(&total); err != nil {
		return nil, 0, err
	}
	const q = `
		SELECT id, session_id, product_id, product_name, buyer_id, buyer_name, buyer_avatar,
		       quantity, unit_price, total_price, discount_amount, coupon_id,
		       status, payment_status, payment_method, transaction_id, paid_at,
		       tracking_code, shipped_at, delivered_at,
		       shipping_name, shipping_phone, shipping_address, created_at
		FROM live_orders WHERE buyer_id = $1
		ORDER BY created_at DESC
		LIMIT $2 OFFSET $3
	`
	rows, err := r.pool.Query(ctx, q, buyerID, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := make([]Order, 0)
	for rows.Next() {
		var o Order
		if err := scanOrder(rows, &o); err != nil {
			return nil, 0, err
		}
		out = append(out, o)
	}
	return out, total, rows.Err()
}

// PaymentConfirmation is what MarkPaid returns so the caller can publish a
// rich `payment.success` event (buyer email, line items, totals) without
// needing a second round trip to the DB.
type PaymentConfirmation struct {
	// Applied is false when the order was already in `paid` state, meaning
	// this call was a no-op (likely a duplicate IPN/callback). Caller
	// should skip publishing the success event in that case.
	Applied        bool
	BuyerID        uuid.UUID
	TotalPrice     int
	DiscountAmount int
	// Shipping snapshot at order creation — included so the receipt
	// email can render the delivery address without a second DB read.
	ShippingName    *string
	ShippingPhone   *string
	ShippingAddress *string
	// Items is the cart_items snapshot taken just before they were deleted
	// in the same transaction. Used to render the itemized receipt email.
	Items []CartItem
}

func (r *OrderRepository) MarkPaid(ctx context.Context, orderID uuid.UUID, method, txID string) (*PaymentConfirmation, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	var (
		buyerID         uuid.UUID
		orderCreatedAt  time.Time
		totalPrice      int
		discountAmount  int
		shippingName    *string
		shippingPhone   *string
		shippingAddress *string
	)
	err = tx.QueryRow(ctx,
		`UPDATE live_orders
		 SET payment_status = 'paid', payment_method = $2, transaction_id = $3, paid_at = NOW()
		 WHERE id = $1 AND payment_status != 'paid'
		 RETURNING buyer_id, created_at, total_price, discount_amount,
		           shipping_name, shipping_phone, shipping_address`,
		orderID, method, txID,
	).Scan(&buyerID, &orderCreatedAt, &totalPrice, &discountAmount,
		&shippingName, &shippingPhone, &shippingAddress)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			// Already paid (or order missing). Nothing to clean up — commit
			// the no-op tx so the caller still sees a non-error result.
			return &PaymentConfirmation{Applied: false}, tx.Commit(ctx)
		}
		return nil, err
	}

	// Snapshot the cart_items that were in the cart when the order was
	// created, BEFORE deleting them. The `added_at <= order.created_at`
	// guard prevents wiping items the buyer added during the payment
	// window (e.g. switched back to the app and added something else
	// while waiting for IPN).
	rows, err := tx.Query(ctx,
		`SELECT id, user_id, variant_id, product_id, product_name, shop_id, shop_name, image_url,
		        attributes, unit_price, original_price, quantity, is_selected, added_at
		 FROM cart_items
		 WHERE user_id = $1 AND is_selected = TRUE AND added_at <= $2`,
		buyerID, orderCreatedAt,
	)
	if err != nil {
		return nil, err
	}
	var items []CartItem
	for rows.Next() {
		var it CartItem
		if err := scanCart(rows, &it); err != nil {
			rows.Close()
			return nil, err
		}
		items = append(items, it)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}

	if _, err := tx.Exec(ctx,
		`DELETE FROM cart_items
		 WHERE user_id = $1 AND is_selected = TRUE AND added_at <= $2`,
		buyerID, orderCreatedAt,
	); err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return &PaymentConfirmation{
		Applied: true, BuyerID: buyerID,
		TotalPrice: totalPrice, DiscountAmount: discountAmount,
		ShippingName: shippingName, ShippingPhone: shippingPhone,
		ShippingAddress: shippingAddress,
		Items:           items,
	}, nil
}

func scanOrder(row interface{ Scan(...any) error }, o *Order) error {
	return row.Scan(
		&o.ID, &o.SessionID, &o.ProductID, &o.ProductName, &o.BuyerID, &o.BuyerName, &o.BuyerAvatar,
		&o.Quantity, &o.UnitPrice, &o.TotalPrice, &o.DiscountAmount, &o.CouponID,
		&o.Status, &o.PaymentStatus, &o.PaymentMethod, &o.TransactionID, &o.PaidAt,
		&o.TrackingCode, &o.ShippedAt, &o.DeliveredAt,
		&o.ShippingName, &o.ShippingPhone, &o.ShippingAddress, &o.CreatedAt,
	)
}

// ============================================================================
// Order Service - place live order + checkout cart
// ============================================================================

// EventPublisher mirrors events.EventBus for testability.
type EventPublisher interface {
	Publish(ctx context.Context, eventType string, payload any) error
}

type noopPublisher struct{}

func (noopPublisher) Publish(context.Context, string, any) error { return nil }

// BuyerLookup is the minimal slice of the auth repository this package
// needs to fetch a buyer's email/name for transactional emails. Kept as an
// interface so commerce doesn't import auth (avoids an import cycle and
// keeps the seam clean for tests).
type BuyerLookup interface {
	LookupBuyer(ctx context.Context, id uuid.UUID) (BuyerInfo, error)
}

type BuyerInfo struct {
	Email string
	Name  string
}

type noopBuyerLookup struct{}

func (noopBuyerLookup) LookupBuyer(context.Context, uuid.UUID) (BuyerInfo, error) {
	return BuyerInfo{}, nil
}

type OrderService struct {
	pool        *pgxpool.Pool
	orderRepo   *OrderRepository
	cartRepo    *CartRepository
	couponRepo  *CouponRepository
	cache       *cache.Cache
	events      EventPublisher
	buyerLookup BuyerLookup
}

func NewOrderService(pool *pgxpool.Pool, oRepo *OrderRepository, cRepo *CartRepository, cpnRepo *CouponRepository, cc *cache.Cache) *OrderService {
	return &OrderService{
		pool: pool, orderRepo: oRepo, cartRepo: cRepo, couponRepo: cpnRepo, cache: cc,
		events: noopPublisher{}, buyerLookup: noopBuyerLookup{},
	}
}

func (s *OrderService) WithEvents(p EventPublisher) *OrderService {
	if p != nil {
		s.events = p
	}
	return s
}

func (s *OrderService) WithBuyerLookup(b BuyerLookup) *OrderService {
	if b != nil {
		s.buyerLookup = b
	}
	return s
}

// ConfirmPayment is the gateway-callback entry point: marks the order
// paid, snapshots the cart items it just cleared, looks up the buyer's
// email, and publishes a `payment.success` event with everything the
// worker needs to send a rich receipt. Returns nil (no error) on
// duplicate callbacks — the second IPN is a no-op, not an error.
func (s *OrderService) ConfirmPayment(ctx context.Context, orderID uuid.UUID, method, txID string) error {
	conf, err := s.orderRepo.MarkPaid(ctx, orderID, method, txID)
	if err != nil {
		return err
	}
	if !conf.Applied {
		// Already paid — duplicate IPN/callback. Don't re-publish the
		// success event (would double-send the receipt email).
		return nil
	}

	buyer, _ := s.buyerLookup.LookupBuyer(ctx, conf.BuyerID)

	items := make([]map[string]any, 0, len(conf.Items))
	for _, it := range conf.Items {
		items = append(items, map[string]any{
			"name":     it.ProductName,
			"quantity": it.Quantity,
			"price":    it.UnitPrice,
		})
	}

	_ = s.events.Publish(ctx, "payment.success", map[string]any{
		"order_id":         orderID.String(),
		"buyer_id":         conf.BuyerID.String(),
		"email":            buyer.Email,
		"name":             buyer.Name,
		"method":           method,
		"trans_id":         txID,
		"amount":           conf.TotalPrice,
		"discount_amount":  conf.DiscountAmount,
		"items":            items,
		"shipping_name":    derefStr(conf.ShippingName),
		"shipping_phone":   derefStr(conf.ShippingPhone),
		"shipping_address": derefStr(conf.ShippingAddress),
	})
	return nil
}

func derefStr(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}

type PlaceOrderInput struct {
	LiveProductID uuid.UUID
	Quantity      int
	CouponCode    string
	BuyerID       uuid.UUID
	BuyerName     string
}

func (s *OrderService) PlaceLiveOrder(ctx context.Context, in PlaceOrderInput) (*Order, error) {
	lockKey := fmt.Sprintf("product:%s:stock", in.LiveProductID.String())
	lock, err := s.cache.AcquireLock(ctx, lockKey, cache.LockOptions{TTL: 5 * time.Second, Retries: 5})
	if err != nil {
		return nil, httpx.NewConflict("stock contention, please retry")
	}
	defer lock.Release(ctx)

	// Fetch + check stock
	var (
		sessionID uuid.UUID
		stockLeft int
		salePrice float64
		productName string
	)
	err = s.pool.QueryRow(ctx,
		`SELECT session_id, stock_left, sale_price, product_name FROM live_session_products WHERE id = $1`,
		in.LiveProductID).Scan(&sessionID, &stockLeft, &salePrice, &productName)
	if err != nil {
		return nil, httpx.NewNotFound("live product not found")
	}
	if stockLeft < in.Quantity {
		return nil, httpx.NewConflict("insufficient stock")
	}

	subtotal := int(salePrice) * in.Quantity
	totalPrice := subtotal
	discount := 0
	var couponID *uuid.UUID

	if in.CouponCode != "" {
		apply, err := ApplyCoupon(ctx, s.couponRepo, in.CouponCode, in.BuyerID, subtotal)
		if err != nil {
			// Surface the validation error (expired / already used / below
			// min order / etc.) so the FE can show "voucher không áp dụng
			// được" instead of silently charging the un-discounted total.
			return nil, err
		}
		discount = apply.DiscountAmount
		totalPrice = subtotal - discount
		couponID = &apply.Coupon.ID
	}

	order, err := s.orderRepo.Insert(ctx, Order{
		SessionID: &sessionID, ProductID: &in.LiveProductID,
		BuyerID: in.BuyerID, BuyerName: &in.BuyerName,
		Quantity: in.Quantity, UnitPrice: int(salePrice),
		TotalPrice: totalPrice, DiscountAmount: discount, CouponID: couponID,
		PaymentMethod: "cod",
	})
	if err != nil {
		return nil, httpx.NewInternal("insert order", err)
	}

	// Decrement stock
	_, _ = s.pool.Exec(ctx,
		`UPDATE live_session_products SET stock_left = stock_left - $2, sold_count = sold_count + $2 WHERE id = $1`,
		in.LiveProductID, in.Quantity)

	if couponID != nil {
		_ = s.couponRepo.RecordUsage(ctx, *couponID, in.BuyerID, order.ID)
	}

	// Worker → sends order confirmation email
	_ = s.events.Publish(ctx, "order.created", map[string]any{
		"order_id":        order.ID.String(),
		"buyer_id":        order.BuyerID.String(),
		"buyer_name":      in.BuyerName,
		"product_name":    productName,
		"quantity":        in.Quantity,
		"total_price":     totalPrice,
		"discount_amount": discount,
	})

	return order, nil
}

type CheckoutCartInput struct {
	BuyerID   uuid.UUID
	BuyerName string
	// CouponCodes is the union of platform-wide + per-shop vouchers the
	// buyer applied on the FE cart. Each code is validated independently
	// (active / not-expired / not-already-used / meets-min) and their
	// discounts are summed. Caller may dedupe; we dedupe defensively here.
	CouponCodes   []string
	PaymentMethod string
	// Delivery address captured at checkout. All three are optional —
	// the FE pickup-at-store path leaves them blank, and existing
	// callers can omit them entirely.
	ShippingName    string
	ShippingPhone   string
	ShippingAddress string
}

func (s *OrderService) CheckoutCart(ctx context.Context, in CheckoutCartInput) (*Order, error) {
	items, err := s.cartRepo.ListSelected(ctx, in.BuyerID)
	if err != nil {
		return nil, httpx.NewInternal("list selected", err)
	}
	if len(items) == 0 {
		return nil, httpx.NewValidation("no items selected", nil)
	}
	subtotal := 0
	totalQty := 0
	for _, it := range items {
		subtotal += it.UnitPrice * it.Quantity
		totalQty += it.Quantity
	}
	discount := 0
	var appliedCouponIDs []uuid.UUID
	seen := make(map[string]struct{}, len(in.CouponCodes))
	for _, code := range in.CouponCodes {
		if code == "" {
			continue
		}
		if _, dup := seen[code]; dup {
			continue
		}
		seen[code] = struct{}{}
		apply, err := ApplyCoupon(ctx, s.couponRepo, code, in.BuyerID, subtotal)
		if err != nil {
			// Surface the validation error (expired / already used / below
			// min / not found) so the FE can prompt the buyer to drop the
			// offending voucher instead of silently charging the un-
			// discounted amount through MoMo / ZaloPay / VNPay.
			return nil, err
		}
		discount += apply.DiscountAmount
		appliedCouponIDs = append(appliedCouponIDs, apply.Coupon.ID)
	}
	if discount > subtotal {
		discount = subtotal
	}
	var couponID *uuid.UUID
	if len(appliedCouponIDs) > 0 {
		// live_orders.coupon_id is a single-column legacy field. With multi
		// coupon support the full mapping lives in coupon_usages; we just
		// store the first applied id here so the column isn't always NULL.
		couponID = &appliedCouponIDs[0]
	}
	grandTotal := subtotal - discount
	if grandTotal < 0 {
		grandTotal = 0
	}

	productName := items[0].ProductName
	if len(items) > 1 {
		productName = fmt.Sprintf("%s và %d sản phẩm khác", items[0].ProductName, len(items)-1)
	}

	method := in.PaymentMethod
	if method == "" {
		method = "cod"
	}

	order, err := s.orderRepo.Insert(ctx, Order{
		BuyerID:         in.BuyerID,
		BuyerName:       &in.BuyerName,
		ProductName:     &productName,
		Quantity:        totalQty,
		UnitPrice:       subtotal, // overloaded as subtotal (Node.js compatibility)
		TotalPrice:      grandTotal,
		DiscountAmount:  discount,
		CouponID:        couponID,
		PaymentMethod:   method,
		ShippingName:    optionalStr(in.ShippingName),
		ShippingPhone:   optionalStr(in.ShippingPhone),
		ShippingAddress: optionalStr(in.ShippingAddress),
	})
	if err != nil {
		return nil, httpx.NewInternal("insert order", err)
	}

	for _, cid := range appliedCouponIDs {
		_ = s.couponRepo.RecordUsage(ctx, cid, in.BuyerID, order.ID)
	}

	// Cart cleanup policy:
	//   - COD: order is committed at creation (buyer pays at delivery), so
	//     remove the checked-out items now.
	//   - Online (momo/vnpay/zalopay): order is only committed once the
	//     gateway IPN/callback flips payment_status to 'paid'. Leaving the
	//     items in the cart means a failed/cancelled payment doesn't wipe
	//     the buyer's selection. MarkPaid is responsible for the eventual
	//     cleanup.
	if method == "cod" {
		_ = s.cartRepo.RemoveSelected(ctx, in.BuyerID)
	}

	// Build payload for the order-created email worker. For COD this also
	// serves as the "receipt" (since the order is committed immediately);
	// for online methods the actual receipt is sent later from the
	// payment.success event after the gateway confirms.
	buyer, _ := s.buyerLookup.LookupBuyer(ctx, in.BuyerID)
	itemsPayload := make([]map[string]any, 0, len(items))
	for _, it := range items {
		itemsPayload = append(itemsPayload, map[string]any{
			"name":     it.ProductName,
			"quantity": it.Quantity,
			"price":    it.UnitPrice,
		})
	}

	_ = s.events.Publish(ctx, "order.created", map[string]any{
		"order_id":         order.ID.String(),
		"buyer_id":         order.BuyerID.String(),
		"buyer_name":       in.BuyerName,
		"email":            buyer.Email,
		"name":             buyer.Name,
		"product_name":     productName,
		"quantity":         totalQty,
		"total_price":      grandTotal,
		"discount_amount":  discount,
		"payment_method":   method,
		"items":            itemsPayload,
		"session_title":    "Tropia Store",
		"shipping_name":    in.ShippingName,
		"shipping_phone":   in.ShippingPhone,
		"shipping_address": in.ShippingAddress,
	})

	return order, nil
}

// optionalStr returns nil for empty strings so we store NULL instead of
// '' in `shipping_*` columns — keeps the email-render logic ("address
// present?" = pointer non-nil) honest.
func optionalStr(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

// ============================================================================
// Order Handler
// ============================================================================

type OrderHandler struct {
	svc  *OrderService
	repo *OrderRepository
}

func NewOrderHandler(svc *OrderService, repo *OrderRepository) *OrderHandler {
	return &OrderHandler{svc: svc, repo: repo}
}

func (h *OrderHandler) Register(r *gin.RouterGroup, authMw gin.HandlerFunc, cc *cache.Cache) {
	// Per-user rate limit on order mutation. A stolen access token could
	// otherwise spam place-order / checkout 1000×/sec — server-side
	// inventory decrements happen synchronously, so an attack drains
	// stock quickly. 20/min per user is generous for real buyers but
	// kills the abuse path.
	orderLimit := httpx.RateLimit(cc, httpx.RateLimitConfig{
		Limit: 20, WindowMs: 60 * 1000, FailClosed: false,
	})

	g := r.Group("/", authMw)
	g.POST("", orderLimit, h.placeOrder)
	g.POST("/checkout", orderLimit, h.checkout)
	g.GET("/my/list", h.myList)
	g.GET("/:id", h.getOne)
}

type placeOrderReq struct {
	LiveProductID uuid.UUID `json:"live_product_id" binding:"required"`
	Quantity      int       `json:"quantity" binding:"required,min=1"`
	CouponCode    string    `json:"coupon_code"`
}

func (h *OrderHandler) placeOrder(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	var req placeOrderReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	order, err := h.svc.PlaceLiveOrder(c.Request.Context(), PlaceOrderInput{
		LiveProductID: req.LiveProductID, Quantity: req.Quantity,
		CouponCode: req.CouponCode, BuyerID: uid,
	})
	if err != nil {
		c.Error(err)
		return
	}
	c.JSON(http.StatusCreated, gin.H{"order": order})
}

type checkoutReq struct {
	// CouponCode is the legacy single-coupon field. Kept for callers that
	// only apply a platform-wide voucher.
	CouponCode string `json:"coupon_code"`
	// CouponCodes is the new multi-coupon field — FE sends the union of
	// the platform voucher plus any per-shop vouchers the buyer applied.
	CouponCodes   []string `json:"coupon_codes"`
	PaymentMethod string   `json:"payment_method"`
	// Optional shipping snapshot — FE delivery tab sends these; pickup
	// tab omits them entirely.
	ShippingName    string `json:"shipping_name"`
	ShippingPhone   string `json:"shipping_phone"`
	ShippingAddress string `json:"shipping_address"`
}

func (h *OrderHandler) checkout(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	var req checkoutReq
	_ = c.ShouldBindJSON(&req)
	codes := req.CouponCodes
	if req.CouponCode != "" {
		codes = append(codes, req.CouponCode)
	}
	order, err := h.svc.CheckoutCart(c.Request.Context(), CheckoutCartInput{
		BuyerID:         uid,
		CouponCodes:     codes,
		PaymentMethod:   req.PaymentMethod,
		ShippingName:    strings.TrimSpace(req.ShippingName),
		ShippingPhone:   strings.TrimSpace(req.ShippingPhone),
		ShippingAddress: strings.TrimSpace(req.ShippingAddress),
	})
	if err != nil {
		c.Error(err)
		return
	}
	c.JSON(http.StatusCreated, gin.H{"order": order})
}

func (h *OrderHandler) myList(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	orders, total, err := h.repo.ListByBuyer(c.Request.Context(), uid, 20, 0)
	if err != nil {
		c.Error(httpx.NewInternal("list orders", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"orders": orders, "total": total})
}

func (h *OrderHandler) getOne(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	order, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.Error(httpx.NewNotFound("order not found"))
		return
	}
	// BOLA: only buyer or admin
	if order.BuyerID != uid && claims.Role != auth.RoleAdmin {
		c.Error(httpx.NewNotFound("order not found")) // mirror Node.js: 404 not 403
		return
	}
	c.JSON(http.StatusOK, gin.H{"order": order})
}
