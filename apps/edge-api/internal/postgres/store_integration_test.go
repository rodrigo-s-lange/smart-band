package postgres

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/rodrigo-s-lange/smart-band/apps/edge-api/internal/application"
	"github.com/rodrigo-s-lange/smart-band/apps/edge-api/internal/proximity"
	"github.com/rodrigo-s-lange/smart-band/apps/edge-api/internal/security"
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

func TestAtomicClaimSelectsStrongestRecentRadio(t *testing.T) {
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

	now := time.Now().UTC().Truncate(time.Microsecond)
	if _, err := pool.Exec(ctx, `DELETE FROM outbox_events`); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `
        DELETE FROM transaction_intents WHERE interaction_id IN (
            SELECT interaction_id FROM interaction_requests WHERE protocol_id IN (101, 102)
        )`); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `
        DELETE FROM interaction_claims WHERE interaction_id IN (
            SELECT interaction_id FROM interaction_requests WHERE protocol_id IN (101, 102)
        )`); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `
        DELETE FROM interaction_sightings WHERE interaction_id IN (
            SELECT interaction_id FROM interaction_requests WHERE protocol_id IN (101, 102)
        )`); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `
        UPDATE interaction_requests SET state = 'queued', expires_at = $1::timestamptz + interval '60 seconds'
         WHERE protocol_id IN (101, 102)`, now); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `
        INSERT INTO interaction_sightings (
            interaction_id, gateway_id, tenant_id, site_id, rssi, received_at, gateway_observed_at
        )
        SELECT i.interaction_id, g.gateway_id, i.tenant_id, i.site_id,
               CASE g.protocol_id WHEN 1 THEN -70 ELSE -40 END,
               $1::timestamptz - interval '2 seconds', $1::timestamptz - interval '2 seconds'
          FROM interaction_requests i CROSS JOIN gateways g
         WHERE i.protocol_id = 101 AND g.protocol_id IN (1, 2)`, now); err != nil {
		t.Fatal(err)
	}

	repository := New(pool)
	operatorToken := sha256.Sum256([]byte("operator-test-session"))
	actor, err := repository.AuthenticateOperator(ctx, operatorToken[:])
	if err != nil || actor.ProtocolID != 1 {
		t.Fatalf("actor=%+v err=%v", actor, err)
	}
	service := application.NewService(repository, nil, application.WithClock(func() time.Time { return now }))

	results := make(chan application.ClaimResult, 2)
	errorsFound := make(chan error, 2)
	var wait sync.WaitGroup
	for range 2 {
		wait.Add(1)
		go func() {
			defer wait.Done()
			result, claimErr := service.ClaimInteraction(ctx, actor, application.ClaimRequest{
				InteractionID: 101, OperatorGatewayID: 1, AttractionID: 10,
			})
			if claimErr != nil {
				errorsFound <- claimErr
				return
			}
			results <- result
		}()
	}
	wait.Wait()
	close(results)
	close(errorsFound)
	if len(results) != 1 || len(errorsFound) != 1 {
		t.Fatalf("successes=%d errors=%d", len(results), len(errorsFound))
	}
	winner := <-results
	loser := <-errorsFound
	if !errors.Is(loser, application.ErrClaimConflict) {
		t.Fatalf("loser error=%v", loser)
	}
	if winner.RadioGatewayID != 2 || !winner.LeaseExpiresAt.Equal(now.Add(10*time.Second)) {
		t.Fatalf("winner=%+v", winner)
	}

	var state, transactionStatus string
	var operatorGateway, radioGateway int
	var nonceLength, eventCount int
	if err := pool.QueryRow(ctx, `
        SELECT i.state, t.status, og.protocol_id, rg.protocol_id,
               octet_length(t.challenge_nonce),
               (SELECT count(*) FROM outbox_events WHERE event_type = 'interaction.claimed')
          FROM interaction_requests i
          JOIN transaction_intents t USING (interaction_id)
          JOIN gateways og ON og.gateway_id = t.operator_gateway_id
          JOIN gateways rg ON rg.gateway_id = t.radio_gateway_id
         WHERE i.protocol_id = 101`).Scan(
		&state, &transactionStatus, &operatorGateway, &radioGateway, &nonceLength, &eventCount); err != nil {
		t.Fatal(err)
	}
	if state != "claimed" || transactionStatus != "claimed" || operatorGateway != 1 || radioGateway != 2 || nonceLength != 8 || eventCount != 1 {
		t.Fatalf("state=%s tx=%s operator=%d radio=%d nonce=%d events=%d", state, transactionStatus, operatorGateway, radioGateway, nonceLength, eventCount)
	}

	if _, err := pool.Exec(ctx, `
        INSERT INTO operational_sessions (session_id, tenant_id, site_id, event_id)
        VALUES ('99999999-9999-9999-9999-999999999997',
                '11111111-1111-1111-1111-111111111111',
                '22222222-2222-2222-2222-222222222222',
                '33333333-3333-3333-3333-333333333333')`); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `
        INSERT INTO wallets (wallet_id, tenant_id, session_id, current_balance)
        VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2',
                '11111111-1111-1111-1111-111111111111',
                '99999999-9999-9999-9999-999999999997', 100)`); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `
        INSERT INTO band_assignments (tenant_id, session_id, band_id)
        VALUES ('11111111-1111-1111-1111-111111111111',
                '99999999-9999-9999-9999-999999999997',
                '66666666-6666-6666-6666-666666666662')`); err != nil {
		t.Fatal(err)
	}

	_, err = service.ClaimInteraction(ctx, actor, application.ClaimRequest{
		InteractionID: 102, OperatorGatewayID: 1, AttractionID: 10,
	})
	if !errors.Is(err, application.ErrNoRadioGateway) {
		t.Fatalf("no-radio error=%v", err)
	}
	if err := pool.QueryRow(ctx, `SELECT state FROM interaction_requests WHERE protocol_id = 102`).Scan(&state); err != nil {
		t.Fatal(err)
	}
	if state != "queued" {
		t.Fatalf("no-radio mutated state=%s", state)
	}
	if _, err := pool.Exec(ctx, `DELETE FROM band_assignments WHERE session_id = '99999999-9999-9999-9999-999999999997'`); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `DELETE FROM wallets WHERE session_id = '99999999-9999-9999-9999-999999999997'`); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `DELETE FROM operational_sessions WHERE session_id = '99999999-9999-9999-9999-999999999997'`); err != nil {
		t.Fatal(err)
	}
}

