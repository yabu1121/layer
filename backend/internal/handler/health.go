package handler

import (
	"context"
	"net/http"
	"time"

	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

// Health は liveness 用エンドポイント（プロセスが生きていれば常に 200）。
func Health(c echo.Context) error {
	return c.JSON(http.StatusOK, map[string]string{"status": "ok"})
}

// ReadinessHandler は依存（DB）の疎通を確認する readiness probe。
type ReadinessHandler struct {
	db *gorm.DB
}

// NewReadinessHandler は ReadinessHandler を生成する。
func NewReadinessHandler(db *gorm.DB) *ReadinessHandler {
	return &ReadinessHandler{db: db}
}

// Ready は DB に ping して 200/503 を返す。LB や k8s の readiness 判定に使う。
func (h *ReadinessHandler) Ready(c echo.Context) error {
	sqlDB, err := h.db.DB()
	if err != nil {
		return c.JSON(http.StatusServiceUnavailable, map[string]string{"status": "db_unavailable"})
	}
	ctx, cancel := context.WithTimeout(c.Request().Context(), 2*time.Second)
	defer cancel()
	if err := sqlDB.PingContext(ctx); err != nil {
		return c.JSON(http.StatusServiceUnavailable, map[string]string{"status": "db_unavailable"})
	}
	return c.JSON(http.StatusOK, map[string]string{"status": "ready"})
}
