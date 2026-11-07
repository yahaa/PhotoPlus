// Package index stores photo metadata for the timeline in SQLite.
package index

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"io/fs"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/yahaa/PhotoPlus/server/migrations"
	_ "modernc.org/sqlite" // database/sql driver
)

// Errors returned by the Indexer.
var (
	ErrNotFound  = errors.New("photo not found")
	ErrBadCursor = errors.New("malformed cursor")
)

// Photo is one committed photo.
type Photo struct {
	ID            string    `json:"id"`
	TakenAt       time.Time `json:"takenAt"`
	Filename      string    `json:"filename"`
	ContentType   string    `json:"contentType"`
	SizeBytes     int64     `json:"sizeBytes"`
	Tier          string    `json:"tier"`
	Width         int       `json:"width"`
	Height        int       `json:"height"`
	SourceLocalID string    `json:"sourceLocalId"`
	MotionSize    int64     `json:"motionSize"`
	UploadedAt    time.Time `json:"uploadedAt"`
}

// Stats summarises what the NAS holds.
type Stats struct {
	PhotoCount int64 `json:"photoCount"`
	TotalBytes int64 `json:"totalBytes"`
}

// Indexer is the SQLite-backed metadata store.
type Indexer struct {
	db *sql.DB
}

// Open opens the database at path and applies pending migrations.
func Open(path string) (*Indexer, error) {
	dsn := "file:" + (&url.URL{Path: path}).EscapedPath() + "?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	if err := migrate(db); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("migrate: %w", err)
	}
	return &Indexer{db: db}, nil
}

// Close releases the database.
func (i *Indexer) Close() error { return i.db.Close() }

func migrate(db *sql.DB) error {
	names, err := fs.Glob(migrations.Files, "*.sql")
	if err != nil {
		return err
	}
	sort.Strings(names)
	var version int
	if err := db.QueryRow("PRAGMA user_version").Scan(&version); err != nil {
		return err
	}
	for n := version; n < len(names); n++ {
		body, err := migrations.Files.ReadFile(names[n])
		if err != nil {
			return err
		}
		tx, err := db.Begin()
		if err != nil {
			return err
		}
		// PRAGMA takes no bind parameters; n is a loop counter.
		_, err = tx.Exec(string(body) + fmt.Sprintf("\nPRAGMA user_version = %d;", n+1))
		if err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("%s: %w", names[n], err)
		}
		if err := tx.Commit(); err != nil {
			return err
		}
	}
	return nil
}

// Upsert records a committed photo. Re-uploading the same content keeps one row.
func (i *Indexer) Upsert(ctx context.Context, p Photo) error {
	_, err := i.db.ExecContext(ctx, `
		INSERT INTO photos (id, taken_at, filename, content_type, size_bytes, tier, width, height, source_local_id, motion_size, uploaded_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT (id) DO UPDATE SET source_local_id = excluded.source_local_id`,
		p.ID, p.TakenAt.UnixMilli(), p.Filename, p.ContentType, p.SizeBytes, p.Tier, p.Width, p.Height,
		p.SourceLocalID, p.MotionSize, p.UploadedAt.UnixMilli())
	return err
}

// Get returns one photo or ErrNotFound.
func (i *Indexer) Get(ctx context.Context, id string) (Photo, error) {
	row := i.db.QueryRowContext(ctx, `SELECT `+columns+` FROM photos WHERE id = ?`, id)
	p, err := scan(row)
	if errors.Is(err, sql.ErrNoRows) {
		return Photo{}, ErrNotFound
	}
	return p, err
}

// List returns photos newest first plus the cursor for the next page ("" at the end).
func (i *Indexer) List(ctx context.Context, cursor string, limit int) ([]Photo, string, error) {
	query := `SELECT ` + columns + ` FROM photos`
	args := []any{}
	if cursor != "" {
		takenAt, id, err := parseCursor(cursor)
		if err != nil {
			return nil, "", err
		}
		query += ` WHERE (taken_at, id) < (?, ?)`
		args = append(args, takenAt, id)
	}
	query += ` ORDER BY taken_at DESC, id DESC LIMIT ?`
	args = append(args, limit+1)
	rows, err := i.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, "", err
	}
	defer rows.Close()
	photos := []Photo{}
	for rows.Next() {
		p, err := scan(rows)
		if err != nil {
			return nil, "", err
		}
		photos = append(photos, p)
	}
	if err := rows.Err(); err != nil {
		return nil, "", err
	}
	next := ""
	if len(photos) > limit {
		photos = photos[:limit]
		last := photos[limit-1]
		next = strconv.FormatInt(last.TakenAt.UnixMilli(), 10) + "_" + last.ID
	}
	return photos, next, nil
}

// Delete removes a row. Deleting a missing row returns ErrNotFound.
func (i *Indexer) Delete(ctx context.Context, id string) error {
	res, err := i.db.ExecContext(ctx, `DELETE FROM photos WHERE id = ?`, id)
	if err != nil {
		return err
	}
	if n, err := res.RowsAffected(); err != nil {
		return err
	} else if n == 0 {
		return ErrNotFound
	}
	return nil
}

// Stats totals the committed photos, including Live Photo motion resources.
func (i *Indexer) Stats(ctx context.Context) (Stats, error) {
	var s Stats
	err := i.db.QueryRowContext(ctx, `SELECT COUNT(*), COALESCE(SUM(size_bytes + motion_size), 0) FROM photos`).
		Scan(&s.PhotoCount, &s.TotalBytes)
	return s, err
}

const columns = `id, taken_at, filename, content_type, size_bytes, tier, width, height, source_local_id, motion_size, uploaded_at`

type scanner interface{ Scan(dest ...any) error }

func scan(s scanner) (Photo, error) {
	var p Photo
	var takenAt, uploadedAt int64
	err := s.Scan(&p.ID, &takenAt, &p.Filename, &p.ContentType, &p.SizeBytes, &p.Tier, &p.Width, &p.Height,
		&p.SourceLocalID, &p.MotionSize, &uploadedAt)
	if err != nil {
		return Photo{}, err
	}
	p.TakenAt = time.UnixMilli(takenAt).UTC()
	p.UploadedAt = time.UnixMilli(uploadedAt).UTC()
	return p, nil
}

func parseCursor(cursor string) (int64, string, error) {
	rawTakenAt, id, ok := strings.Cut(cursor, "_")
	if !ok {
		return 0, "", ErrBadCursor
	}
	takenAt, err := strconv.ParseInt(rawTakenAt, 10, 64)
	if err != nil {
		return 0, "", ErrBadCursor
	}
	return takenAt, id, nil
}
