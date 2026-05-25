package handler

import (
	"encoding/json"
	"net/http"
	"testing"
)

func TestPinCreate_WithEmotion(t *testing.T) {
	db := setupDB(t)
	seedPinUser(t, db, "Me", "🙂")
	e := authedPinEcho(db)

	body := `{"body":"落ち着く場所","lat":35.0,"lng":139.0,"emotion":"calm"}`
	rec := serveAuth(e, http.MethodPost, "/api/pins", "good", body)
	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, want 201 (%s)", rec.Code, rec.Body.String())
	}
	var resp createPinResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.Pin.Emotion == nil || *resp.Pin.Emotion != "calm" {
		t.Fatalf("emotion = %v, want calm", resp.Pin.Emotion)
	}

	get := getAt(e, "/api/pins/"+resp.Pin.ID, "good")
	var got createPinResponse
	_ = json.Unmarshal(get.Body.Bytes(), &got)
	if got.Pin.Emotion == nil || *got.Pin.Emotion != "calm" {
		t.Fatalf("get emotion = %v, want calm", got.Pin.Emotion)
	}
}

func TestPinCreate_InvalidEmotion(t *testing.T) {
	db := setupDB(t)
	seedPinUser(t, db, "Me", "🙂")
	e := authedPinEcho(db)

	body := `{"body":"x","lat":35.0,"lng":139.0,"emotion":"angry"}`
	if rec := serveAuth(e, http.MethodPost, "/api/pins", "good", body); rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 (unknown emotion)", rec.Code)
	}
}

func TestPinCreate_WithoutEmotion(t *testing.T) {
	db := setupDB(t)
	seedPinUser(t, db, "Me", "🙂")
	e := authedPinEcho(db)

	body := `{"body":"感情なし","lat":35.0,"lng":139.0}`
	rec := serveAuth(e, http.MethodPost, "/api/pins", "good", body)
	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, want 201", rec.Code)
	}
	var resp createPinResponse
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp.Pin.Emotion != nil {
		t.Fatalf("emotion = %v, want nil", *resp.Pin.Emotion)
	}
}
