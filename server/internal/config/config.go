package config

// Config holds server settings loaded from env / files.
type Config struct {
	HTTPAddr string
	// TODO: SeaweedFS endpoints, DB DSN, Headscale, auth secrets
}

// Load returns config with defaults. TODO: parse env / yaml.
func Load() Config {
	return Config{HTTPAddr: ":8080"}
}
