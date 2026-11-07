-- Photos fully committed to object storage. A row exists only after the original,
-- thumbnail and any motion resource are stored and verified, so clients may treat
-- a row as permission to remove their local copy.
CREATE TABLE photos (
    id              TEXT PRIMARY KEY,          -- SHA-256 hex of the original bytes
    taken_at        INTEGER NOT NULL,          -- Unix milliseconds
    filename        TEXT NOT NULL,
    content_type    TEXT NOT NULL,
    size_bytes      INTEGER NOT NULL,
    tier            TEXT NOT NULL CHECK (tier IN ('casual', 'important')),
    width           INTEGER NOT NULL,
    height          INTEGER NOT NULL,
    source_local_id TEXT NOT NULL DEFAULT '',  -- PHAsset localIdentifier, used to de-duplicate timelines
    motion_size     INTEGER NOT NULL DEFAULT 0,-- Live Photo paired video; 0 means none
    uploaded_at     INTEGER NOT NULL
);

CREATE INDEX photos_timeline ON photos (taken_at DESC, id DESC);
