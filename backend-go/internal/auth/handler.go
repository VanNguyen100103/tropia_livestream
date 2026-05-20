package auth

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

type User struct {
	ID           uuid.UUID `json:"id"`
	Email        string    `json:"email"`
	DisplayName  string    `json:"display_name"`
	AvatarURL    string    `json:"avatar_url,omitempty"`
	Role         Role      `json:"role"`
	CreatedAt    time.Time `json:"created_at"`
}

type Handler struct {
	db  *pgxpool.Pool
	jwt *Service
}

func NewHandler(db *pgxpool.Pool, jwtSvc *Service) *Handler {
	return &Handler{db: db, jwt: jwtSvc}
}

func (h *Handler) Register(r *gin.RouterGroup, authMw gin.HandlerFunc) {
	r.POST("/register", h.register)
	r.POST("/login", h.login)
	r.POST("/refresh", h.refresh)

	authed := r.Group("/", authMw)
	authed.GET("/me", h.me)
}

type registerReq struct {
	Email       string `json:"email" binding:"required,email"`
	Password    string `json:"password" binding:"required,min=8,max=72"`
	DisplayName string `json:"display_name" binding:"required,min=1,max=100"`
	Role        string `json:"role"`
}

func (h *Handler) register(c *gin.Context) {
	var req registerReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	role := Role(req.Role)
	if role != RoleSeller && role != RoleViewer {
		role = RoleViewer
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "hash failed"})
		return
	}

	const q = `
		INSERT INTO users (email, password_hash, display_name, role)
		VALUES ($1, $2, $3, $4)
		RETURNING id, email, display_name, role, created_at
	`
	var user User
	row := h.db.QueryRow(c.Request.Context(), q, req.Email, string(hash), req.DisplayName, role)
	if err := row.Scan(&user.ID, &user.Email, &user.DisplayName, &user.Role, &user.CreatedAt); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	access, _ := h.jwt.SignAccess(user.ID.String(), user.Role)
	refresh, _ := h.jwt.SignRefresh(user.ID.String(), user.Role)

	c.JSON(http.StatusCreated, gin.H{
		"user":          user,
		"access_token":  access,
		"refresh_token": refresh,
	})
}

type loginReq struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

func (h *Handler) login(c *gin.Context) {
	var req loginReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	const q = `SELECT id, email, password_hash, display_name, role, created_at FROM users WHERE email = $1`
	var (
		user         User
		passwordHash string
	)
	row := h.db.QueryRow(c.Request.Context(), q, req.Email)
	if err := row.Scan(&user.ID, &user.Email, &passwordHash, &user.DisplayName, &user.Role, &user.CreatedAt); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
		return
	}

	access, _ := h.jwt.SignAccess(user.ID.String(), user.Role)
	refresh, _ := h.jwt.SignRefresh(user.ID.String(), user.Role)

	c.JSON(http.StatusOK, gin.H{
		"user":          user,
		"access_token":  access,
		"refresh_token": refresh,
	})
}

type refreshReq struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

func (h *Handler) refresh(c *gin.Context) {
	var req refreshReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	claims, err := h.jwt.VerifyRefresh(req.RefreshToken)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid refresh token"})
		return
	}

	access, _ := h.jwt.SignAccess(claims.UserID, claims.Role)
	c.JSON(http.StatusOK, gin.H{"access_token": access})
}

func (h *Handler) me(c *gin.Context) {
	claims, _ := ClaimsFrom(c)
	userID, err := uuid.Parse(claims.UserID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user id"})
		return
	}

	const q = `SELECT id, email, display_name, role, created_at FROM users WHERE id = $1`
	var user User
	row := h.db.QueryRow(c.Request.Context(), q, userID)
	if err := row.Scan(&user.ID, &user.Email, &user.DisplayName, &user.Role, &user.CreatedAt); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}
	c.JSON(http.StatusOK, user)
}

// guard against unused import warning
var _ = context.Background
