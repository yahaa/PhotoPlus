package api

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/yahaa/PhotoPlus/server/internal/auth"
	"github.com/yahaa/PhotoPlus/server/internal/index"
	"github.com/yahaa/PhotoPlus/server/internal/storage"
)

const testToken = "secret"

type memStore struct {
	mu      sync.Mutex
	objects map[string][]byte
}

func (m *memStore) key(tier, id, kind string) string { return tier + "/" + id + "/" + kind }

func (m *memStore) Put(_ context.Context, tier, id, kind, _ string, body io.Reader, _ int64) error {
	data, err := io.ReadAll(body)
	if err != nil {
		return err
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.objects[m.key(tier, id, kind)] = data
	return nil
}

func (m *memStore) Size(_ context.Context, tier, id, kind string) (int64, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	data, ok := m.objects[m.key(tier, id, kind)]
	if !ok {
		return 0, storage.ErrNotFound
	}
	return int64(len(data)), nil
}

func (m *memStore) Get(_ context.Context, tier, id, kind, _ string) (*storage.Object, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	data, ok := m.objects[m.key(tier, id, kind)]
	if !ok {
		return nil, storage.ErrNotFound
	}
	return &storage.Object{Body: io.NopCloser(bytes.NewReader(data)), Status: http.StatusOK, Length: fmt.Sprint(len(data))}, nil
}

func (m *memStore) Delete(_ context.Context, tier, id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	for key := range m.objects {
		if strings.HasPrefix(key, tier+"/"+id+"/") {
			delete(m.objects, key)
		}
	}
	return nil
}

type fixture struct {
	t     *testing.T
	srv   *httptest.Server
	store *memStore
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	indexer, err := index.Open(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = indexer.Close() })
	store := &memStore{objects: map[string][]byte{}}
	handler := NewRouter(auth.NewService(testToken), &PhotoHandlers{
		Index: indexer,
		Store: store,
		Now:   func() time.Time { return time.Unix(1_700_000_000, 0) },
	})
	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)
	return &fixture{t: t, srv: srv, store: store}
}

