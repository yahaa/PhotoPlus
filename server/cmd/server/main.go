package main

import (
	"log"
	"net/http"

	"github.com/yahaa/PhotoPlus/server/internal/api"
	"github.com/yahaa/PhotoPlus/server/internal/config"
)

func main() {
	cfg := config.Load()
	r := api.NewRouter()
	addr := cfg.HTTPAddr
	log.Printf("photoplus server listening on %s", addr)
	if err := http.ListenAndServe(addr, r); err != nil {
		log.Fatal(err)
	}
}
