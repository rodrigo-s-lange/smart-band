package config

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"time"
)

type Config struct {
	HTTPAddress     string
	DatabaseURL     string
	ShutdownTimeout time.Duration
	DatabaseMaxConn int32
}

func Load() (Config, error) {
	cfg := Config{
		HTTPAddress:     envOrDefault("SMARTBAND_HTTP_ADDRESS", ":8080"),
		DatabaseURL:     os.Getenv("DATABASE_URL"),
		ShutdownTimeout: 10 * time.Second,
		DatabaseMaxConn: 10,
	}
	if cfg.DatabaseURL == "" {
		return Config{}, errors.New("DATABASE_URL is required")
	}

	if raw := os.Getenv("SMARTBAND_SHUTDOWN_TIMEOUT"); raw != "" {
		value, err := time.ParseDuration(raw)
		if err != nil || value <= 0 {
			return Config{}, fmt.Errorf("SMARTBAND_SHUTDOWN_TIMEOUT must be a positive duration")
		}
		cfg.ShutdownTimeout = value
	}
	if raw := os.Getenv("SMARTBAND_DATABASE_MAX_CONNS"); raw != "" {
		value, err := strconv.ParseInt(raw, 10, 32)
		if err != nil || value <= 0 {
			return Config{}, fmt.Errorf("SMARTBAND_DATABASE_MAX_CONNS must be a positive integer")
		}
		cfg.DatabaseMaxConn = int32(value)
	}
	return cfg, nil
}

func envOrDefault(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}
