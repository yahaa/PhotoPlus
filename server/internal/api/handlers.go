package api

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"regexp"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/yahaa/PhotoPlus/server/internal/index"
	"github.com/yahaa/PhotoPlus/server/internal/storage"
)

// Object kinds stored per photo.
const (
	kindOriginal  = "original"
	kindMotion    = "motion"
	kindThumbnail = "thumbnail"
)

const (
	defaultPageSize = 500
	maxPageSize     = 2000
	maxUploadBytes  = 20 << 30
)

var sha256Hex = regexp.MustCompile(`^[0-9a-f]{64}$`)

// ObjectStore is the object storage the handlers need.
type ObjectStore interface {
	Put(ctx context.Context, tier, id, kind, contentType string, body io.Reader, size int64) error
	Size(ctx context.Context, tier, id, kind string) (int64, error)
	Get(ctx context.Context, tier, id, kind, rangeHeader string) (*storage.Object, error)
	Delete(ctx context.Context, tier, id string) error
}

// PhotoHandlers serves the photo API.
type PhotoHandlers struct {
	Index *index.Indexer
	Store ObjectStore
	Now   func() time.Time
}

func (h *PhotoHandlers) stats(w http.ResponseWriter, r *http.Request) {
	s, err := h.Index.Stats(r.Context())
	if err != nil {
		serverError(w, "stats", err)
		return
	}
	writeJSON(w, http.StatusOK, s)
}

