package postgres

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/rodrigo-s-lange/smart-band/apps/edge-api/internal/application"
	db "github.com/rodrigo-s-lange/smart-band/apps/edge-api/internal/postgres/generated"
)

type Store struct {
	pool    *pgxpool.Pool
	queries *db.Queries
}

func New(pool *pgxpool.Pool) *Store {
	return &Store{pool: pool, queries: db.New(pool)}
}

func (s *Store) Ping(ctx context.Context) error {
	return s.pool.Ping(ctx)
}

func (s *Store) Appliance(ctx context.Context) (application.ApplianceContext, error) {
	row, err := s.queries.GetApplianceContext(ctx)
	if err != nil {
		return application.ApplianceContext{}, err
	}
	return application.ApplianceContext{
		TenantID: row.TenantID, TenantCode: row.TenantCode, TenantName: row.TenantName,
		SiteID: row.SiteID, SiteCode: row.SiteCode, SiteName: row.SiteName,
		Timezone: row.Timezone, ApplianceName: row.ApplianceName,
		EventID: row.EventID, EventCode: row.EventCode, EventName: row.EventName,
	}, nil
}

func (s *Store) Queue(ctx context.Context) ([]application.QueueEntry, error) {
	rows, err := s.queries.ListQueue(ctx)
	if err != nil {
		return nil, err
	}
	entries := make([]application.QueueEntry, 0, len(rows))
	byCode := make(map[string][]uint32)
	for _, row := range rows {
		id := uint32(row.ProtocolID)
		byCode[row.DisplayCode] = append(byCode[row.DisplayCode], id)
		entries = append(entries, application.QueueEntry{
			InteractionID: id, DisplayCode: row.DisplayCode, Status: row.State,
			QueuedAt: row.CreatedAt.Time,
		})
	}
	for index := range entries {
		collisions := byCode[entries[index].DisplayCode]
		if len(collisions) < 2 {
			continue
		}
		entries[index].Status = "queued_ambiguous"
		for _, id := range collisions {
			if id != entries[index].InteractionID {
				entries[index].CollidesWith = append(entries[index].CollidesWith, id)
			}
		}
	}
	return entries, nil
}

func (s *Store) Attractions(ctx context.Context) ([]application.Attraction, error) {
	rows, err := s.queries.ListAttractions(ctx)
	if err != nil {
		return nil, err
	}
	items := make([]application.Attraction, 0, len(rows))
	for _, row := range rows {
		items = append(items, application.Attraction{
			AttractionID: uint16(row.ProtocolID), Name: row.DisplayName, DefaultCost: row.PriceMinor,
		})
	}
	return items, nil
}

func (s *Store) Gateways(ctx context.Context) ([]application.Gateway, error) {
	rows, err := s.queries.ListGateways(ctx)
	if err != nil {
		return nil, err
	}
	items := make([]application.Gateway, 0, len(rows))
	for _, row := range rows {
		items = append(items, application.Gateway{
			GatewayID: uint16(row.ProtocolID), Role: row.Role, Status: row.OperationalStatus,
		})
	}
	return items, nil
}

func (s *Store) Bands(ctx context.Context) ([]application.Band, error) {
	rows, err := s.queries.ListBands(ctx)
	if err != nil {
		return nil, err
	}
	items := make([]application.Band, 0, len(rows))
	for _, row := range rows {
		items = append(items, application.Band{
			BandID: row.BandID, ProvisionedAt: row.ProvisionedAt.Time, Balance: row.Balance,
		})
	}
	return items, nil
}

func (s *Store) AuthenticateGateway(ctx context.Context, hash []byte) (application.Actor, error) {
	row, err := s.queries.AuthenticateGateway(ctx, hash)
	if err != nil {
		return application.Actor{}, err
	}
	return application.Actor{Kind: "gateway", InternalID: row.GatewayID, ProtocolID: uint16(row.ProtocolID)}, nil
}

