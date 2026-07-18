package httpapi

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/rodrigo-s-lange/smart-band/apps/edge-api/internal/application"
)

type fakeStore struct {
	pingErr        error
	sightingErr    error
	sightingReport application.SightingReport
	streamEvents   []application.StreamEvent
	claimErr       error
	claimRequest   application.ClaimRequest
}

func (f *fakeStore) Ping(context.Context) error { return f.pingErr }
func (f *fakeStore) Appliance(context.Context) (application.ApplianceContext, error) {
	return application.ApplianceContext{TenantCode: "vrplay", SiteCode: "shopping-piloto"}, nil
}
func (f *fakeStore) Queue(context.Context) ([]application.QueueEntry, error) {
	return []application.QueueEntry{{InteractionID: 101, DisplayCode: "M7K-3PX", Status: "queued", QueuedAt: time.Unix(1, 0)}}, nil
}
func (f *fakeStore) Attractions(context.Context) ([]application.Attraction, error) {
	return []application.Attraction{}, nil
}
func (f *fakeStore) Gateways(context.Context) ([]application.Gateway, error) {
	return []application.Gateway{}, nil
}
func (f *fakeStore) Bands(context.Context) ([]application.Band, error) {
	return []application.Band{}, nil
}
func (f *fakeStore) AuthenticateGateway(_ context.Context, hash []byte) (application.Actor, error) {
	if len(hash) != 32 {
		return application.Actor{}, pgx.ErrNoRows
	}
	return application.Actor{Kind: "gateway", InternalID: "77777777-7777-7777-7777-777777777771", ProtocolID: 1}, nil
}
func (f *fakeStore) AuthenticateOperator(_ context.Context, hash []byte) (application.Actor, error) {
	if len(hash) != 32 {
		return application.Actor{}, pgx.ErrNoRows
	}
	return application.Actor{
		Kind: "operator", InternalID: "55555555-5555-5555-5555-555555555555",
		ProtocolID: 1, GatewayInternalID: "77777777-7777-7777-7777-777777777771",
	}, nil
}
func (f *fakeStore) ClaimInteraction(_ context.Context, actor application.Actor, request application.ClaimRequest) (application.ClaimResult, error) {
	f.claimRequest = request
	if actor.Kind != "operator" || actor.ProtocolID != request.OperatorGatewayID {
		return application.ClaimResult{}, application.ErrOperatorGatewayMismatch
	}
	if f.claimErr != nil {
		return application.ClaimResult{}, f.claimErr
	}
	return application.ClaimResult{
		TransactionID: "0102030405060708", InteractionID: request.InteractionID,
		RadioGatewayID: 2, LeaseExpiresAt: time.Date(2026, 7, 18, 12, 0, 10, 0, time.UTC),
	}, nil
}
func (f *fakeStore) ReportSighting(_ context.Context, _ application.Actor, report application.SightingReport) (application.SightingResult, error) {
	f.sightingReport = report
	if report.GatewayID != 1 {
		return application.SightingResult{}, application.ErrGatewayIdentityMismatch
	}
	if f.sightingErr != nil {
		return application.SightingResult{}, f.sightingErr
	}
	id := uint32(103)
	return application.SightingResult{Resolved: true, InteractionID: &id}, nil
}
func (f *fakeStore) EventsAfter(_ context.Context, sequence int64, _ int32) ([]application.StreamEvent, error) {
	if sequence == 0 {
		return f.streamEvents, nil
	}
	return []application.StreamEvent{}, nil
}

func testHandler(store application.Store) http.Handler {
	return New(store, slog.New(slog.NewTextHandler(io.Discard, nil)))
}

func TestHealth(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/v1/health", nil)
	response := httptest.NewRecorder()
	testHandler(&fakeStore{}).ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	if response.Header().Get("X-Request-ID") == "" {
		t.Fatal("missing X-Request-ID")
	}
}

func TestHealthDegraded(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/v1/health", nil)
	response := httptest.NewRecorder()
	testHandler(&fakeStore{pingErr: errors.New("offline")}).ServeHTTP(response, request)
	if response.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
}

func TestProtectedRouteRejectsMissingCredentials(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/v1/queue", nil)
	response := httptest.NewRecorder()
	testHandler(&fakeStore{}).ServeHTTP(response, request)
	if response.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
}

func TestProtectedRouteAcceptsGateway(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/v1/queue", nil)
	request.Header.Set("Authorization", "Bearer gateway-test-secret")
	response := httptest.NewRecorder()
	testHandler(&fakeStore{}).ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
}

func TestSightingRequiresAuthenticatedGatewayID(t *testing.T) {
	payload := base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{0x01}, 22))
	body, _ := json.Marshal(map[string]any{
		"gateway_id": 2, "rssi": -55,
		"received_at": "2026-07-18T12:00:00Z", "raw_payload": payload,
	})
	request := httptest.NewRequest(http.MethodPost, "/v1/sightings", bytes.NewReader(body))
	request.Header.Set("Authorization", "Bearer gateway-test-secret")
	response := httptest.NewRecorder()
	testHandler(&fakeStore{}).ServeHTTP(response, request)
	if response.Code != http.StatusForbidden {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
}

