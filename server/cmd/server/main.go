package main

import (
	"log"
	"net/http"
	"time"

	"github.com/yahaa/PhotoPlus/server/internal/api"
	"github.com/yahaa/PhotoPlus/server/internal/auth"
	"github.com/yahaa/PhotoPlus/server/internal/config"
	"github.com/yahaa/PhotoPlus/server/internal/index"
	"github.com/yahaa/PhotoPlus/server/internal/storage"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatal(err)
	}
	indexer, err := index.Open(cfg.DBPath)
	if err != nil {
		log.Fatal(err)
	}
	defer indexer.Close()

	handler := api.NewRouter(auth.NewService(cfg.Token), &api.PhotoHandlers{
		Index: indexer,
		Store: storage.NewClient(cfg.FilerURL),
		Now:   time.Now,
	})
	// No read or write timeout: originals can take minutes over a home uplink.
	srv := &http.Server{Addr: cfg.HTTPAddr, Handler: handler, ReadHeaderTimeout: 10 * time.Second}
	log.Printf("photoplus server listening on %s", cfg.HTTPAddr)
	log.Fatal(srv.ListenAndServe())
}