func (s *Store) ClaimInteraction(ctx context.Context, command application.ClaimCommand) (application.ClaimResult, error) {
	var outcome string
	var transactionID []byte
	var radioGatewayID *int32
	var leaseExpiresAt *time.Time
	err := s.pool.QueryRow(ctx, `
        SELECT outcome, transaction_protocol_id, radio_gateway_protocol_id, lease_expires_at
          FROM smartband_claim_interaction($1, $2, $3, $4, $5, $6)`,
		int64(command.InteractionID), int32(command.OperatorGatewayID),
		int32(command.AttractionID), command.TransactionProtocolID, command.ChallengeNonce,
		command.Now).Scan(&outcome, &transactionID, &radioGatewayID, &leaseExpiresAt)
	if err != nil {
		return application.ClaimResult{}, err
	}
	switch outcome {
	case "claimed":
		if radioGatewayID == nil || leaseExpiresAt == nil {
			return application.ClaimResult{}, errors.New("claim returned incomplete result")
		}
		return application.ClaimResult{
			InteractionID: command.InteractionID, RadioGatewayID: uint16(*radioGatewayID),
			LeaseExpiresAt: *leaseExpiresAt,
		}, nil
	case "not_found":
		return application.ClaimResult{}, application.ErrClaimNotFound
	case "no_radio_gateway":
		return application.ClaimResult{}, application.ErrNoRadioGateway
	case "invalid_attraction":
		return application.ClaimResult{}, application.ErrInvalidAttraction
	case "invalid_operator_gateway":
		return application.ClaimResult{}, application.ErrGatewayIdentityMismatch
	case "transaction_id_collision":
		return application.ClaimResult{}, application.ErrTransactionIDCollision
	default:
		return application.ClaimResult{}, application.ErrClaimConflict
	}
}