func TestSightingAcceptsContractBody(t *testing.T) {
	store := &fakeStore{}
	payload := base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{0x01}, 22))
	body, _ := json.Marshal(map[string]any{
		"gateway_id": 1, "rssi": -55,
		"received_at": "2026-07-18T12:00:00Z", "raw_payload": payload,
	})
	request := httptest.NewRequest(http.MethodPost, "/v1/sightings", bytes.NewReader(body))
	request.Header.Set("Authorization", "Bearer gateway-test-secret")
	response := httptest.NewRecorder()
	testHandler(store).ServeHTTP(response, request)
	if response.Code != http.StatusOK || len(store.sightingReport.RawPayload) != 22 {
		t.Fatalf("status = %d report=%+v body=%s", response.Code, store.sightingReport, response.Body.String())
	}
}

func TestSightingReportsBandBusyAsConflict(t *testing.T) {
	store := &fakeStore{sightingErr: application.ErrBandBusy}
	payload := base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{0x01}, 22))
	body, _ := json.Marshal(map[string]any{
		"gateway_id": 1, "rssi": -55,
		"received_at": "2026-07-18T12:00:00Z", "raw_payload": payload,
	})
	request := httptest.NewRequest(http.MethodPost, "/v1/sightings", bytes.NewReader(body))
	request.Header.Set("Authorization", "Bearer gateway-test-secret")
	response := httptest.NewRecorder()
	testHandler(store).ServeHTTP(response, request)
	if response.Code != http.StatusConflict {
		t.Fatalf("status = %d body=%s", response.Code, response.Body.String())
	}
}

func TestClaimRequiresOperatorSession(t *testing.T) {
	body := strings.NewReader(`{"operator_gateway_id":1,"attraction_id":10}`)
	request := httptest.NewRequest(http.MethodPost, "/v1/interactions/101/claim", body)
	request.Header.Set("Authorization", "Bearer gateway-test-secret")
	response := httptest.NewRecorder()
	testHandler(&fakeStore{}).ServeHTTP(response, request)
	if response.Code != http.StatusForbidden {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
}

func TestClaimRejectsGatewayOutsideOperatorSession(t *testing.T) {
	body := strings.NewReader(`{"operator_gateway_id":2,"attraction_id":10}`)
	request := httptest.NewRequest(http.MethodPost, "/v1/interactions/101/claim", body)
	request.AddCookie(&http.Cookie{Name: "sb_session", Value: "operator-test-session"})
	response := httptest.NewRecorder()
	testHandler(&fakeStore{}).ServeHTTP(response, request)
	if response.Code != http.StatusForbidden {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
}

func TestClaimReturnsSelectedRadioAndLease(t *testing.T) {
	store := &fakeStore{}
	body := strings.NewReader(`{"operator_gateway_id":1,"attraction_id":10}`)
	request := httptest.NewRequest(http.MethodPost, "/v1/interactions/101/claim", body)
	request.AddCookie(&http.Cookie{Name: "sb_session", Value: "operator-test-session"})
	response := httptest.NewRecorder()
	testHandler(store).ServeHTTP(response, request)
	if response.Code != http.StatusOK || store.claimRequest.InteractionID != 101 {
		t.Fatalf("status=%d request=%+v body=%s", response.Code, store.claimRequest, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), `"radio_gateway_id":2`) {
		t.Fatalf("body=%s", response.Body.String())
	}
}

func TestClaimReportsNoRecentRadioAsConflict(t *testing.T) {
	store := &fakeStore{claimErr: application.ErrNoRadioGateway}
	body := strings.NewReader(`{"operator_gateway_id":1,"attraction_id":10}`)
	request := httptest.NewRequest(http.MethodPost, "/v1/interactions/101/claim", body)
	request.AddCookie(&http.Cookie{Name: "sb_session", Value: "operator-test-session"})
	response := httptest.NewRecorder()
	testHandler(store).ServeHTTP(response, request)
	if response.Code != http.StatusConflict || !strings.Contains(response.Body.String(), "no_radio_gateway") {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
}

func TestQueueStreamUsesEventSequenceAndEnvelope(t *testing.T) {
	store := &fakeStore{streamEvents: []application.StreamEvent{{
		Sequence: 7, EventType: "interaction.queued",
		Envelope: json.RawMessage(`{"event_type":"interaction.queued"}`),
	}}}
	ctx, cancel := context.WithTimeout(context.Background(), 650*time.Millisecond)
	defer cancel()
	request := httptest.NewRequest(http.MethodGet, "/v1/queue/stream", nil).WithContext(ctx)
	request.Header.Set("Authorization", "Bearer gateway-test-secret")
	response := httptest.NewRecorder()
	testHandler(store).ServeHTTP(response, request)
	if response.Code != http.StatusOK || !strings.Contains(response.Body.String(), "id: 7\nevent: interaction.queued") {
		t.Fatalf("status = %d body = %q", response.Code, response.Body.String())
	}
}
