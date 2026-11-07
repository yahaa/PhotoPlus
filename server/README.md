# server

Go API on the NAS: photo upload, timeline index (SQLite), and object I/O through the SeaweedFS filer.

All `/api/v1` routes need `Authorization: Bearer $PHOTOPLUS_TOKEN`:

| Route | Purpose |
|-------|---------|
| `GET /healthz` | Liveness, no auth |
| `GET /api/v1/stats` | Photo count and bytes stored |
| `GET /api/v1/photos?limit=&cursor=` | Timeline, newest first |
| `GET` / `DELETE /api/v1/photos/{id}` | One photo's metadata, or delete it |
| `GET` / `PUT /api/v1/photos/{id}/{original,motion,thumbnail}` | Download (supports `Range`) or upload a resource |

`{id}` is the SHA-256 of the original. Upload `thumbnail` and any `motion` first (`motion` needs `X-Content-SHA256`). The `original` PUT goes last, takes `tier`, `takenAt`, `filename`, `width`, `height`, `sourceLocalId` and `motionSize` as query parameters, and commits the photo.
