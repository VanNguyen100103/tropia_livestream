package httpx

import (
	"errors"
	"net/http"
)

// AppError - mirrors Node.js AppError hierarchy
type AppError struct {
	StatusCode int
	Code       string
	Message    string
	Details    any
	Err        error
}

func (e *AppError) Error() string {
	if e.Err != nil {
		return e.Message + ": " + e.Err.Error()
	}
	return e.Message
}

func (e *AppError) Unwrap() error { return e.Err }

func NewValidation(msg string, details any) *AppError {
	return &AppError{StatusCode: http.StatusUnprocessableEntity, Code: "VALIDATION_ERROR", Message: msg, Details: details}
}
func NewAuth(msg string) *AppError {
	return &AppError{StatusCode: http.StatusUnauthorized, Code: "UNAUTHORIZED", Message: msg}
}
func NewForbidden(msg string) *AppError {
	return &AppError{StatusCode: http.StatusForbidden, Code: "FORBIDDEN", Message: msg}
}
func NewNotFound(msg string) *AppError {
	return &AppError{StatusCode: http.StatusNotFound, Code: "NOT_FOUND", Message: msg}
}
func NewConflict(msg string) *AppError {
	return &AppError{StatusCode: http.StatusConflict, Code: "CONFLICT", Message: msg}
}
func NewRateLimit(msg string) *AppError {
	return &AppError{StatusCode: http.StatusTooManyRequests, Code: "RATE_LIMITED", Message: msg}
}
func NewPayment(msg string) *AppError {
	return &AppError{StatusCode: http.StatusPaymentRequired, Code: "PAYMENT_ERROR", Message: msg}
}
func NewInternal(msg string, err error) *AppError {
	return &AppError{StatusCode: http.StatusInternalServerError, Code: "INTERNAL_ERROR", Message: msg, Err: err}
}

func AsAppError(err error) (*AppError, bool) {
	var ae *AppError
	if errors.As(err, &ae) {
		return ae, true
	}
	return nil, false
}
