'use strict';

const server   = require('./server');
const auth     = require('./auth');
const payment  = require('./payment');
const services = require('./services');

// Re-export phẳng để mọi require('../config').xxx vẫn hoạt động
module.exports = {
  ...server,
  ...auth,
  ...services,
  ...payment,
};
