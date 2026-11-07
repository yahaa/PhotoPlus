// Package migrations embeds the ordered SQL schema files.
package migrations

import "embed"

// Files holds every NNNNNN_name.sql file. Files apply in name order.
//
//go:embed *.sql
var Files embed.FS
