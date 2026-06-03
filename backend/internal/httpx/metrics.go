package httpx

import (
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Metrics registers Prometheus collectors and returns a Gin middleware
// that records request count + latency, plus the /metrics handler.
type Metrics struct {
	reqTotal   *prometheus.CounterVec
	reqLatency *prometheus.HistogramVec
}

func NewMetrics() *Metrics {
	m := &Metrics{
		reqTotal: prometheus.NewCounterVec(prometheus.CounterOpts{
			Namespace: "tropia",
			Subsystem: "http",
			Name:      "requests_total",
			Help:      "Total HTTP requests by method, path, status.",
		}, []string{"method", "path", "status"}),
		reqLatency: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Namespace: "tropia",
			Subsystem: "http",
			Name:      "request_duration_seconds",
			Help:      "HTTP request latency in seconds.",
			Buckets:   prometheus.DefBuckets,
		}, []string{"method", "path"}),
	}
	prometheus.MustRegister(m.reqTotal, m.reqLatency)
	return m
}

func (m *Metrics) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		c.Next()
		// FullPath() returns the route pattern (e.g. "/api/live/streams/:id"),
		// not the concrete URL — keeps cardinality bounded.
		path := c.FullPath()
		if path == "" {
			path = "unknown"
		}
		status := strconv.Itoa(c.Writer.Status())
		m.reqTotal.WithLabelValues(c.Request.Method, path, status).Inc()
		m.reqLatency.WithLabelValues(c.Request.Method, path).Observe(time.Since(start).Seconds())
	}
}

func MetricsHandler() gin.HandlerFunc {
	h := promhttp.Handler()
	return func(c *gin.Context) {
		h.ServeHTTP(c.Writer, c.Request)
	}
}
