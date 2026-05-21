// Package middleware は echo 用の横断的ミドルウェアを提供する。
package middleware

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"github.com/cymed/layer/backend/internal/model"
	"github.com/labstack/echo/v4"
	"google.golang.org/api/idtoken"
	"gorm.io/gorm"
)

// currentUserKey は echo Context に認証ユーザーを格納するキー。
const currentUserKey = "current_user"

// VerifyFunc は ID トークンを検証し subject(sub) を返す。
// 実検証（Google）とテスト用スタブを差し替えられるよう関数型で抽象化する。
type VerifyFunc func(ctx context.Context, idToken string) (sub string, err error)

// GoogleVerifier は Google の ID トークンを署名検証し、aud == clientID を確認して
// sub を返す VerifyFunc を生成する。
func GoogleVerifier(clientID string) VerifyFunc {
	return func(ctx context.Context, idToken string) (string, error) {
		payload, err := idtoken.Validate(ctx, idToken, clientID)
		if err != nil {
			return "", err
		}
		return payload.Subject, nil
	}
}

// RequireAuth は Authorization: Bearer の ID トークンを検証し、対応する users 行を
// echo Context に *model.User として格納するミドルウェアを返す。
// 検証失敗・該当ユーザー不在はいずれも 401。publicPaths に挙げたルートパス
// （c.Path() と一致）は検証をスキップする（例: サインイン）。
func RequireAuth(db *gorm.DB, verify VerifyFunc, publicPaths ...string) echo.MiddlewareFunc {
	public := make(map[string]struct{}, len(publicPaths))
	for _, p := range publicPaths {
		public[p] = struct{}{}
	}
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			if _, ok := public[c.Path()]; ok {
				return next(c)
			}
			token, err := bearerToken(c.Request().Header.Get(echo.HeaderAuthorization))
			if err != nil {
				return echo.NewHTTPError(http.StatusUnauthorized, "missing bearer token")
			}
			sub, err := verify(c.Request().Context(), token)
			if err != nil {
				return echo.NewHTTPError(http.StatusUnauthorized, "invalid token")
			}
			var user model.User
			if err := db.Where("auth_uid = ?", sub).First(&user).Error; err != nil {
				return echo.NewHTTPError(http.StatusUnauthorized, "user not found")
			}
			c.Set(currentUserKey, &user)
			return next(c)
		}
	}
}

// CurrentUser はミドルウェアが格納した認証ユーザーを返す（未認証なら nil）。
func CurrentUser(c echo.Context) *model.User {
	u, _ := c.Get(currentUserKey).(*model.User)
	return u
}

// bearerToken は "Bearer <token>" ヘッダからトークン部分を取り出す。
func bearerToken(header string) (string, error) {
	const prefix = "Bearer "
	if len(header) <= len(prefix) || !strings.EqualFold(header[:len(prefix)], prefix) {
		return "", errors.New("invalid authorization header")
	}
	token := strings.TrimSpace(header[len(prefix):])
	if token == "" {
		return "", errors.New("empty token")
	}
	return token, nil
}
