'use strict';

class AppError extends Error {
  constructor(message, statusCode, code) {
    super(message);
    this.statusCode    = statusCode;
    this.code          = code;
    this.isOperational = true;
  }
}

class ValidationError extends AppError {
  constructor(message, details) {
    super(message, 422, 'VALIDATION_ERROR');
    this.details = details;
  }
}
class AuthError     extends AppError { constructor(m) { super(m, 401, 'UNAUTHORIZED'); } }
class ForbiddenError extends AppError { constructor(m) { super(m, 403, 'FORBIDDEN'); } }
class NotFoundError  extends AppError { constructor(m) { super(m, 404, 'NOT_FOUND'); } }
class ConflictError  extends AppError { constructor(m) { super(m, 409, 'CONFLICT'); } }
class RateLimitError extends AppError { constructor(m = 'Too many requests') { super(m, 429, 'RATE_LIMIT'); } }
class PaymentError   extends AppError { constructor(m) { super(m, 402, 'PAYMENT_ERROR'); } }

module.exports = { AppError, ValidationError, AuthError, ForbiddenError, NotFoundError, ConflictError, RateLimitError, PaymentError };
