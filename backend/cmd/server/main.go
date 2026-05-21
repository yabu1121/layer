package main

import (
	"log"
	"os"

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
	e := router.New(db, verify)

	port := cfg.Port
	if port == "" {
		port = "8080"
	}
	log.Printf("listening on :%s", port)
	if err := e.Start(":" + port); err != nil {
		log.Printf("server stopped: %v", err)
		os.Exit(1)
	}
}
