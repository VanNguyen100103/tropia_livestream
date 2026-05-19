'use strict';

require('dotenv').config();

const express      = require('express');
const cors         = require('cors');
const cookieParser = require('cookie-parser');
const logger       = require('./lib/logger');
const config       = require('./config');
const passport     = require('./lib/passport');
const rabbitmq     = require('./lib/rabbitmq');

const { helmetConfig, requestId, sanitizeInput, requestSizeGuard, auditLog } = require('./middleware/security');
const { errorHandler } = require('./middleware/errorHandler');

const app = express();

app.use(helmetConfig());
app.use(cors({ origin: config.corsOrigin, credentials: true }));
app.set('trust proxy', 1);
app.use(requestId());
app.use(cookieParser());
app.use(express.json({ limit: '64kb' }));
app.use(sanitizeInput());
// Upload routes dùng multipart/form-data nên không áp dụng size guard JSON
app.use(/^(?!\/api\/upload)/, requestSizeGuard(64));
app.use(auditLog());
app.use(passport.initialize());

app.get('/health', (_, res) => res.json({ ok: true, service: 'tropia-backend', ts: Date.now() }));

app.use('/api/auth',       require('./routes/auth'));
app.use('/api/live',       require('./routes/live'));
app.use('/api/token',      require('./routes/token'));
app.use('/api/orders',     require('./routes/orders'));
app.use('/api/upload',     require('./routes/upload'));
app.use('/api/categories', require('./routes/categories'));
app.use('/api/shops',      require('./routes/shops'));
app.use('/api/products',   require('./routes/products'));
app.use('/api/payment',    require('./routes/payment'));
app.use('/api/coupons',    require('./routes/coupons'));
app.use('/api/cart',       require('./routes/cart'));

app.use((_, res) => res.status(404).json({ error: 'Route not found', code: 'NOT_FOUND' }));
app.use(errorHandler());

app.listen(config.port, () => {
  logger.info(`Tropia backend running on :${config.port}`);
  rabbitmq.connect().catch(err => logger.warn({ err }, 'RabbitMQ initial connect failed'));
});

module.exports = app;
