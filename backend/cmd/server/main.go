package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/cymed/layer/backend/internal/config"
	"github.com/cymed/layer/backend/internal/database"
	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/cymed/layer/backend/internal/router"
)

func main() {
	cfg := config.Load()

	db, err := database.Connect(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("failed to connect database: %v", err)
	}

	if err := database.Migrate(db); err != nil {
		log.Fatalf("failed to migrate: %v", err)
	}

	if err := database.MigrateSQL(db); err != nil {
		log.Fatalf("failed to apply SQL migrations: %v", err)
	}

	verify := authmw.GoogleVerifier(cfg.GoogleOAuthClientID)
	if cfg.DevAuthBypass {
		// 開発専用: Google 検証をスキップし、id_token をそのまま subject として扱う。
		log.Println("⚠️  DEV_AUTH_BYPASS 有効: 認証検証をスキップしています（開発専用）")
		verify = func(ctx context.Context, idToken string) (string, error) {
			if idToken == "" {
				return "", errors.New("empty token")
			}
			return idToken, nil
		}
	}
	e := router.New(db, verify)

	port := cfg.Port
	if port == "" {
		port = "8080"
	}

	// サーバを別 goroutine で起動し、SIGINT/SIGTERM でグレースフルに停止する。
	go func() {
		log.Printf("listening on :%s", port)
		if err := e.Start(":" + port); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("server stopped: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("shutting down...")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := e.Shutdown(ctx); err != nil {
		log.Fatalf("graceful shutdown failed: %v", err)
	}
	log.Println("server gracefully stopped")
}
