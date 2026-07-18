package httpapi

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strconv"
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

type sightingRequest struct {
	GatewayID  uint16    `json:"gateway_id"`
	RSSI       int16     `json:"rssi"`
	ReceivedAt time.Time `json:"received_at"`
	RawPayload []byte    `json:"raw_payload"`
}

type claimRequest struct {
	OperatorGatewayID uint16 `json:"operator_gateway_id"`
	AttractionID      uint16 `json:"attraction_id"`
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
	mux.Handle("GET /v1/queue/stream", server.authenticate(http.HandlerFunc(server.queueStream)))
	mux.Handle("POST /v1/sightings", server.authenticate(http.HandlerFunc(server.sighting)))
	mux.Handle("POST /v1/interactions/{interaction_id}/claim", server.authenticate(http.HandlerFunc(server.claimInteraction)))
	mux.Handle("GET /v1/attractions", server.authenticate(http.HandlerFunc(server.attractions)))
	mux.Handle("GET /v1/gateways", server.authenticate(http.HandlerFunc(server.gateways)))
	mux.Handle("GET /v1/bands", server.authenticate(http.HandlerFunc(server.bands)))
	return server.accessLog(mux)
}

func (s *Server) claimInteraction(w http.ResponseWriter, r *http.Request) {
	interactionValue, err := strconv.ParseUint(r.PathValue("interaction_id"), 10, 32)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_interaction_id", "interaction_id must be an unsigned 32-bit integer")
		return
	}
	var request claimRequest
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1024))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "request body must be valid JSON")
		return
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		writeError(w, http.StatusBadRequest, "invalid_request", "request body must contain one JSON object")
		return
	}
	actor, ok := actorFromContext(r.Context())
	if !ok || actor.Kind != "operator" {
		writeError(w, http.StatusForbidden, "operator_required", "an operator session is required")
		return
	}
	result, err := s.store.ClaimInteraction(r.Context(), actor, application.ClaimRequest{
		InteractionID: uint32(interactionValue), OperatorGatewayID: request.OperatorGatewayID,
		AttractionID: request.AttractionID,
	})
	if err != nil {
		switch {
		case errors.Is(err, application.ErrClaimNotFound):
			writeError(w, http.StatusNotFound, "interaction_not_found", "interaction was not found")
		case errors.Is(err, application.ErrOperatorGatewayMismatch):
			writeError(w, http.StatusForbidden, "operator_gateway_mismatch", "operator session is not bound to this gateway")
		case errors.Is(err, application.ErrNoRadioGateway):
			writeError(w, http.StatusConflict, "no_radio_gateway", "no gateway has a recent authenticated sighting")
		case errors.Is(err, application.ErrInvalidAttraction):
			writeError(w, http.StatusConflict, "invalid_attraction", "attraction is unavailable at this operator gateway")
		case errors.Is(err, application.ErrClaimConflict):
			writeError(w, http.StatusConflict, "claim_conflict", "interaction is ambiguous or no longer claimable")
		default:
			s.internalError(w, r, err)
		}
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (s *Server) sighting(w http.ResponseWriter, r *http.Request) {
	var request sightingRequest
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "request body must be valid JSON")
		return
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		writeError(w, http.StatusBadRequest, "invalid_request", "request body must contain one JSON object")
		return
	}
	if len(request.RawPayload) != 22 || request.RSSI < -127 || request.RSSI > 20 || request.ReceivedAt.IsZero() {
		writeError(w, http.StatusBadRequest, "invalid_sighting", "gateway_id, rssi, received_at and a 22-byte payload are required")
		return
	}
	actor, ok := actorFromContext(r.Context())
	if !ok || actor.Kind != "gateway" {
		writeError(w, http.StatusForbidden, "gateway_required", "a gateway credential is required")
		return
	}
	result, err := s.store.ReportSighting(r.Context(), actor, application.SightingReport{
		GatewayID: request.GatewayID, RSSI: request.RSSI,
		GatewayObservedAt: request.ReceivedAt.UTC(), ReceivedAt: time.Now().UTC(),
		RawPayload: request.RawPayload,
	})
	if err != nil {
		if errors.Is(err, application.ErrGatewayIdentityMismatch) {
			writeError(w, http.StatusForbidden, "gateway_mismatch", "gateway_id does not match the authenticated gateway")
			return
		}
		if errors.Is(err, application.ErrBandBusy) {
			writeError(w, http.StatusConflict, "band_busy", "band already has an active interaction")
			return
		}
		s.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (s *Server) queueStream(w http.ResponseWriter, r *http.Request) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		writeError(w, http.StatusInternalServerError, "stream_unsupported", "streaming is unavailable")
		return
	}
	sequence := int64(0)
	if value := r.Header.Get("Last-Event-ID"); value != "" {
		parsed, err := strconv.ParseInt(value, 10, 64)
		if err != nil || parsed < 0 {
			writeError(w, http.StatusBadRequest, "invalid_last_event_id", "Last-Event-ID must be a non-negative integer")
			return
		}
		sequence = parsed
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.WriteHeader(http.StatusOK)
	flusher.Flush()

	poll := time.NewTicker(500 * time.Millisecond)
	heartbeat := time.NewTicker(15 * time.Second)
	defer poll.Stop()
	defer heartbeat.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case <-heartbeat.C:
			if _, err := io.WriteString(w, ": keep-alive\n\n"); err != nil {
				return
			}
			flusher.Flush()
		case <-poll.C:
			events, err := s.store.EventsAfter(r.Context(), sequence, 100)
			if err != nil {
				s.logger.ErrorContext(r.Context(), "queue stream poll failed", "error", err)
				return
			}
			for _, event := range events {
				if _, err := fmt.Fprintf(w, "id: %d\nevent: %s\ndata: %s\n\n", event.Sequence, event.EventType, event.Envelope); err != nil {
					return
				}
				sequence = event.Sequence
			}
			if len(events) > 0 {
				flusher.Flush()
			}
		}
	}
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

func actorFromContext(ctx context.Context) (application.Actor, bool) {
	actor, ok := ctx.Value(actorContextKey).(application.Actor)
	return actor, ok
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

func (w *statusRecorder) Flush() {
	if flusher, ok := w.ResponseWriter.(http.Flusher); ok {
		flusher.Flush()
	}
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