func (f *fixture) do(method, path string, body []byte, headers map[string]string) (int, []byte) {
	f.t.Helper()
	req, err := http.NewRequest(method, f.srv.URL+path, bytes.NewReader(body))
	if err != nil {
		f.t.Fatal(err)
	}
	req.Header.Set("Authorization", "Bearer "+testToken)
	for key, value := range headers {
		req.Header.Set(key, value)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		f.t.Fatal(err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		f.t.Fatal(err)
	}
	return resp.StatusCode, data
}

func hashOf(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func originalPath(id string, takenAt time.Time, extra url.Values) string {
	q := url.Values{
		"tier":     {"casual"},
		"takenAt":  {takenAt.Format(time.RFC3339Nano)},
		"filename": {"照片 1.HEIC"},
		"width":    {"4032"},
		"height":   {"3024"},
	}
	for key, values := range extra {
		q[key] = values
	}
	return "/api/v1/photos/" + id + "/original?" + q.Encode()
}

// commit uploads a whole photo the way a client does.
func (f *fixture) commit(data []byte, takenAt time.Time) string {
	f.t.Helper()
	id := hashOf(data)
	if code, body := f.do(http.MethodPut, "/api/v1/photos/"+id+"/thumbnail?tier=casual", []byte("thumb"), nil); code != http.StatusNoContent {
		f.t.Fatalf("thumbnail: %d %s", code, body)
	}
	code, body := f.do(http.MethodPut, originalPath(id, takenAt, nil), data, map[string]string{"Content-Type": "image/heic"})
	if code != http.StatusCreated {
		f.t.Fatalf("original: %d %s", code, body)
	}
	return id
}

func TestHealthzIsOpenButAPIRequiresToken(t *testing.T) {
	f := newFixture(t)
	resp, err := http.Get(f.srv.URL + "/healthz")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("healthz: %d", resp.StatusCode)
	}
	for _, header := range []string{"", "Bearer wrong", testToken} {
		req, _ := http.NewRequest(http.MethodGet, f.srv.URL+"/api/v1/photos", nil)
		if header != "" {
			req.Header.Set("Authorization", header)
		}
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusUnauthorized {
			t.Errorf("Authorization %q: got %d", header, resp.StatusCode)
		}
	}
}

func TestUploadCommitAndDownloadRoundTrip(t *testing.T) {
	f := newFixture(t)
	data := []byte("original bytes with exif")
	takenAt := time.Date(2024, 3, 1, 8, 0, 0, 0, time.UTC)
	id := f.commit(data, takenAt)

	code, body := f.do(http.MethodGet, "/api/v1/photos/"+id+"/original", nil, nil)
	if code != http.StatusOK || !bytes.Equal(body, data) {
		t.Fatalf("original: %d %q", code, body)
	}
	code, body = f.do(http.MethodGet, "/api/v1/photos/"+id, nil, nil)
	if code != http.StatusOK {
		t.Fatalf("metadata: %d", code)
	}
	var photo index.Photo
	if err := json.Unmarshal(body, &photo); err != nil {
		t.Fatal(err)
	}
	if photo.Filename != "照片 1.HEIC" || !photo.TakenAt.Equal(takenAt) || photo.SizeBytes != int64(len(data)) || photo.ContentType != "image/heic" {
		t.Fatalf("metadata: %+v", photo)
	}
}

func TestOriginalWithWrongHashIsNotCommitted(t *testing.T) {
	f := newFixture(t)
	id := hashOf([]byte("what the client hashed"))
	f.do(http.MethodPut, "/api/v1/photos/"+id+"/thumbnail?tier=casual", []byte("thumb"), nil)
	code, _ := f.do(http.MethodPut, originalPath(id, time.Now(), nil), []byte("what actually arrived"), nil)
	if code != http.StatusUnprocessableEntity {
		t.Fatalf("got %d", code)
	}
	if code, _ := f.do(http.MethodGet, "/api/v1/photos/"+id, nil, nil); code != http.StatusNotFound {
		t.Fatalf("row committed despite mismatch: %d", code)
	}
}

func TestOriginalNotCommittedWithoutThumbnail(t *testing.T) {
	f := newFixture(t)
	data := []byte("no thumbnail sent")
	id := hashOf(data)
	code, _ := f.do(http.MethodPut, originalPath(id, time.Now(), nil), data, nil)
	if code != http.StatusConflict {
		t.Fatalf("got %d", code)
	}
	if code, _ := f.do(http.MethodGet, "/api/v1/photos/"+id, nil, nil); code != http.StatusNotFound {
		t.Fatalf("row committed without thumbnail: %d", code)
	}
}

func TestLivePhotoNeedsItsMotionResource(t *testing.T) {
	f := newFixture(t)
	data, motion := []byte("still"), []byte("paired video")
	id := hashOf(data)
	f.do(http.MethodPut, "/api/v1/photos/"+id+"/thumbnail?tier=casual", []byte("thumb"), nil)
	path := originalPath(id, time.Now(), url.Values{"motionSize": {fmt.Sprint(len(motion))}})

	if code, _ := f.do(http.MethodPut, path, data, nil); code != http.StatusConflict {
		t.Fatalf("committed without motion: %d", code)
	}
	motionPath := "/api/v1/photos/" + id + "/motion?tier=casual"
	if code, _ := f.do(http.MethodPut, motionPath, motion, nil); code != http.StatusBadRequest {
		t.Fatalf("motion without hash: %d", code)
	}
	headers := map[string]string{"X-Content-SHA256": hashOf([]byte("something else"))}
	if code, _ := f.do(http.MethodPut, motionPath, motion, headers); code != http.StatusUnprocessableEntity {
		t.Fatalf("motion with wrong hash: %d", code)
	}
	headers["X-Content-SHA256"] = hashOf(motion)
	if code, _ := f.do(http.MethodPut, motionPath, motion, headers); code != http.StatusNoContent {
		t.Fatalf("motion: %d", code)
	}
	if code, _ := f.do(http.MethodPut, path, data, nil); code != http.StatusCreated {
		t.Fatalf("original: %d", code)
	}
}

func TestRetryNeverOverwritesCommittedPhoto(t *testing.T) {
	f := newFixture(t)
	data := []byte("durable")
	id := f.commit(data, time.Now())
	code, _ := f.do(http.MethodPut, originalPath(id, time.Now(), nil), []byte("corrupted retry"), nil)
	if code != http.StatusOK {
		t.Fatalf("retry: %d", code)
	}
	if _, body := f.do(http.MethodGet, "/api/v1/photos/"+id+"/original", nil, nil); !bytes.Equal(body, data) {
		t.Fatalf("committed bytes changed: %q", body)
	}
}

func TestListPagesNewestFirst(t *testing.T) {
	f := newFixture(t)
	base := time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC)
	var ids []string
	for i := 0; i < 5; i++ {
		ids = append(ids, f.commit([]byte(fmt.Sprintf("photo %d", i)), base.AddDate(0, i, 0)))
	}
	var got []string
	cursor := ""
	for pages := 0; ; pages++ {
		if pages > 5 {
			t.Fatal("pagination did not end")
		}
		code, body := f.do(http.MethodGet, "/api/v1/photos?limit=2&cursor="+url.QueryEscape(cursor), nil, nil)
		if code != http.StatusOK {
			t.Fatalf("list: %d %s", code, body)
		}
		var page struct {
			Items      []index.Photo `json:"items"`
			NextCursor string        `json:"nextCursor"`
		}
		if err := json.Unmarshal(body, &page); err != nil {
			t.Fatal(err)
		}
		for _, item := range page.Items {
			got = append(got, item.ID)
		}
		if cursor = page.NextCursor; cursor == "" {
			break
		}
	}
	if len(got) != len(ids) {
		t.Fatalf("got %d photos", len(got))
	}
	for i := range got {
		if got[i] != ids[len(ids)-1-i] {
			t.Fatalf("position %d out of order", i)
		}
	}
}

