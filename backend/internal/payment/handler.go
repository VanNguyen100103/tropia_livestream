package payment

import (
	"fmt"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/tropia/backend/internal/auth"
	"github.com/tropia/backend/internal/commerce"
	"github.com/tropia/backend/internal/httpx"
)

type Handler struct {
	orderRepo *commerce.OrderRepository
	momo      *MoMo
	vnpay     *VNPay
	zalopay   *ZaloPay
	clientURL string
}

func NewHandler(orderRepo *commerce.OrderRepository, momo *MoMo, vnpay *VNPay, zalopay *ZaloPay, clientURL string) *Handler {
	return &Handler{orderRepo: orderRepo, momo: momo, vnpay: vnpay, zalopay: zalopay, clientURL: clientURL}
}

func (h *Handler) Register(r *gin.RouterGroup, authMw gin.HandlerFunc) {
	authed := r.Group("/", authMw)
	authed.POST("/momo", h.initMoMo)
	authed.POST("/vnpay", h.initVNPay)
	authed.POST("/zalopay", h.initZaloPay)

	r.POST("/momo/ipn", h.momoIPN)
	r.GET("/momo/callback", h.momoCallback)
	r.GET("/vnpay/return", h.vnpayReturn)
	r.POST("/zalopay/callback", h.zaloPayCallback)
}

type initReq struct {
	OrderID uuid.UUID `json:"order_id" binding:"required"`
}

func (h *Handler) initMoMo(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	var req initReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	order, err := h.orderRepo.GetByID(c.Request.Context(), req.OrderID)
	if err != nil {
		c.Error(httpx.NewNotFound("order not found"))
		return
	}
	if order.BuyerID != uid {
		c.Error(httpx.NewNotFound("order not found"))
		return
	}
	if order.PaymentStatus == "paid" {
		c.Error(httpx.NewPayment("already paid"))
		return
	}
	res, err := h.momo.Create(c.Request.Context(), MoMoCreateInput{
		OrderID:   order.ID.String(),
		Amount:    order.TotalPrice,
		OrderInfo: "Thanh toan don hang " + order.ID.String(),
		ExtraData: fmt.Sprintf(`{"orderId":"%s"}`, order.ID.String()),
	})
	if err != nil {
		c.Error(httpx.NewPayment("momo init failed: " + err.Error()))
		return
	}
	c.JSON(http.StatusOK, gin.H{"pay_url": res.PayURL, "deeplink": res.Deeplink, "qr_code_url": res.QRCodeURL})
}

func (h *Handler) momoIPN(c *gin.Context) {
	var ipn MoMoIPN
	if err := c.ShouldBindJSON(&ipn); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"message": "invalid payload"})
		return
	}
	if !h.momo.VerifyIPN(&ipn) {
		c.JSON(http.StatusBadRequest, gin.H{"message": "invalid signature"})
		return
	}
	if ipn.ResultCode == 0 {
		orderID, err := uuid.Parse(ipn.OrderID)
		if err == nil {
			_ = h.orderRepo.MarkPaid(c.Request.Context(), orderID, "MoMo", strconv.FormatInt(ipn.TransID, 10))
		}
	}
	c.JSON(http.StatusOK, gin.H{"message": "ok"})
}

func (h *Handler) momoCallback(c *gin.Context) {
	orderID := c.Query("orderId")
	resultCode := c.Query("resultCode")
	status := "failed"
	if resultCode == "0" {
		if oid, err := uuid.Parse(orderID); err == nil {
			_ = h.orderRepo.MarkPaid(c.Request.Context(), oid, "MoMo", c.Query("transId"))
			status = "success"
		}
	}
	c.Redirect(http.StatusFound, fmt.Sprintf("%s/payment-result?status=%s&orderId=%s&method=momo", h.clientURL, status, orderID))
}

func (h *Handler) initVNPay(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	var req initReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	order, err := h.orderRepo.GetByID(c.Request.Context(), req.OrderID)
	if err != nil {
		c.Error(httpx.NewNotFound("order not found"))
		return
	}
	if order.BuyerID != uid {
		c.Error(httpx.NewNotFound("order not found"))
		return
	}
	if order.PaymentStatus == "paid" {
		c.Error(httpx.NewPayment("already paid"))
		return
	}
	payURL := h.vnpay.BuildPayURL(order.ID.String(), order.TotalPrice, c.ClientIP(), "vn")
	c.JSON(http.StatusOK, gin.H{"pay_url": payURL})
}

func (h *Handler) vnpayReturn(c *gin.Context) {
	q := c.Request.URL.Query()
	if !h.vnpay.VerifyReturn(q) {
		c.Redirect(http.StatusFound, fmt.Sprintf("%s/payment-result?status=failed&method=vnpay", h.clientURL))
		return
	}
	orderInfo := q.Get("vnp_OrderInfo")
	orderID := ExtractVNPayOrderID(orderInfo)
	respCode := q.Get("vnp_ResponseCode")
	status := "failed"
	if respCode == "00" {
		if oid, err := uuid.Parse(orderID); err == nil {
			_ = h.orderRepo.MarkPaid(c.Request.Context(), oid, "VNPay", q.Get("vnp_TransactionNo"))
			status = "success"
		}
	}
	c.Redirect(http.StatusFound, fmt.Sprintf("%s/payment-result?status=%s&orderId=%s&method=vnpay", h.clientURL, status, orderID))
}

// ---------- ZaloPay ----------

func (h *Handler) initZaloPay(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	var req initReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	order, err := h.orderRepo.GetByID(c.Request.Context(), req.OrderID)
	if err != nil || order.BuyerID != uid {
		c.Error(httpx.NewNotFound("order not found"))
		return
	}
	if order.PaymentStatus == "paid" {
		c.Error(httpx.NewPayment("already paid"))
		return
	}
	res, err := h.zalopay.Create(c.Request.Context(), ZaloPayCreateInput{
		OrderID:     order.ID.String(),
		Amount:      order.TotalPrice,
		Description: "Thanh toán đơn hàng " + order.ID.String(),
		AppUser:     uid.String(),
	})
	if err != nil {
		c.Error(httpx.NewPayment("zalopay init failed: " + err.Error()))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"order_url":      res.OrderURL,
		"zp_trans_token": res.ZpTransToken,
		"app_trans_id":   res.AppTransID,
	})
}

// zaloPayCallback - ZaloPay POSTs {data, mac, type} as JSON body. Must
// respond with {return_code:1} on success, {return_code:-1} on bad MAC.
func (h *Handler) zaloPayCallback(c *gin.Context) {
	var cb ZaloPayCallback
	if err := c.ShouldBindJSON(&cb); err != nil {
		c.JSON(http.StatusOK, gin.H{"return_code": -1, "return_message": "invalid payload"})
		return
	}
	res, err := h.zalopay.VerifyCallback(&cb)
	if err != nil || !res.Valid {
		c.JSON(http.StatusOK, gin.H{"return_code": -1, "return_message": "invalid mac"})
		return
	}
	if oid, err := uuid.Parse(res.OrderID); err == nil {
		_ = h.orderRepo.MarkPaid(c.Request.Context(), oid, "ZaloPay", res.TxID)
	}
	c.JSON(http.StatusOK, gin.H{"return_code": 1, "return_message": "success"})
}

// strconv kept in case future ZaloPay/MoMo methods need it.
var _ = strconv.Itoa
