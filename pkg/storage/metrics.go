package storage

import (
	"sync"
	"sync/atomic"
	"time"
)

// LatencyHistogram tracks latency metrics
type LatencyHistogram struct {
	buckets []int64
	counts  []int64
	mu      sync.RWMutex
}

// NewLatencyHistogram creates a new latency histogram
func NewLatencyHistogram() *LatencyHistogram {
	// Define buckets in microseconds: 1us, 10us, 100us, 1ms, 10ms, 100ms, 1s
	buckets := []int64{1, 10, 100, 1000, 10000, 100000, 1000000}
	counts := make([]int64, len(buckets)+1) // +1 for overflow bucket

	return &LatencyHistogram{
		buckets: buckets,
		counts:  counts,
	}
}

// Observe records a latency measurement
func (h *LatencyHistogram) Observe(duration time.Duration) {
	micros := duration.Nanoseconds() / 1000

	h.mu.Lock()
	defer h.mu.Unlock()

	for i, bucket := range h.buckets {
		if micros <= bucket {
			atomic.AddInt64(&h.counts[i], 1)
			return
		}
	}

	// Overflow bucket
	atomic.AddInt64(&h.counts[len(h.buckets)], 1)
}

// GetPercentile returns the specified percentile
func (h *LatencyHistogram) GetPercentile(percentile float64) time.Duration {
	h.mu.RLock()
	defer h.mu.RUnlock()

	var total int64
	for _, count := range h.counts {
		total += atomic.LoadInt64(&count)
	}

	if total == 0 {
		return 0
	}

	target := int64(float64(total) * percentile / 100.0)
	var sum int64

	for i, count := range h.counts {
		sum += atomic.LoadInt64(&count)
		if sum >= target {
			if i < len(h.buckets) {
				return time.Duration(h.buckets[i]) * time.Microsecond
			} else {
				return time.Second // Overflow bucket
			}
		}
	}

	return 0
}

// Counter tracks a monotonically increasing value
type Counter struct {
	value int64
}

// NewCounter creates a new counter
func NewCounter() *Counter {
	return &Counter{}
}

// Inc increments the counter by 1
func (c *Counter) Inc() {
	atomic.AddInt64(&c.value, 1)
}

// Add adds the given value to the counter
func (c *Counter) Add(delta float64) {
	atomic.AddInt64(&c.value, int64(delta))
}

// Value returns the current value
func (c *Counter) Value() int64 {
	return atomic.LoadInt64(&c.value)
}

// Gauge tracks a value that can go up and down
type Gauge struct {
	value int64
}

// NewGauge creates a new gauge
func NewGauge() *Gauge {
	return &Gauge{}
}

// Set sets the gauge to the given value
func (g *Gauge) Set(value float64) {
	atomic.StoreInt64(&g.value, int64(value))
}

// Inc increments the gauge by 1
func (g *Gauge) Inc() {
	atomic.AddInt64(&g.value, 1)
}

// Dec decrements the gauge by 1
func (g *Gauge) Dec() {
	atomic.AddInt64(&g.value, -1)
}

// Add adds the given value to the gauge
func (g *Gauge) Add(delta float64) {
	atomic.AddInt64(&g.value, int64(delta))
}

// Value returns the current value
func (g *Gauge) Value() int64 {
	return atomic.LoadInt64(&g.value)
}
