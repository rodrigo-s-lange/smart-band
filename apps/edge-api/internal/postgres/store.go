package postgres

import (
	"context"

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
