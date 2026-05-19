package config

import (
	"log"
	"os"

	"github.com/joho/godotenv"
)

// Config はアプリ全体の設定値を保持する。
type Config struct {
	Port        string
	DatabaseURL string
}

// Load は .env と環境変数から設定を読み込む。
func Load() *Config {
	if err := godotenv.Load(); err != nil {
		log.Println("no .env file found, using environment variables")
	}
	return &Config{
		Port:        os.Getenv("PORT"),
		DatabaseURL: os.Getenv("DATABASE_URL"),
	}
}
