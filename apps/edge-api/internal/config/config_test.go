package config

import (
	"testing"
	"time"
)

func TestLoadDefaults(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgresql://example")
	t.Setenv("SMARTBAND_BAND_KEY_KEK_FILE", "/run/secrets/band-key-kek")
	t.Setenv("SMARTBAND_HTTP_ADDRESS", "")
	t.Setenv("SMARTBAND_SHUTDOWN_TIMEOUT", "")
	t.Setenv("SMARTBAND_DATABASE_MAX_CONNS", "")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if cfg.HTTPAddress != ":8080" || cfg.ShutdownTimeout != 10*time.Second || cfg.DatabaseMaxConn != 10 {
		t.Fatalf("unexpected defaults: %+v", cfg)
	}
}

func TestLoadRequiresDatabaseURL(t *testing.T) {
	t.Setenv("DATABASE_URL", "")
	t.Setenv("SMARTBAND_BAND_KEY_KEK_FILE", "/run/secrets/band-key-kek")
	if _, err := Load(); err == nil {
		t.Fatal("Load() expected an error")
	}
}

func TestLoadRequiresBandKeyEncryptionKeyFile(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgresql://example")
	t.Setenv("SMARTBAND_BAND_KEY_KEK_FILE", "")
	if _, err := Load(); err == nil {
		t.Fatal("Load() expected an error")
	}
}