func (s *Store) ActiveBandKeys(ctx context.Context) ([]application.ActiveBandKey, error) {
	rows, err := s.pool.Query(ctx, `
        SELECT b.band_id::text, b.encrypted_key
          FROM bands b
          JOIN appliance_configuration ac ON ac.tenant_id = b.tenant_id
          JOIN events e ON e.site_id = ac.site_id
                       AND e.tenant_id = ac.tenant_id
                       AND e.status = 'active'
          JOIN band_assignments ba ON ba.band_id = b.band_id AND ba.status = 'active'
          JOIN operational_sessions os ON os.session_id = ba.session_id
                                      AND os.event_id = e.event_id
                                      AND os.status = 'active'
         WHERE b.status = 'assigned'
         ORDER BY b.band_id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]application.ActiveBandKey, 0)
	for rows.Next() {
		var item application.ActiveBandKey
		if err := rows.Scan(&item.BandID, &item.EncryptedKey); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (s *Store) SaveAuthenticatedSighting(ctx context.Context, value application.AuthenticatedSighting) (uint32, error) {
	bandID, err := uuid.Parse(value.BandID)
	if err != nil {
		return 0, fmt.Errorf("parse band id: %w", err)
	}
	gatewayID, err := uuid.Parse(value.GatewayInternalID)
	if err != nil {
		return 0, fmt.Errorf("parse gateway id: %w", err)
	}
	var protocolID int64
	err = s.pool.QueryRow(ctx, `
        SELECT interaction_protocol_id
          FROM smartband_record_authenticated_sighting(
            $1, $2, $3, $4, $5, $6, $7, $8, $9
          )`, gatewayID, bandID, value.SessionNonce, value.DisplayCode,
		int16(value.ProtocolVersion), int16(value.TTLSeconds), value.RSSI,
		value.GatewayObservedAt, value.ReceivedAt).Scan(&protocolID)
	if err != nil {
		var databaseError *pgconn.PgError
		if errors.As(err, &databaseError) && databaseError.Code == "23505" &&
			strings.Contains(databaseError.Message, "band already has an active interaction") {
			return 0, application.ErrBandBusy
		}
		return 0, err
	}
	return uint32(protocolID), nil
}

func (s *Store) EventsAfter(ctx context.Context, sequence int64, limit int32) ([]application.StreamEvent, error) {
	if _, err := s.pool.Exec(ctx, `SELECT smartband_expire_discovery(now())`); err != nil {
		return nil, err
	}
	rows, err := s.pool.Query(ctx, `
        SELECT stream_sequence, event_type, payload
          FROM outbox_events
         WHERE stream_sequence > $1
         ORDER BY stream_sequence
         LIMIT $2`, sequence, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]application.StreamEvent, 0)
	for rows.Next() {
		var item application.StreamEvent
		if err := rows.Scan(&item.Sequence, &item.EventType, &item.Envelope); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (s *Store) StartRadioDispatch(
	ctx context.Context,
	command application.StartRadioDispatchCommand,
) (application.RadioDispatchAttempt, error) {
	dispatchID, err := uuid.Parse(command.DispatchID)
	if err != nil {
		return application.RadioDispatchAttempt{}, fmt.Errorf("parse dispatch id: %w", err)
	}
	var result string
	var attempt *int16
	var radioGatewayID *uuid.UUID
	var status *string
	var deadline *time.Time
	err = s.pool.QueryRow(ctx, `
        SELECT result, attempt, radio_gateway_id, status, deadline
          FROM smartband_start_radio_dispatch($1, $2, $3, $4, $5, $6)`,
		command.TransactionProtocolID, dispatchID, command.ChallengeNonce,
		int32(command.ProtocolVersion), command.Payload, command.Now,
	).Scan(&result, &attempt, &radioGatewayID, &status, &deadline)
	if err != nil {
		return application.RadioDispatchAttempt{}, err
	}
	switch result {
	case "not_found":
		return application.RadioDispatchAttempt{}, application.ErrRadioDispatchNotFound
	case "not_claimed":
		return application.RadioDispatchAttempt{}, application.ErrRadioDispatchNotClaimed
	case "already_started":
		return application.RadioDispatchAttempt{}, application.ErrRadioDispatchAlreadyStarted
	case "started":
		if attempt == nil || status == nil || deadline == nil {
			return application.RadioDispatchAttempt{}, errors.New("radio dispatch start returned incomplete result")
		}
		item := application.RadioDispatchAttempt{
			DispatchID: command.DispatchID,
			Attempt:    *attempt,
			Status:     *status,
			Deadline:   *deadline,
		}
		if radioGatewayID != nil {
			item.RadioGatewayID = radioGatewayID.String()
		}
		return item, nil
	default:
		return application.RadioDispatchAttempt{}, fmt.Errorf("unknown radio dispatch start result %q", result)
	}
}

func (s *Store) DueRadioDispatches(
	ctx context.Context,
	now time.Time,
	limit int32,
) ([]application.DueRadioDispatch, error) {
	rows, err := s.pool.Query(ctx, `
        SELECT dispatch.dispatch_id::text, dispatch.transaction_id::text,
               dispatch.attempt, dispatch.challenge_nonce, dispatch.status
          FROM radio_dispatch_attempts dispatch
         WHERE (status = 'waiting_for_radio' AND selection_deadline <= $1)
            OR (status = 'pending' AND dispatch_deadline <= $1)
         ORDER BY COALESCE(selection_deadline, dispatch_deadline), created_at
         LIMIT $2`, now, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]application.DueRadioDispatch, 0)
	for rows.Next() {
		var item application.DueRadioDispatch
		if err := rows.Scan(
			&item.DispatchID, &item.TransactionID, &item.Attempt,
			&item.ChallengeNonce, &item.Status,
		); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (s *Store) AcquireRadioDispatches(
	ctx context.Context,
	workerID string,
	now time.Time,
	limit int32,
) ([]application.RadioDispatchCommand, error) {
	parsedWorkerID, err := uuid.Parse(workerID)
	if err != nil {
		return nil, fmt.Errorf("parse worker id: %w", err)
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if _, err := tx.Exec(ctx, `SELECT smartband_promote_waiting_radio($1)`, now); err != nil {
		return nil, err
	}
	rows, err := tx.Query(ctx, `
        WITH candidates AS (
            SELECT dispatch_id
              FROM radio_dispatch_attempts
             WHERE status = 'pending'
               AND dispatch_deadline > $1
               AND (work_lease_expires_at IS NULL OR work_lease_expires_at <= $1)
             ORDER BY created_at
             FOR UPDATE SKIP LOCKED
             LIMIT $3
        ), leased AS (
            UPDATE radio_dispatch_attempts dispatch
               SET worker_id = $2,
                   work_lease_expires_at = LEAST(
                       dispatch.dispatch_deadline,
                       $1::timestamptz + interval '2 seconds'
                   )
              FROM candidates
             WHERE dispatch.dispatch_id = candidates.dispatch_id
            RETURNING dispatch.*
        )
        SELECT leased.dispatch_id::text,
               transaction.interaction_id::text,
               transaction.transaction_id::text,
               leased.attempt,
               leased.radio_gateway_id::text,
               leased.challenge_nonce,
               leased.protocol_version,
               leased.payload,
               leased.dispatch_deadline
          FROM leased
          JOIN transaction_intents transaction USING (transaction_id)
         ORDER BY leased.created_at`, now, parsedWorkerID, limit)
	if err != nil {
		return nil, err
	}
	items := make([]application.RadioDispatchCommand, 0)
	for rows.Next() {
		var item application.RadioDispatchCommand
		var protocolVersion int32
		if err := rows.Scan(
			&item.DispatchID, &item.InteractionID, &item.TransactionID,
			&item.Attempt, &item.RadioGatewayID, &item.ChallengeNonce,
			&protocolVersion, &item.Payload, &item.Deadline,
		); err != nil {
			rows.Close()
			return nil, err
		}
		item.ProtocolVersion = uint16(protocolVersion)
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return nil, err
	}
	rows.Close()
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return items, nil
}

func (s *Store) FinishRadioDispatch(
	ctx context.Context,
	command application.FinishRadioDispatchCommand,
) (application.FinishRadioDispatchResult, error) {
	dispatchID, err := uuid.Parse(command.DispatchID)
	if err != nil {
		return application.FinishRadioDispatchResult{}, fmt.Errorf("parse dispatch id: %w", err)
	}
	transactionID, err := uuid.Parse(command.TransactionID)
	if err != nil {
		return application.FinishRadioDispatchResult{}, fmt.Errorf("parse transaction id: %w", err)
	}
	nextDispatchID, err := uuid.Parse(command.NextDispatchID)
	if err != nil {
		return application.FinishRadioDispatchResult{}, fmt.Errorf("parse next dispatch id: %w", err)
	}
	var workerID any
	if command.WorkerID != "" {
		parsedWorkerID, parseErr := uuid.Parse(command.WorkerID)
		if parseErr != nil {
			return application.FinishRadioDispatchResult{}, fmt.Errorf("parse worker id: %w", parseErr)
		}
		workerID = parsedWorkerID
	}
	var result application.FinishRadioDispatchResult
	var nextStatus *string
	var returnedNextDispatchID *uuid.UUID
	err = s.pool.QueryRow(ctx, `
        SELECT result, next_status, next_dispatch_id
          FROM smartband_finish_radio_dispatch(
            $1, $2, $3, $4, $5, $6, $7, $8, $9, $10
          )`,
		dispatchID, transactionID, command.Attempt, command.ChallengeNonce, workerID,
		command.Outcome, nullableText(command.FailureKind), command.Now,
		nextDispatchID, command.NextChallengeNonce,
	).Scan(&result.Classification, &nextStatus, &returnedNextDispatchID)
	if err != nil {
		return application.FinishRadioDispatchResult{}, err
	}
	if nextStatus != nil {
		result.NextStatus = *nextStatus
	}
	if returnedNextDispatchID != nil {
		result.NextDispatchID = returnedNextDispatchID.String()
	}
	return result, nil
}

func nullableText(value string) any {
	if value == "" {
		return nil
	}
	return value
}
