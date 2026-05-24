package config

import (
	"log"
	"os"

	"github.com/joho/godotenv"
)

// Config はアプリ全体の設定値を保持する。
type Config struct {
	Port                string
	DatabaseURL         string
	GoogleOAuthClientID string
	// DevAuthBypass は開発専用。true のとき Google 検証をスキップし、
	// id_token をそのまま subject として受け入れる（本番では絶対に有効化しない）。
	DevAuthBypass bool
}

// Load は .env と環境変数から設定を読み込む。
func Load() *Config {
	if err := godotenv.Load(); err != nil {
		log.Println("no .env file found, using environment variables")
	}
	return &Config{
		Port:                os.Getenv("PORT"),
		DatabaseURL:         os.Getenv("DATABASE_URL"),
		GoogleOAuthClientID: os.Getenv("GOOGLE_OAUTH_CLIENT_ID"),
		DevAuthBypass: os.Getenv("DEV_AUTH_BYPASS") == "1" ||
			os.Getenv("DEV_AUTH_BYPASS") == "true",
	}
}
