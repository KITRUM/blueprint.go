package middlewares

import (
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

var (
	RespDurSec = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "requests_duration_seconds",
		Buckets: []float64{0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 1},
	}, []string{"method", "route", "code"})

	RespTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "requests_total",
	}, []string{"method", "route", "code"})
)

// MetricsMiddleware represents HTTP metrics collecting middlewares.
func MetricsMiddleware() func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		fn := func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			ctx := chi.RouteContext(r.Context())
			ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)

			next.ServeHTTP(ww, r)

			RespDurSec.WithLabelValues(r.Method, ctx.RoutePattern(), strconv.Itoa(ww.Status())).
				Observe(time.Since(start).Seconds())

			RespTotal.WithLabelValues(r.Method, ctx.RoutePattern(), strconv.Itoa(ww.Status())).
				Inc()
		}

		return http.HandlerFunc(fn)
	}
}