func TestDeleteRemovesRowAndObjects(t *testing.T) {
	f := newFixture(t)
	id := f.commit([]byte("to delete"), time.Now())
	if code, _ := f.do(http.MethodDelete, "/api/v1/photos/"+id, nil, nil); code != http.StatusNoContent {
		t.Fatalf("delete: %d", code)
	}
	if code, _ := f.do(http.MethodGet, "/api/v1/photos/"+id, nil, nil); code != http.StatusNotFound {
		t.Fatalf("row remains: %d", code)
	}
	if len(f.store.objects) != 0 {
		t.Fatalf("objects remain: %d", len(f.store.objects))
	}
}

func TestStatsCountsMotion(t *testing.T) {
	f := newFixture(t)
	data, motion := []byte("12345"), []byte("123")
	id := hashOf(data)
	f.do(http.MethodPut, "/api/v1/photos/"+id+"/thumbnail?tier=casual", []byte("thumb"), nil)
	f.do(http.MethodPut, "/api/v1/photos/"+id+"/motion?tier=casual", motion, map[string]string{"X-Content-SHA256": hashOf(motion)})
	f.do(http.MethodPut, originalPath(id, time.Now(), url.Values{"motionSize": {"3"}}), data, nil)
	_, body := f.do(http.MethodGet, "/api/v1/stats", nil, nil)
	var stats index.Stats
	if err := json.Unmarshal(body, &stats); err != nil {
		t.Fatal(err)
	}
	if stats.PhotoCount != 1 || stats.TotalBytes != 8 {
		t.Fatalf("stats: %+v", stats)
	}
}

func TestRejectsBadInput(t *testing.T) {
	f := newFixture(t)
	id := hashOf([]byte("x"))
	cases := []struct {
		name, method, path string
		want               int
	}{
		{"non-hash id", http.MethodPut, "/api/v1/photos/..%2f..%2fetc/original?tier=casual", http.StatusNotFound},
		{"unknown kind", http.MethodPut, "/api/v1/photos/" + id + "/exe?tier=casual", http.StatusNotFound},
		{"unknown tier", http.MethodPut, "/api/v1/photos/" + id + "/thumbnail?tier=gold", http.StatusBadRequest},
		{"missing takenAt", http.MethodPut, "/api/v1/photos/" + id + "/original?tier=casual&filename=a&width=1&height=1", http.StatusBadRequest},
		{"bad limit", http.MethodGet, "/api/v1/photos?limit=0", http.StatusBadRequest},
		{"bad cursor", http.MethodGet, "/api/v1/photos?cursor=nonsense", http.StatusBadRequest},
	}
	for _, tc := range cases {
		if code, _ := f.do(tc.method, tc.path, []byte("x"), nil); code != tc.want {
			t.Errorf("%s: got %d, want %d", tc.name, code, tc.want)
		}
	}
}