func TestAuthenticatedSightingDeduplicatesAndPublishes(t *testing.T) {
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
	repository := New(pool)
	box, err := security.NewBandKeyBox(bytes.Repeat([]byte{0x42}, 32))
	if err != nil {
		t.Fatal(err)
	}
	bandID := "66666666-6666-6666-6666-666666666661"
	bandKey := []byte{0x2b, 0x7e, 0x15, 0x16, 0x28, 0xae, 0xd2, 0xa6, 0xab, 0xf7, 0x15, 0x88, 0x09, 0xcf, 0x4f, 0x3c}
	envelope, err := box.Encrypt(bandID, bandKey)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `UPDATE bands SET encrypted_key = $1 WHERE band_id = $2`, envelope, bandID); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `UPDATE interaction_requests SET state = 'completed' WHERE band_id = $1`, bandID); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `DELETE FROM outbox_events`); err != nil {
		t.Fatal(err)
	}
	service := application.NewService(repository, box)
	payload := advertisingPayload(t, bandKey, [8]byte{9, 10, 11, 12, 13, 14, 15, 16}, 0x12345678)
	now := time.Now().UTC().Truncate(time.Microsecond)
	report := application.SightingReport{
		GatewayID: 1, RSSI: -52, GatewayObservedAt: now.Add(-20 * time.Millisecond),
		ReceivedAt: now, RawPayload: payload,
	}
	actor := application.Actor{
		Kind: "gateway", InternalID: "77777777-7777-7777-7777-777777777771", ProtocolID: 1,
	}
	first, err := service.ReportSighting(ctx, actor, report)
	if err != nil || !first.Resolved || first.InteractionID == nil {
		t.Fatalf("first=%+v err=%v", first, err)
	}
	report.ReceivedAt = now.Add(5 * time.Second)
	second, err := service.ReportSighting(ctx, actor, report)
	if err != nil || second.InteractionID == nil || *second.InteractionID != *first.InteractionID {
		t.Fatalf("second=%+v err=%v", second, err)
	}
	var interactions, sightings int
	var firstAuthenticated, expiresAt time.Time
	if err := pool.QueryRow(ctx, `
        SELECT count(*), min(first_authenticated_at), min(expires_at)
          FROM interaction_requests
         WHERE band_id = $1 AND session_nonce = $2`, bandID, payload[1:9]).Scan(
		&interactions, &firstAuthenticated, &expiresAt); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `
        SELECT count(*) FROM interaction_sightings s
        JOIN interaction_requests i USING (interaction_id)
        WHERE i.band_id = $1 AND i.session_nonce = $2`, bandID, payload[1:9]).Scan(&sightings); err != nil {
		t.Fatal(err)
	}
	if interactions != 1 || sightings != 2 || !expiresAt.Equal(firstAuthenticated.Add(60*time.Second)) {
		t.Fatalf("interactions=%d sightings=%d first=%s expires=%s", interactions, sightings, firstAuthenticated, expiresAt)
	}
	events, err := repository.EventsAfter(ctx, 0, 100)
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 2 || events[0].EventType != "interaction.discovered" || events[1].EventType != "interaction.queued" {
		t.Fatalf("events=%+v", events)
	}

	tampered := append([]byte(nil), payload...)
	tampered[9] ^= 0xff
	report.RawPayload = tampered
	invalid, err := service.ReportSighting(ctx, actor, report)
	if err != nil || invalid.Resolved {
		t.Fatalf("tampered=%+v err=%v", invalid, err)
	}
	if err := pool.QueryRow(ctx, `
        SELECT count(*) FROM interaction_sightings s
        JOIN interaction_requests i USING (interaction_id)
        WHERE i.band_id = $1 AND i.session_nonce = $2`, bandID, payload[1:9]).Scan(&sightings); err != nil {
		t.Fatal(err)
	}
	if sightings != 2 {
		t.Fatalf("invalid advertising created a sighting: count=%d", sightings)
	}

	secondBandID := "66666666-6666-6666-6666-666666666662"
	secondKey := bytes.Repeat([]byte{0x5a}, 16)
	secondEnvelope, err := box.Encrypt(secondBandID, secondKey)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `UPDATE bands SET encrypted_key = $1 WHERE band_id = $2`, secondEnvelope, secondBandID); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `UPDATE interaction_requests SET state = 'completed' WHERE band_id = $1`, secondBandID); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `
        INSERT INTO participants (participant_id, tenant_id, external_reference)
        VALUES ('44444444-4444-4444-4444-444444444445',
                '11111111-1111-1111-1111-111111111111', 'fixture-collision');
        INSERT INTO operational_sessions (
            session_id, tenant_id, site_id, event_id, participant_id
        ) VALUES (
            '99999999-9999-9999-9999-999999999998',
            '11111111-1111-1111-1111-111111111111',
            '22222222-2222-2222-2222-222222222222',
            '33333333-3333-3333-3333-333333333333',
            '44444444-4444-4444-4444-444444444445'
        );
        INSERT INTO band_assignments (tenant_id, session_id, band_id)
        VALUES (
            '11111111-1111-1111-1111-111111111111',
            '99999999-9999-9999-9999-999999999998',
            '66666666-6666-6666-6666-666666666662'
        )`); err != nil {
		t.Fatal(err)
	}
	report.RawPayload = advertisingPayload(t, secondKey, [8]byte{33, 34, 35, 36, 37, 38, 39, 40}, 0x12345678)
	report.ReceivedAt = now.Add(6 * time.Second)
	collision, err := service.ReportSighting(ctx, actor, report)
	if err != nil || !collision.Resolved {
		t.Fatalf("collision=%+v err=%v", collision, err)
	}
	var ambiguous int
	if err := pool.QueryRow(ctx, `
        SELECT count(*) FROM interaction_requests
         WHERE display_code = '938-NKR' AND state = 'queued_ambiguous'`).Scan(&ambiguous); err != nil {
		t.Fatal(err)
	}
	if ambiguous != 2 {
		t.Fatalf("ambiguous interactions=%d", ambiguous)
	}
}

func advertisingPayload(t *testing.T, key []byte, nonce [8]byte, displayCode uint32) []byte {
	t.Helper()
	payload := make([]byte, proximity.AdvertisingLength)
	payload[0] = proximity.ProtocolVersion
	copy(payload[1:9], nonce[:])
	binary.LittleEndian.PutUint32(payload[17:21], displayCode)
	payload[21] = proximity.RequestTTLSeconds
	message := append([]byte{1}, payload[0])
	message = append(message, payload[1:9]...)
	message = append(message, payload[17:22]...)
	tag, err := proximity.AESCMAC(key, message)
	if err != nil {
		t.Fatal(err)
	}
	copy(payload[9:17], tag[:8])
	return payload
}
