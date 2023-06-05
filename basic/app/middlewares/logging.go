package middlewares

import (
	"net/http"
	"time"

	"github.com/KitRUM/golang-blueprint/basicrest/pkg/log"
	"github.com/go-chi/chi/v5/middleware"
)

// LoggingMiddleware represents logging middlewares.
func LoggingMiddleware(logger log.Logger) func(next http.Handler) http.Handler {
	format := "%s %d %s Remote: %s %s"

	return func(next http.Handler) http.Handler {
		fn := func(w http.ResponseWriter, r *http.Request) {
			start := time.Now().UTC()

			ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
			next.ServeHTTP(ww, r.WithContext(r.Context()))
			status := ww.Status()

			if status >= http.StatusBadRequest {
				logger.Errorf(format, r.Method, status, r.RequestURI, r.RemoteAddr, time.Since(start).String())
			} else {
				logger.Infof(format, r.Method, status, r.RequestURI, r.RemoteAddr, time.Since(start).String())
			}
		}

		return http.HandlerFunc(fn)
	}
}
