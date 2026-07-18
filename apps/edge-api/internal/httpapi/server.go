package httpapi

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/rodrigo-s-lange/smart-band/apps/edge-api/internal/application"
)

type Server struct {
	store  application.Store
	logger *slog.Logger
}

type healthResponse struct {
	Status       string     `json:"status"`
	Database     string     `json:"database"`
	LastBackupAt *time.Time `json:"last_backup_at"`
}

type readyResponse struct {
	Status string `json:"status"`
}

type errorResponse struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type contextKey string

const actorContextKey contextKey = "actor"

func New(store application.Store, logger *slog.Logger) http.Handler {
	server := &Server{store: store, logger: logger}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/health", server.health)
	mux.HandleFunc("GET /v1/ready", server.ready)
	mux.Handle("GET /v1/appliance", server.authenticate(http.HandlerFunc(server.appliance)))
	mux.Handle("GET /v1/queue", server.authenticate(http.HandlerFunc(server.queue)))
	mux.Handle("GET /v1/attractions", server.authenticate(http.HandlerFunc(server.attractions)))
	mux.Handle("GET /v1/gateways", server.authenticate(http.HandlerFunc(server.gateways)))
	mux.Handle("GET /v1/bands", server.authenticate(http.HandlerFunc(server.bands)))
	return server.accessLog(mux)
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	response := healthResponse{Status: "ok", Database: "ok"}
	status := http.StatusOK
	if err := s.store.Ping(ctx); err != nil {
		response.Status, response.Database, status = "degraded", "unreachable", http.StatusServiceUnavailable
	}
	writeJSON(w, status, response)
}

func (s *Server) ready(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := s.store.Ping(ctx); err != nil {
		writeError(w, http.StatusServiceUnavailable, "database_unreachable", "database is unavailable")
		return
	}
	if _, err := s.store.Appliance(ctx); err != nil {
		writeError(w, http.StatusServiceUnavailable, "appliance_not_configured", "appliance configuration is unavailable")
		return
	}
	writeJSON(w, http.StatusOK, readyResponse{Status: "ready"})
}

func (s *Server) appliance(w http.ResponseWriter, r *http.Request) {
	value, err := s.store.Appliance(r.Context())
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, value)
}

func (s *Server) queue(w http.ResponseWriter, r *http.Request) {
	value, err := s.store.Queue(r.Context())
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, value)
}

func (s *Server) attractions(w http.ResponseWriter, r *http.Request) {
	value, err := s.store.Attractions(r.Context())
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, value)
}

func (s *Server) gateways(w http.ResponseWriter, r *http.Request) {
	value, err := s.store.Gateways(r.Context())
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, value)
}

func (s *Server) bands(w http.ResponseWriter, r *http.Request) {
	value, err := s.store.Bands(r.Context())
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, value)
}

func (s *Server) authenticate(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var actor application.Actor
		var err error
		if header := r.Header.Get("Authorization"); strings.HasPrefix(header, "Bearer ") {
			hash := sha256.Sum256([]byte(strings.TrimPrefix(header, "Bearer ")))
			actor, err = s.store.AuthenticateGateway(r.Context(), hash[:])
		} else if cookie, cookieErr := r.Cookie("sb_session"); cookieErr == nil {
			hash := sha256.Sum256([]byte(cookie.Value))
			actor, err = s.store.AuthenticateOperator(r.Context(), hash[:])
		} else {
			err = pgx.ErrNoRows
		}
		if err != nil {
			if !errors.Is(err, pgx.ErrNoRows) {
				s.logger.ErrorContext(r.Context(), "authentication failed", "error", err)
			}
			writeError(w, http.StatusUnauthorized, "unauthorized", "valid gateway or operator credentials are required")
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), actorContextKey, actor)))
	})
}

func (s *Server) internalError(w http.ResponseWriter, r *http.Request, err error) {
	s.logger.ErrorContext(r.Context(), "request failed", "error", err)
	writeError(w, http.StatusInternalServerError, "internal_error", "the request could not be completed")
}

func (s *Server) accessLog(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestID := newRequestID()
		w.Header().Set("X-Request-ID", requestID)
		started := time.Now()
		recorder := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(recorder, r)
		s.logger.InfoContext(r.Context(), "http request",
			"request_id", requestID, "method", r.Method, "path", r.URL.Path,
			"status", recorder.status, "duration_ms", time.Since(started).Milliseconds())
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (w *statusRecorder) WriteHeader(status int) {
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, errorResponse{Code: code, Message: message})
}

func newRequestID() string {
	var value [8]byte
	if _, err := rand.Read(value[:]); err != nil {
		return "unavailable"
	}
	return hex.EncodeToString(value[:])
}
