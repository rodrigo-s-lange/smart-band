package postgres

import (
	"context"
	"errors"
	"fmt"
	"strings"

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

func (s *Store) AuthenticateOperator(ctx context.Context, hash []byte) (application.Actor, error) {
	row, err := s.queries.AuthenticateOperator(ctx, hash)
	if err != nil {
		return application.Actor{}, err
	}
	return application.Actor{Kind: "operator", InternalID: row.OperatorID, Label: row.DisplayName}, nil
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
