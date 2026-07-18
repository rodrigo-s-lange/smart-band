package application

import (
	"context"
	"encoding/json"
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
	Kind              string
	InternalID        string
	ProtocolID        uint16
	GatewayInternalID string
	Label             string
}

type ClaimRequest struct {
	InteractionID     uint32
	OperatorGatewayID uint16
	AttractionID      uint16
}

type ClaimCommand struct {
	InteractionID         uint32
	OperatorID            string
	OperatorGatewayID     uint16
	AttractionID          uint16
	TransactionProtocolID []byte
	ChallengeNonce        []byte
	Now                   time.Time
}

type ClaimResult struct {
	TransactionID  string    `json:"transaction_id"`
	InteractionID  uint32    `json:"interaction_id"`
	RadioGatewayID uint16    `json:"radio_gateway_id"`
	LeaseExpiresAt time.Time `json:"lease_expires_at"`
}

type SightingReport struct {
	GatewayID         uint16
	RSSI              int16
	GatewayObservedAt time.Time
	ReceivedAt        time.Time
	RawPayload        []byte
}

type SightingResult struct {
	Resolved      bool    `json:"resolved"`
	InteractionID *uint32 `json:"interaction_id,omitempty"`
}

type ActiveBandKey struct {
	BandID       string
	EncryptedKey []byte
}

type AuthenticatedSighting struct {
	BandID            string
	GatewayInternalID string
	ProtocolVersion   uint8
	SessionNonce      []byte
	DisplayCode       string
	TTLSeconds        uint8
	RSSI              int16
	GatewayObservedAt time.Time
	ReceivedAt        time.Time
}

type StreamEvent struct {
	Sequence  int64
	EventType string
	Envelope  json.RawMessage
}

type BandKeyDecryptor interface {
	Decrypt(string, []byte) ([]byte, error)
}

type Repository interface {
	Ping(context.Context) error
	Appliance(context.Context) (ApplianceContext, error)
	Queue(context.Context) ([]QueueEntry, error)
	Attractions(context.Context) ([]Attraction, error)
	Gateways(context.Context) ([]Gateway, error)
	Bands(context.Context) ([]Band, error)
	AuthenticateGateway(context.Context, []byte) (Actor, error)
	AuthenticateOperator(context.Context, []byte) (Actor, error)
	ActiveBandKeys(context.Context) ([]ActiveBandKey, error)
	SaveAuthenticatedSighting(context.Context, AuthenticatedSighting) (uint32, error)
	ClaimInteraction(context.Context, ClaimCommand) (ClaimResult, error)
	EventsAfter(context.Context, int64, int32) ([]StreamEvent, error)
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
	ReportSighting(context.Context, Actor, SightingReport) (SightingResult, error)
	ClaimInteraction(context.Context, Actor, ClaimRequest) (ClaimResult, error)
	EventsAfter(context.Context, int64, int32) ([]StreamEvent, error)
}
