package events

import (
	"context"
	"encoding/json"
	"log/slog"
	"time"

	"github.com/redis/go-redis/v9"
)

// EventBus uses Redis Streams as a lightweight RabbitMQ replacement.
// Each event type = one stream key. Consumer groups give at-least-once delivery.
type EventBus struct {
	rds *redis.Client
	log *slog.Logger
}

func New(rds *redis.Client, log *slog.Logger) *EventBus {
	return &EventBus{rds: rds, log: log}
}

const streamPrefix = "events:"

// Publish - non-blocking, persistent (MAXLEN 100000 ~).
func (b *EventBus) Publish(ctx context.Context, eventType string, payload any) error {
	data, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	return b.rds.XAdd(ctx, &redis.XAddArgs{
		Stream: streamPrefix + eventType,
		MaxLen: 100000,
		Approx: true,
		Values: map[string]any{"data": data, "ts": time.Now().UnixMilli()},
	}).Err()
}

// HandlerFunc - returns error to nack (will retry); nil to ack.
type HandlerFunc func(ctx context.Context, data []byte) error

// Subscribe - blocking consumer loop (run in goroutine).
func (b *EventBus) Subscribe(ctx context.Context, eventType, group, consumer string, fn HandlerFunc) {
	stream := streamPrefix + eventType
	// Create group if not exists
	_ = b.rds.XGroupCreateMkStream(ctx, stream, group, "0").Err()

	for {
		select {
		case <-ctx.Done():
			return
		default:
		}
		streams, err := b.rds.XReadGroup(ctx, &redis.XReadGroupArgs{
			Group:    group,
			Consumer: consumer,
			Streams:  []string{stream, ">"},
			Count:    10,
			Block:    5 * time.Second,
		}).Result()
		if err != nil && err != redis.Nil {
			b.log.Warn("xreadgroup", "err", err, "stream", stream)
			time.Sleep(2 * time.Second)
			continue
		}
		for _, s := range streams {
			for _, msg := range s.Messages {
				raw, _ := msg.Values["data"].(string)
				if err := fn(ctx, []byte(raw)); err != nil {
					b.log.Warn("handler error", "err", err, "stream", stream, "id", msg.ID)
					// no ack -> message stays pending; auto-retry on next read of pending
					continue
				}
				_ = b.rds.XAck(ctx, stream, group, msg.ID).Err()
			}
		}
	}
}
