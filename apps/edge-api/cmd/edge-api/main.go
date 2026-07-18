package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/rodrigo-s-lange/smart-band/apps/edge-api/internal/application"
	"github.com/rodrigo-s-lange/smart-band/apps/edge-api/internal/config"
	"github.com/rodrigo-s-lange/smart-band/apps/edge-api/internal/httpapi"
	"github.com/rodrigo-s-lange/smart-band/apps/edge-api/internal/postgres"
	"github.com/rodrigo-s-lange/smart-band/apps/edge-api/internal/security"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	if err := run(logger); err != nil {
		logger.Error("edge-api stopped", "error", err)
		os.Exit(1)
	}
}

func run(logger *slog.Logger) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	keyEncryptionKey, err := security.LoadBandKeyEncryptionKey(cfg.BandKeyKEKFile)
	if err != nil {
		return err
	}
	bandKeyBox, err := security.NewBandKeyBox(keyEncryptionKey)
	for index := range keyEncryptionKey {
		keyEncryptionKey[index] = 0
	}
	if err != nil {
		return err
	}

	poolConfig, err := pgxpool.ParseConfig(cfg.DatabaseURL)
	if err != nil {
		return err
	}
	poolConfig.MaxConns = cfg.DatabaseMaxConn
	pool, err := pgxpool.NewWithConfig(context.Background(), poolConfig)
	if err != nil {
		return err
	}
	defer pool.Close()

	repository := postgres.New(pool)
	service := application.NewService(repository, bandKeyBox)
	server := &http.Server{
		Addr:              cfg.HTTPAddress,
		Handler:           httpapi.New(service, logger),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      0,
		IdleTimeout:       60 * time.Second,
	}

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	serveErrors := make(chan error, 1)
	go func() {
		logger.Info("edge-api listening", "address", cfg.HTTPAddress)
		serveErrors <- server.ListenAndServe()
	}()

	select {
	case signalValue := <-stop:
		logger.Info("shutdown requested", "signal", signalValue.String())
	case serveErr := <-serveErrors:
		if !errors.Is(serveErr, http.ErrServerClosed) {
			return serveErr
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
	defer cancel()
	return server.Shutdown(ctx)
}
