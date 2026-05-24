package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/labstack/echo/v4"
)

func setR2Env(t *testing.T) {
	t.Helper()
	t.Setenv("R2_ACCOUNT_ID", "acct123")
	t.Setenv("R2_BUCKET", "layer")
	t.Setenv("R2_ACCESS_KEY_ID", "AKIATEST")
	t.Setenv("R2_SECRET_ACCESS_KEY", "secrettest")
	t.Setenv("R2_PUBLIC_BASE_URL", "https://cdn.example")
}

func uploadReq(e *echo.Echo, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, "/p", strings.NewReader(body))
	req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)
	return rec
}

func TestPresign_ReturnsUploadAndPublicURL(t *testing.T) {
	setR2Env(t)
	e := echo.New()
	e.POST("/p", NewUploadHandler().PresignPinImage)

	rec := uploadReq(e, `{"contentType":"image/jpeg"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	var resp presignResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	// presigned PUT URL は R2 エンドポイント + 署名を含む。
	if !strings.Contains(resp.UploadURL, "acct123.r2.cloudflarestorage.com") {
		t.Fatalf("uploadUrl missing R2 endpoint: %s", resp.UploadURL)
	}
	if !strings.Contains(resp.UploadURL, "X-Amz-Signature") {
		t.Fatalf("uploadUrl not signed: %s", resp.UploadURL)
	}
	// publicUrl は公開ベース + 同じキー。
	if !strings.HasPrefix(resp.PublicURL, "https://cdn.example/pin-images/") ||
		!strings.HasSuffix(resp.PublicURL, ".jpg") {
		t.Fatalf("unexpected publicUrl: %s", resp.PublicURL)
	}
}

func TestPresign_RejectsNonImage(t *testing.T) {
	setR2Env(t)
	e := echo.New()
	e.POST("/p", NewUploadHandler().PresignPinImage)

	if rec := uploadReq(e, `{"contentType":"application/pdf"}`); rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rec.Code)
	}
}

func TestPresign_503WhenUnconfigured(t *testing.T) {
	// R2 env を空にする（未設定）。
	t.Setenv("R2_ACCOUNT_ID", "")
	t.Setenv("R2_BUCKET", "")
	t.Setenv("R2_ACCESS_KEY_ID", "")
	t.Setenv("R2_SECRET_ACCESS_KEY", "")
	t.Setenv("R2_PUBLIC_BASE_URL", "")
	e := echo.New()
	e.POST("/p", NewUploadHandler().PresignPinImage)

	if rec := uploadReq(e, `{"contentType":"image/jpeg"}`); rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", rec.Code)
	}
}
