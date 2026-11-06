package index

// Indexer stores file metadata for timeline / search. TODO: EXIF parse + DB upsert.
type Indexer struct{}

func New() *Indexer { return &Indexer{} }
