package application

import (
	"context"
	"time"
)

type ApplianceContext struct {
	TenantID      string `json:"tenant_id"`
	TenantCode    string `json:"tenant_code"`
	TenantName    string `json:"tenant_name"`
	SiteID        string `json:"site_id"`
	SiteCode      string `json:"site_code"`
	SiteName      string `json:"site_name"`
	Timezone      string `json:"timezone"`
	ApplianceName string `json:"appliance_name"`
	EventID       string `json:"event_id,omitempty"`
	EventCode     string `json:"event_code,omitempty"`
	EventName     string `json:"event_name,omitempty"`
}

type QueueEntry struct {
	InteractionID uint32    `json:"interaction_id"`
	DisplayCode   string    `json:"display_code"`
	Status        string    `json:"status"`
	CollidesWith  []uint32  `json:"collides_with,omitempty"`
	QueuedAt      time.Time `json:"queued_at"`
}

type Attraction struct {
	AttractionID uint16 `json:"attraction_id"`
	Name         string `json:"name"`
	DefaultCost  int64  `json:"default_cost"`
}

type Gateway struct {
	GatewayID uint16 `json:"gateway_id"`
	Role      string `json:"role"`
	Status    string `json:"status"`
}

type Band struct {
	BandID        string    `json:"band_id"`
	ProvisionedAt time.Time `json:"provisioned_at"`
	Balance       int64     `json:"balance"`
}

type Actor struct {
	Kind       string
	InternalID string
	ProtocolID uint16
	Label      string
}

type Store interface {
	Ping(context.Context) error
	Appliance(context.Context) (ApplianceContext, error)
	Queue(context.Context) ([]QueueEntry, error)
	Attractions(context.Context) ([]Attraction, error)
	Gateways(context.Context) ([]Gateway, error)
	Bands(context.Context) ([]Band, error)
	AuthenticateGateway(context.Context, []byte) (Actor, error)
	AuthenticateOperator(context.Context, []byte) (Actor, error)
}
