// Package api serves the HTTP API used by the phone clients.
package api

import (
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/yahaa/PhotoPlus/server/internal/auth"
)

// NewRouter wires HTTP routes. Everything except /healthz requires the bearer token.
func NewRouter(authService *auth.Service, photos *PhotoHandlers) http.Handler {
	r := chi.NewRouter()
	r.Use(middleware.RequestID, middleware.RealIP, middleware.Logger, middleware.Recoverer)
	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	r.Route("/api/v1", func(r chi.Router) {
		r.Use(authService.Middleware)
		r.Get("/stats", photos.stats)
		r.Get("/photos", photos.list)
		r.Get("/photos/{id}", photos.get)
		r.Delete("/photos/{id}", photos.remove)
		r.Get("/photos/{id}/{kind}", photos.download)
		r.Put("/photos/{id}/{kind}", photos.upload)
	})
	return r
}
