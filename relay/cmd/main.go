package main

import (
	"context"
	"crypto/tls"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/pocketclaude/relay/internal/api"
	"github.com/pocketclaude/relay/internal/presence"
	"github.com/pocketclaude/relay/internal/registry"
)

func main() {
	// CLI flags.
	addr := flag.String("addr", ":8080", "listen address (e.g. :8080, 0.0.0.0:9090)")
	tlsCert := flag.String("tls-cert", "", "path to TLS certificate file (optional)")
	tlsKey := flag.String("tls-key", "", "path to TLS private key file (optional)")
	logLevel := flag.String("log-level", "info", "log level: debug, info, warn, error")
	flag.Parse()

	// Setup structured logger.
	level := parseLogLevel(*logLevel)
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: level}))
	slog.SetDefault(logger)

	// Initialize core services.
	reg := registry.New()
	pres := presence.New(reg, logger)

	// Start presence checker in background.
	go pres.Start()

	// Setup HTTP handler.
	handler := api.NewHandler(reg, logger)
	mux := http.NewServeMux()
	mux.Handle("/ws", handler)

	// Health endpoint for load balancers / orchestrators.
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"ok"}`))
	})

	server := &http.Server{
		Addr:         *addr,
		Handler:      mux,
		ReadTimeout:  0, // no timeout for WebSocket connections
		WriteTimeout: 0,
		IdleTimeout:  120 * time.Second,
	}

	// Start server in background.
	serverErr := make(chan error, 1)
	go func() {
		logger.Info("relay server starting",
			"addr", *addr,
			"tls", *tlsCert != "",
		)

		var err error
		if *tlsCert != "" && *tlsKey != "" {
			cfg := &tls.Config{
				MinVersion: tls.VersionTLS12,
			}
			server.TLSConfig = cfg
			err = server.ListenAndServeTLS(*tlsCert, *tlsKey)
		} else {
			err = server.ListenAndServe()
		}
		serverErr <- err
	}()

	// Wait for interrupt signal or server error.
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	select {
	case err := <-serverErr:
		if err != nil && err != http.ErrServerClosed {
			logger.Error("server failed", "error", err)
			os.Exit(1)
		}
	case sig := <-quit:
		logger.Info("shutdown signal received", "signal", sig.String())
	}

	// Graceful shutdown with timeout.
	logger.Info("shutting down gracefully...")
	pres.Stop()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		logger.Error("server shutdown error", "error", err)
		os.Exit(1)
	}

	logger.Info("relay server stopped")
}

func parseLogLevel(level string) slog.Level {
	switch level {
	case "debug":
		return slog.LevelDebug
	case "info":
		return slog.LevelInfo
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}
