package application

import (
	"context"
	"errors"
	"fmt"

	"github.com/rodrigo-s-lange/smart-band/apps/edge-api/internal/proximity"
)

var (
	ErrGatewayIdentityMismatch = errors.New("gateway identity does not match sighting")
	ErrBandKeyCollision        = errors.New("advertising authenticates with more than one band key")
	ErrBandBusy                = errors.New("band already has an active interaction")
)

type Service struct {
	repository Repository
	keys       BandKeyDecryptor
}

func NewService(repository Repository, keys BandKeyDecryptor) *Service {
	return &Service{repository: repository, keys: keys}
}

func (s *Service) Ping(ctx context.Context) error { return s.repository.Ping(ctx) }
func (s *Service) Appliance(ctx context.Context) (ApplianceContext, error) {
	return s.repository.Appliance(ctx)
}
func (s *Service) Queue(ctx context.Context) ([]QueueEntry, error) {
	return s.repository.Queue(ctx)
}
func (s *Service) Attractions(ctx context.Context) ([]Attraction, error) {
	return s.repository.Attractions(ctx)
}
func (s *Service) Gateways(ctx context.Context) ([]Gateway, error) {
	return s.repository.Gateways(ctx)
}
func (s *Service) Bands(ctx context.Context) ([]Band, error) {
	return s.repository.Bands(ctx)
}
func (s *Service) AuthenticateGateway(ctx context.Context, hash []byte) (Actor, error) {
	return s.repository.AuthenticateGateway(ctx, hash)
}
func (s *Service) AuthenticateOperator(ctx context.Context, hash []byte) (Actor, error) {
	return s.repository.AuthenticateOperator(ctx, hash)
}
func (s *Service) EventsAfter(ctx context.Context, sequence int64, limit int32) ([]StreamEvent, error) {
	return s.repository.EventsAfter(ctx, sequence, limit)
}

func (s *Service) ReportSighting(ctx context.Context, actor Actor, report SightingReport) (SightingResult, error) {
	if actor.Kind != "gateway" || actor.ProtocolID != report.GatewayID {
		return SightingResult{}, ErrGatewayIdentityMismatch
	}
	advertising, err := proximity.ParseAdvertising(report.RawPayload)
	if err != nil {
		return SightingResult{Resolved: false}, nil
	}
	candidates, err := s.repository.ActiveBandKeys(ctx)
	if err != nil {
		return SightingResult{}, err
	}
	var resolvedBand string
	matches := 0
	for _, candidate := range candidates {
		bandKey, decryptErr := s.keys.Decrypt(candidate.BandID, candidate.EncryptedKey)
		if decryptErr != nil {
			continue
		}
		authenticated, authErr := proximity.AuthenticateAdvertising(bandKey, advertising)
		for index := range bandKey {
			bandKey[index] = 0
		}
		if authErr != nil {
			return SightingResult{}, fmt.Errorf("authenticate advertising: %w", authErr)
		}
		if authenticated {
			resolvedBand = candidate.BandID
			matches++
		}
	}
	if matches == 0 {
		return SightingResult{Resolved: false}, nil
	}
	if matches > 1 {
		return SightingResult{}, ErrBandKeyCollision
	}
	interactionID, err := s.repository.SaveAuthenticatedSighting(ctx, AuthenticatedSighting{
		BandID: resolvedBand, GatewayInternalID: actor.InternalID,
		ProtocolVersion: advertising.ProtocolVersion,
		SessionNonce:    append([]byte(nil), advertising.SessionNonce[:]...),
		DisplayCode:     advertising.DisplayCode, TTLSeconds: advertising.TTLSeconds,
		RSSI: report.RSSI, GatewayObservedAt: report.GatewayObservedAt,
		ReceivedAt: report.ReceivedAt,
	})
	if err != nil {
		return SightingResult{}, err
	}
	return SightingResult{Resolved: true, InteractionID: &interactionID}, nil
}
