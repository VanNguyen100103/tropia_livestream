'use strict';

const logger = require('../lib/logger');
const { AppError } = require('../errors/AppError');

function errorHandler() {
  return (err, req, res, _next) => {
    // Zod validation error
    if (err?.name === 'ZodError') {
      return res.status(422).json({
        error:   'Validation failed',
        code:    'VALIDATION_ERROR',
        details: err.errors.map(e => ({ path: e.path.join('.'), message: e.message })),
      });
    }

    // JWT errors
    if (err?.name === 'JsonWebTokenError' || err?.name === 'TokenExpiredError') {
      return res.status(401).json({ error: 'Invalid or expired token', code: 'UNAUTHORIZED' });
    }

    // Known operational errors
    if (err instanceof AppError) {
      return res.status(err.statusCode).json({
        error:   err.message,
        code:    err.code,
        details: err.details,
      });
    }

    // Unknown – don't leak internals
    logger.error('Unhandled error', { error: err.message, stack: err.stack, requestId: req.id });
    res.status(500).json({ error: 'Internal server error', code: 'INTERNAL_ERROR' });
  };
}

module.exports = { errorHandler };
