// Package config loads server settings from the environment.
package config

import (
	"errors"
	"os"
)

// Config holds server settings.
type Config struct {
	HTTPAddr string
	Token    string
	DBPath   string
	FilerURL string
}

// Load reads PHOTOPLUS_* variables. PHOTOPLUS_TOKEN is required: the API serves
// private photos, so it never starts open.
func Load() (Config, error) {
	cfg := Config{
		HTTPAddr: envOr("PHOTOPLUS_HTTP_ADDR", ":8080"),
		Token:    os.Getenv("PHOTOPLUS_TOKEN"),
		DBPath:   envOr("PHOTOPLUS_DB_PATH", "photoplus.db"),
		FilerURL: envOr("PHOTOPLUS_FILER_URL", "http://127.0.0.1:8888"),
	}
	if cfg.Token == "" {
		return Config{}, errors.New("PHOTOPLUS_TOKEN is required")
	}
	return cfg, nil
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
