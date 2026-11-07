// Package auth guards the API. The single-user MVP uses one shared bearer token;
// scan-to-bind and family roles replace it later.
package auth

import (
	"crypto/sha256"
	"crypto/subtle"
	"net/http"
	"strings"
)

// Service validates bearer tokens.
type Service struct {
	tokenHash [sha256.Size]byte
}

// NewService returns a Service accepting token.
func NewService(token string) *Service {
	return &Service{tokenHash: sha256.Sum256([]byte(token))}
}

// Middleware rejects requests without the expected bearer token.
func (s *Service) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		got := sha256.Sum256([]byte(token))
		if !ok || subtle.ConstantTimeCompare(got[:], s.tokenHash[:]) != 1 {
			w.Header().Set("WWW-Authenticate", "Bearer")
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}
