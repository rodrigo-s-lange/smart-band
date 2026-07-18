package httpapi

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/rodrigo-s-lange/smart-band/apps/edge-api/internal/application"
)

type fakeStore struct {
	pingErr error
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
	return application.Actor{Kind: "gateway", ProtocolID: 1}, nil
}
func (f *fakeStore) AuthenticateOperator(context.Context, []byte) (application.Actor, error) {
	return application.Actor{}, pgx.ErrNoRows
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
