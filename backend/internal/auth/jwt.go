package auth

import (
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

type Role string

const (
	RoleViewer Role = "viewer"
	RoleSeller Role = "seller"
	RoleAdmin  Role = "admin"
)

type Claims struct {
	UserID string `json:"user_id"`
	Role   Role   `json:"role"`
	jwt.RegisteredClaims
}

type Service struct {
	accessSecret  []byte
	refreshSecret []byte
	accessTTL     time.Duration
	refreshTTL    time.Duration
}

func NewService(accessSecret, refreshSecret string, accessTTL, refreshTTL time.Duration) *Service {
	return &Service{
		accessSecret:  []byte(accessSecret),
		refreshSecret: []byte(refreshSecret),
		accessTTL:     accessTTL,
		refreshTTL:    refreshTTL,
	}
}

func (s *Service) SignAccess(userID string, role Role) (string, error) {
	return s.sign(userID, role, s.accessSecret, s.accessTTL)
}

func (s *Service) SignRefresh(userID string, role Role) (string, error) {
	return s.sign(userID, role, s.refreshSecret, s.refreshTTL)
}

func (s *Service) sign(userID string, role Role, secret []byte, ttl time.Duration) (string, error) {
	now := time.Now()
	claims := &Claims{
		UserID: userID,
		Role:   role,
		RegisteredClaims: jwt.RegisteredClaims{
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(ttl)),
			Issuer:    "tropia",
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(secret)
}

func (s *Service) VerifyAccess(tokenStr string) (*Claims, error) {
	return s.verify(tokenStr, s.accessSecret)
}

func (s *Service) VerifyRefresh(tokenStr string) (*Claims, error) {
	return s.verify(tokenStr, s.refreshSecret)
}

func (s *Service) verify(tokenStr string, secret []byte) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenStr, &Claims{}, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return secret, nil
	})
	if err != nil {
		return nil, err
	}
	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, errors.New("invalid token")
	}
	return claims, nil
}
