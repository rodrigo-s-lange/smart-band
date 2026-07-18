package postgres

import (
	"context"
	"crypto/sha256"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func TestStoreAgainstPostgreSQL(t *testing.T) {
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		t.Skip("DATABASE_URL is not set")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	store := New(pool)

	appliance, err := store.Appliance(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if appliance.TenantCode != "vrplay" || appliance.SiteCode != "shopping-piloto" {
		t.Fatalf("unexpected appliance: %+v", appliance)
	}

	gatewayToken := sha256.Sum256([]byte("gateway-test-secret"))
	actor, err := store.AuthenticateGateway(ctx, gatewayToken[:])
	if err != nil || actor.ProtocolID != 1 {
		t.Fatalf("gateway auth actor=%+v err=%v", actor, err)
	}
	operatorToken := sha256.Sum256([]byte("operator-test-session"))
	actor, err = store.AuthenticateOperator(ctx, operatorToken[:])
	if err != nil || actor.Kind != "operator" {
		t.Fatalf("operator auth actor=%+v err=%v", actor, err)
	}

	if _, err := pool.Exec(ctx, `
        UPDATE interaction_requests
           SET state = 'queued', expires_at = now() + interval '60 seconds'
         WHERE protocol_id = 101`); err != nil {
		t.Fatal(err)
	}
	queue, err := store.Queue(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(queue) != 1 || queue[0].InteractionID != 101 {
		t.Fatalf("unexpected queue: %+v", queue)
	}

	attractions, err := store.Attractions(ctx)
	if err != nil || len(attractions) != 1 || attractions[0].AttractionID != 10 {
		t.Fatalf("attractions=%+v err=%v", attractions, err)
	}
	gateways, err := store.Gateways(ctx)
	if err != nil || len(gateways) != 2 {
		t.Fatalf("gateways=%+v err=%v", gateways, err)
	}
	bands, err := store.Bands(ctx)
	if err != nil || len(bands) != 2 {
		t.Fatalf("bands=%+v err=%v", bands, err)
	}
}