func (h *PhotoHandlers) list(w http.ResponseWriter, r *http.Request) {
	limit := defaultPageSize
	if raw := r.URL.Query().Get("limit"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 || n > maxPageSize {
			http.Error(w, "invalid limit", http.StatusBadRequest)
			return
		}
		limit = n
	}
	photos, next, err := h.Index.List(r.Context(), r.URL.Query().Get("cursor"), limit)
	if errors.Is(err, index.ErrBadCursor) {
		http.Error(w, "invalid cursor", http.StatusBadRequest)
		return
	}
	if err != nil {
		serverError(w, "list", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": photos, "nextCursor": next})
}

func (h *PhotoHandlers) get(w http.ResponseWriter, r *http.Request) {
	photo, ok := h.lookup(w, r)
	if ok {
		writeJSON(w, http.StatusOK, photo)
	}
}

func (h *PhotoHandlers) remove(w http.ResponseWriter, r *http.Request) {
	photo, ok := h.lookup(w, r)
	if !ok {
		return
	}
	// The row goes first: a failure below leaves unreachable objects, never a row pointing at missing data.
	if err := h.Index.Delete(r.Context(), photo.ID); err != nil {
		serverError(w, "delete row", err)
		return
	}
	if err := h.Store.Delete(r.Context(), photo.Tier, photo.ID); err != nil {
		serverError(w, "delete objects", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *PhotoHandlers) download(w http.ResponseWriter, r *http.Request) {
	kind := chi.URLParam(r, "kind")
	if !validKind(kind) {
		http.NotFound(w, r)
		return
	}
	photo, ok := h.lookup(w, r)
	if !ok {
		return
	}
	object, err := h.Store.Get(r.Context(), photo.Tier, photo.ID, kind, r.Header.Get("Range"))
	if errors.Is(err, storage.ErrNotFound) {
		http.NotFound(w, r)
		return
	}
	if err != nil {
		serverError(w, "get object", err)
		return
	}
	defer object.Body.Close()

	header := w.Header()
	switch kind {
	case kindOriginal:
		header.Set("Content-Type", photo.ContentType)
	case kindThumbnail:
		header.Set("Content-Type", "image/jpeg")
	default:
		header.Set("Content-Type", object.ContentType)
	}
	header.Set("Accept-Ranges", "bytes")
	// The id is the content hash, so a stored object never changes.
	header.Set("Cache-Control", "private, max-age=31536000, immutable")
	if object.Length != "" {
		header.Set("Content-Length", object.Length)
	}
	if object.ContentRange != "" {
		header.Set("Content-Range", object.ContentRange)
	}
	w.WriteHeader(object.Status)
	if _, err := io.Copy(w, object.Body); err != nil {
		log.Printf("download %s/%s: %v", photo.ID, kind, err)
	}
}

// upload stores one resource. Clients send thumbnail and motion first; the original
// goes last and commits the row, so a row means the whole photo is durable.
func (h *PhotoHandlers) upload(w http.ResponseWriter, r *http.Request) {
	id, kind := chi.URLParam(r, "id"), chi.URLParam(r, "kind")
	if !sha256Hex.MatchString(id) || !validKind(kind) {
		http.NotFound(w, r)
		return
	}
	existing, err := h.Index.Get(r.Context(), id)
	if err == nil {
		// Already committed: never overwrite durable data, and answer so retries are idempotent.
		_, _ = io.Copy(io.Discard, http.MaxBytesReader(w, r.Body, maxUploadBytes))
		writeJSON(w, http.StatusOK, existing)
		return
	}
	if !errors.Is(err, index.ErrNotFound) {
		serverError(w, "lookup", err)
		return
	}
	tier := r.URL.Query().Get("tier")
	if tier != "casual" && tier != "important" {
		http.Error(w, "tier must be casual or important", http.StatusBadRequest)
		return
	}

	var meta index.Photo
	if kind == kindOriginal {
		var ok bool
		if meta, ok = parseMeta(w, r); !ok {
			return
		}
	}
	expected := r.Header.Get("X-Content-SHA256")
	switch kind {
	case kindOriginal:
		expected = id
	case kindMotion:
		if !sha256Hex.MatchString(expected) {
			http.Error(w, "X-Content-SHA256 required", http.StatusBadRequest)
			return
		}
	}

	contentType := r.Header.Get("Content-Type")
	if contentType == "" {
		contentType = "application/octet-stream"
	}
	hash := sha256.New()
	counted := &countingReader{r: io.TeeReader(http.MaxBytesReader(w, r.Body, maxUploadBytes), hash)}
	if err := h.Store.Put(r.Context(), tier, id, kind, contentType, counted, r.ContentLength); err != nil {
		serverError(w, "put object", err)
		return
	}
	if expected != "" && hex.EncodeToString(hash.Sum(nil)) != expected {
		// The stored bytes are not what the client meant to send; a retry overwrites them.
		http.Error(w, "content hash mismatch", http.StatusUnprocessableEntity)
		return
	}
	if kind != kindOriginal {
		w.WriteHeader(http.StatusNoContent)
		return
	}

	meta.ID, meta.Tier, meta.ContentType, meta.SizeBytes = id, tier, contentType, counted.n
	meta.UploadedAt = h.Now().UTC().Truncate(time.Millisecond)
	if !h.verifyStored(w, r, meta) {
		return
	}
	if err := h.Index.Upsert(r.Context(), meta); err != nil {
		serverError(w, "commit", err)
		return
	}
	writeJSON(w, http.StatusCreated, meta)
}

// verifyStored checks every object of the photo is really in storage before commit.
func (h *PhotoHandlers) verifyStored(w http.ResponseWriter, r *http.Request, p index.Photo) bool {
	want := []struct {
		kind string
		size int64 // -1: any size
	}{{kindOriginal, p.SizeBytes}, {kindThumbnail, -1}}
	if p.MotionSize > 0 {
		want = append(want, struct {
			kind string
			size int64
		}{kindMotion, p.MotionSize})
	}
	for _, item := range want {
		size, err := h.Store.Size(r.Context(), p.Tier, p.ID, item.kind)
		if errors.Is(err, storage.ErrNotFound) {
			http.Error(w, item.kind+" not stored", http.StatusConflict)
			return false
		}
		if err != nil {
			serverError(w, "verify", err)
			return false
		}
		if item.size >= 0 && size != item.size {
			http.Error(w, item.kind+" size mismatch", http.StatusConflict)
			return false
		}
	}
	return true
}

func (h *PhotoHandlers) lookup(w http.ResponseWriter, r *http.Request) (index.Photo, bool) {
	id := chi.URLParam(r, "id")
	if !sha256Hex.MatchString(id) {
		http.NotFound(w, r)
		return index.Photo{}, false
	}
	photo, err := h.Index.Get(r.Context(), id)
	if errors.Is(err, index.ErrNotFound) {
		http.NotFound(w, r)
		return index.Photo{}, false
	}
	if err != nil {
		serverError(w, "lookup", err)
		return index.Photo{}, false
	}
	return photo, true
}

func parseMeta(w http.ResponseWriter, r *http.Request) (index.Photo, bool) {
	q := r.URL.Query()
	takenAt, err := time.Parse(time.RFC3339Nano, q.Get("takenAt"))
	if err != nil {
		http.Error(w, "takenAt must be RFC 3339", http.StatusBadRequest)
		return index.Photo{}, false
	}
	width, errW := strconv.Atoi(q.Get("width"))
	height, errH := strconv.Atoi(q.Get("height"))
	if errW != nil || errH != nil || width < 0 || height < 0 {
		http.Error(w, "width and height are required", http.StatusBadRequest)
		return index.Photo{}, false
	}
	filename := q.Get("filename")
	if filename == "" {
		http.Error(w, "filename is required", http.StatusBadRequest)
		return index.Photo{}, false
	}
	var motionSize int64
	if raw := q.Get("motionSize"); raw != "" {
		motionSize, err = strconv.ParseInt(raw, 10, 64)
		if err != nil || motionSize < 0 {
			http.Error(w, "invalid motionSize", http.StatusBadRequest)
			return index.Photo{}, false
		}
	}
	return index.Photo{
		TakenAt:       takenAt.UTC().Truncate(time.Millisecond),
		Filename:      filename,
		Width:         width,
		Height:        height,
		SourceLocalID: q.Get("sourceLocalId"),
		MotionSize:    motionSize,
	}, true
}

func validKind(kind string) bool {
	return kind == kindOriginal || kind == kindMotion || kind == kindThumbnail
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(value); err != nil {
		log.Printf("write json: %v", err)
	}
}

func serverError(w http.ResponseWriter, op string, err error) {
	log.Printf("%s: %v", op, err)
	http.Error(w, "internal error", http.StatusInternalServerError)
}

type countingReader struct {
	r io.Reader
	n int64
}

func (c *countingReader) Read(p []byte) (int, error) {
	n, err := c.r.Read(p)
	c.n += int64(n)
	return n, err
}
