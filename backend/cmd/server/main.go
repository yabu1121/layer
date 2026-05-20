package main

import (
	"log"
	"os"

	"github.com/cymed/layer/backend/internal/config"
	"github.com/cymed/layer/backend/internal/database"
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

	e := router.New(db)

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
