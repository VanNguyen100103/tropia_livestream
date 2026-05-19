'use strict';

const { createLogger, format, transports } = require('winston');

const { combine, timestamp, colorize, printf, json, errors } = format;

const devFormat = combine(
  colorize(),
  timestamp({ format: 'HH:mm:ss' }),
  errors({ stack: true }),
  printf(({ level, message, timestamp: ts, service, ...meta }) => {
    const extra = Object.keys(meta).length ? ' ' + JSON.stringify(meta) : '';
    return `${ts} [${service || 'backend'}] ${level}: ${message}${extra}`;
  }),
);

const prodFormat = combine(timestamp(), errors({ stack: true }), json());

const logger = createLogger({
  level:      process.env.LOG_LEVEL || 'info',
  format:     process.env.NODE_ENV === 'production' ? prodFormat : devFormat,
  defaultMeta: { service: 'tropia-backend' },
  transports: [new transports.Console()],
});

module.exports = logger;
