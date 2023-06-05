package app

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/KitRUM/golang-blueprint/basicrest/app/middlewares"
	"github.com/KitRUM/golang-blueprint/basicrest/pkg/log"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"golang.org/x/sync/errgroup"
)

const (
	// readTimeout represents default read timeout for the http.Server.
	readTimeout = 10 * time.Second

	// readHeaderTimeout represents default read header timeout for http.Server.
	readHeaderTimeout = 5 * time.Second

	// writeTimeout represents default write timeout for the http.Server.
	writeTimeout = 10 * time.Second

	// idleTimeout represents default idle timeout for the http.Server.
	idleTimeout = 90 * time.Second

	// shutdownTimeout represents server default shutdown timeout.
	shutdownTimeout = 5 * time.Second
)

// Server holds all dependencies for providing
// an HTTP transport functionality.
type Server struct {
	router chi.Router
	server *http.Server
	logger log.Logger
}

func NewServer(addr string, logger log.Logger, cat http.Handler) *Server {
	router := chi.NewRouter()

	s := Server{
		logger: logger,
		router: router,
		server: &http.Server{
			Addr:              addr,
			Handler:           router,
			ReadTimeout:       readTimeout,
			ReadHeaderTimeout: readHeaderTimeout,
			WriteTimeout:      writeTimeout,
			IdleTimeout:       idleTimeout,
		},
	}

	router.Use(
		middleware.Recoverer,
		middleware.StripSlashes,
	)

	router.Get("/health", s.healthCheck)
	router.Get("/metrics", s.metrics)

	router.Route("/v1", func(v1 chi.Router) {
		v1.Use(
			middlewares.LoggingMiddleware(s.logger),
			middlewares.MetricsMiddleware(),
		)

		v1.Mount("/cat", cat)
	})

	return &s
}

// Serve listen to incoming connections and serves each request.
func (s *Server) Serve(ctx context.Context) error {
	if s.server.Addr == "" {
		return fmt.Errorf("invalid listener address: %s", s.server.Addr)
	}

	g, serveCtx := errgroup.WithContext(ctx)

	// handle shutdown signal in the background.
	g.Go(func() error { return s.handleShutdown(serveCtx) })

	g.Go(func() error {
		s.logger.Infof("ListenerHTTP started to listen on: %s", s.server.Addr)

		if err := s.server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			return fmt.Errorf("listener failed: %w", err)
		}

		return nil
	})

	if err := g.Wait(); err != nil {
		s.logger.Errorf("Server failed: %s", err.Error())

		return err
	}

	s.logger.Infof("Bye!")

	return nil
}

func (*Server) metrics(w http.ResponseWriter, r *http.Request) {
	promhttp.Handler().ServeHTTP(w, r)
}

func (*Server) healthCheck(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
}

// handleShutdown blocks until select statement receives a signal from
// ctx.Done, after that new context.WithTimeout will be created and passed to
// http.Server Shutdown method.
//
// If Shutdown method returns non nil error, program will panic immediately.
func (s *Server) handleShutdown(ctx context.Context) error {
	<-ctx.Done()

	s.logger.Infof("Shutting down the listener!")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()

	if err := s.server.Shutdown(shutdownCtx); err != nil {
		return fmt.Errorf("failed to shutdown the listener gracefully: %w", err)
	}

	return nil
}
