'use strict';

/**
 * RabbitMQ event bus – dùng cho async microservice communication.
 *
 * Pattern: publish-subscribe qua topic exchange 'tropia.events'
 * Routing keys: 'order.created', 'user.registered', 'live.started', ...
 *
 * Producer (routes): publish(event, payload)
 * Consumer (workers): subscribe(pattern, handler) – chạy trong process riêng
 */

const amqp   = require('amqplib');
const cfg    = require('../config');
const logger = require('./logger');

const EXCHANGE      = 'tropia.events';
const EXCHANGE_TYPE = 'topic';
const RECONNECT_MS  = 5_000;

let _connection = null;
let _channel    = null;

async function connect() {
  try {
    _connection = await amqp.connect(cfg.rabbitmq.url);
    _channel    = await _connection.createChannel();

    await _channel.assertExchange(EXCHANGE, EXCHANGE_TYPE, { durable: true });

    _connection.on('close', () => {
      logger.warn('RabbitMQ connection closed – reconnecting...');
      _connection = null;
      _channel    = null;
      setTimeout(connect, RECONNECT_MS);
    });

    _connection.on('error', (err) => {
      logger.error({ err }, 'RabbitMQ connection error');
    });

    logger.info('RabbitMQ connected');
  } catch (err) {
    logger.error({ err }, 'RabbitMQ connect failed – retrying...');
    setTimeout(connect, RECONNECT_MS);
  }
}

/**
 * Publish event lên exchange.
 * @param {string} routingKey  – VD: 'order.created', 'user.registered'
 * @param {object} payload
 */
async function publish(routingKey, payload) {
  if (!_channel) {
    logger.warn({ routingKey }, 'RabbitMQ not ready – event dropped');
    return;
  }
  const msg = Buffer.from(JSON.stringify({
    event:     routingKey,
    payload,
    timestamp: new Date().toISOString(),
  }));
  _channel.publish(EXCHANGE, routingKey, msg, { persistent: true });
  logger.debug({ routingKey }, 'Event published');
}

/**
 * Subscribe một consumer tới pattern routing key.
 * @param {string}   bindingPattern  – VD: 'order.*', 'user.#', 'live.started'
 * @param {string}   queueName       – tên queue (persistent)
 * @param {Function} handler         – async (payload, routingKey) => void
 */
async function subscribe(bindingPattern, queueName, handler) {
  if (!_channel) throw new Error('RabbitMQ not connected');

  const q = await _channel.assertQueue(queueName, { durable: true });
  await _channel.bindQueue(q.queue, EXCHANGE, bindingPattern);
  _channel.prefetch(1); // xử lý 1 message tại 1 thời điểm

  _channel.consume(q.queue, async (msg) => {
    if (!msg) return;
    try {
      const { event, payload } = JSON.parse(msg.content.toString());
      await handler(payload, event);
      _channel.ack(msg);
    } catch (err) {
      logger.error({ err }, `Consumer error on queue ${queueName}`);
      // nack: không requeue để tránh poison message loop
      _channel.nack(msg, false, false);
    }
  });

  logger.info({ bindingPattern, queueName }, 'RabbitMQ consumer started');
}

module.exports = { connect, publish, subscribe };
