package handler

import (
	"encoding/json"
	"net/http"
	"testing"
)

func TestPinCreate_WithImageURL(t *testing.T) {
	db := setupDB(t)
	seedPinUser(t, db, "Me", "🙂")
	e := authedPinEcho(db)

	const url = "https://cdn.example/r2/abc.jpg"
	body := `{"body":"写真つき","lat":35.0,"lng":139.0,"image_url":"` + url + `"}`
	rec := serveAuth(e, http.MethodPost, "/api/pins", "good", body)
	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, want 201 (%s)", rec.Code, rec.Body.String())
	}
	var resp createPinResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.Pin.ImageURL == nil || *resp.Pin.ImageURL != url {
		t.Fatalf("imageUrl = %v, want %q", resp.Pin.ImageURL, url)
	}

	// 取得でも imageUrl が返る。
	get := getAt(e, "/api/pins/"+resp.Pin.ID, "good")
	if get.Code != http.StatusOK {
		t.Fatalf("get status = %d, want 200", get.Code)
	}
	var got createPinResponse
	if err := json.Unmarshal(get.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode get: %v", err)
	}
	if got.Pin.ImageURL == nil || *got.Pin.ImageURL != url {
		t.Fatalf("get imageUrl = %v, want %q", got.Pin.ImageURL, url)
	}
}

func TestPinCreate_WithoutImageURL(t *testing.T) {
	db := setupDB(t)
	seedPinUser(t, db, "Me", "🙂")
	e := authedPinEcho(db)

	body := `{"body":"画像なし","lat":35.0,"lng":139.0}`
	rec := serveAuth(e, http.MethodPost, "/api/pins", "good", body)
	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, want 201 (%s)", rec.Code, rec.Body.String())
	}
	var resp createPinResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.Pin.ImageURL != nil {
		t.Fatalf("imageUrl = %v, want nil", *resp.Pin.ImageURL)
	}
}
