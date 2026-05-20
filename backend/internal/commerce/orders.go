package commerce

import (
	"context"
	"errors"
	"fmt"
	"net/http"
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
	CreatedAt      time.Time  `json:"created_at"`
}

type OrderRepository struct{ pool *pgxpool.Pool }

func NewOrderRepository(pool *pgxpool.Pool) *OrderRepository {
	return &OrderRepository{pool: pool}
}

func (r *OrderRepository) Insert(ctx context.Context, o Order) (*Order, error) {
	const q = `
		INSERT INTO live_orders (session_id, product_id, product_name, buyer_id, buyer_name, buyer_avatar,
		                          quantity, unit_price, total_price, discount_amount, coupon_id,
		                          status, payment_status, payment_method)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 'confirmed', 'pending', $12)
		RETURNING id, session_id, product_id, product_name, buyer_id, buyer_name, buyer_avatar,
		          quantity, unit_price, total_price, discount_amount, coupon_id,
		          status, payment_status, payment_method, transaction_id, paid_at,
		          tracking_code, shipped_at, delivered_at, created_at
	`
	row := r.pool.QueryRow(ctx, q,
		o.SessionID, o.ProductID, o.ProductName, o.BuyerID, o.BuyerName, o.BuyerAvatar,
		o.Quantity, o.UnitPrice, o.TotalPrice, o.DiscountAmount, o.CouponID,
		o.PaymentMethod,
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
		       tracking_code, shipped_at, delivered_at, created_at
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
		       tracking_code, shipped_at, delivered_at, created_at
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

func (r *OrderRepository) MarkPaid(ctx context.Context, orderID uuid.UUID, method, txID string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE live_orders SET payment_status = 'paid', payment_method = $2, transaction_id = $3, paid_at = NOW()
		 WHERE id = $1 AND payment_status != 'paid'`,
		orderID, method, txID)
	return err
}

func scanOrder(row interface{ Scan(...any) error }, o *Order) error {
	return row.Scan(
		&o.ID, &o.SessionID, &o.ProductID, &o.ProductName, &o.BuyerID, &o.BuyerName, &o.BuyerAvatar,
		&o.Quantity, &o.UnitPrice, &o.TotalPrice, &o.DiscountAmount, &o.CouponID,
		&o.Status, &o.PaymentStatus, &o.PaymentMethod, &o.TransactionID, &o.PaidAt,
		&o.TrackingCode, &o.ShippedAt, &o.DeliveredAt, &o.CreatedAt,
	)
}

// ============================================================================
// Order Service - place live order + checkout cart
// ============================================================================

type OrderService struct {
	pool     *pgxpool.Pool
	orderRepo *OrderRepository
	cartRepo *CartRepository
	couponRepo *CouponRepository
	cache    *cache.Cache
}

func NewOrderService(pool *pgxpool.Pool, oRepo *OrderRepository, cRepo *CartRepository, cpnRepo *CouponRepository, cc *cache.Cache) *OrderService {
	return &OrderService{pool: pool, orderRepo: oRepo, cartRepo: cRepo, couponRepo: cpnRepo, cache: cc}
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
		if err == nil {
			discount = apply.DiscountAmount
			totalPrice = subtotal - discount
			couponID = &apply.Coupon.ID
		}
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

	return order, nil
}

type CheckoutCartInput struct {
	BuyerID      uuid.UUID
	BuyerName    string
	CouponCode   string
	PaymentMethod string
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
	var couponID *uuid.UUID
	if in.CouponCode != "" {
		apply, err := ApplyCoupon(ctx, s.couponRepo, in.CouponCode, in.BuyerID, subtotal)
		if err == nil {
			discount = apply.DiscountAmount
			couponID = &apply.Coupon.ID
		}
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
		BuyerID:    in.BuyerID,
		BuyerName:  &in.BuyerName,
		ProductName: &productName,
		Quantity:   totalQty,
		UnitPrice:  subtotal, // overloaded as subtotal (Node.js compatibility)
		TotalPrice: grandTotal,
		DiscountAmount: discount,
		CouponID:   couponID,
		PaymentMethod: method,
	})
	if err != nil {
		return nil, httpx.NewInternal("insert order", err)
	}

	if couponID != nil {
		_ = s.couponRepo.RecordUsage(ctx, *couponID, in.BuyerID, order.ID)
	}

	// Remove checked-out items from cart
	_ = s.cartRepo.RemoveSelected(ctx, in.BuyerID)

	return order, nil
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

func (h *OrderHandler) Register(r *gin.RouterGroup, authMw gin.HandlerFunc) {
	g := r.Group("/", authMw)
	g.POST("", h.placeOrder)
	g.POST("/checkout", h.checkout)
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
	CouponCode    string `json:"coupon_code"`
	PaymentMethod string `json:"payment_method"`
}

func (h *OrderHandler) checkout(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	var req checkoutReq
	_ = c.ShouldBindJSON(&req)
	order, err := h.svc.CheckoutCart(c.Request.Context(), CheckoutCartInput{
		BuyerID: uid, CouponCode: req.CouponCode, PaymentMethod: req.PaymentMethod,
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
