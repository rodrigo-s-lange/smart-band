package application

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"time"

	"github.com/google/uuid"
)

const (
	RadioWaitingForRadio = "waiting_for_radio"
	RadioPending         = "pending"
	RadioDelivered       = "delivered"
	RadioFailed          = "failed"
	RadioTimedOut        = "timed_out"
)

const (
	FailureGatewayOffline    = "gateway_offline"
	FailureConnectFailed     = "connect_failed"
	FailureWriteNotConfirmed = "write_not_confirmed"
	FailureTransportError    = "transport_error"
	FailureNoRadioGateway    = "no_radio_gateway"
)

var (
	ErrRadioDispatchNotFound       = errors.New("radio dispatch transaction not found")
	ErrRadioDispatchAlreadyStarted = errors.New("radio dispatch already started")
	ErrRadioDispatchNotClaimed     = errors.New("transaction is not claimed")
	ErrInvalidRadioResult          = errors.New("invalid radio dispatch result")
)

type StartRadioDispatchCommand struct {
	TransactionProtocolID []byte
	DispatchID            string
	ChallengeNonce        []byte
	ProtocolVersion       uint16
	Payload               []byte
	Now                   time.Time
}

type RadioDispatchAttempt struct {
	DispatchID     string
	Attempt        int16
	RadioGatewayID string
	Status         string
	Deadline       time.Time
}

type RadioDispatchCommand struct {
	DispatchID      string
	InteractionID   string
	TransactionID   string
	Attempt         int16
	RadioGatewayID  string
	ChallengeNonce  []byte
	ProtocolVersion uint16
	Payload         []byte
	Deadline        time.Time
}

type DueRadioDispatch struct {
	DispatchID     string
	TransactionID  string
	Attempt        int16
	ChallengeNonce []byte
	Status         string
}

type RadioDispatchResult struct {
	DispatchID     string
	TransactionID  string
	Attempt        int16
	ChallengeNonce []byte
	Outcome        string
	FailureKind    string
}

type FinishRadioDispatchCommand struct {
	RadioDispatchResult
	WorkerID           string
	Now                time.Time
	NextDispatchID     string
	NextChallengeNonce []byte
}

type FinishRadioDispatchResult struct {
	Classification string
	NextStatus     string
	NextDispatchID string
}

type RadioRepository interface {
	StartRadioDispatch(context.Context, StartRadioDispatchCommand) (RadioDispatchAttempt, error)
	DueRadioDispatches(context.Context, time.Time, int32) ([]DueRadioDispatch, error)
	AcquireRadioDispatches(context.Context, string, time.Time, int32) ([]RadioDispatchCommand, error)
	FinishRadioDispatch(context.Context, FinishRadioDispatchCommand) (FinishRadioDispatchResult, error)
}

type RadioTransport interface {
	Dispatch(context.Context, RadioDispatchCommand) (RadioDispatchResult, error)
}

func (s *Service) StartRadioDispatch(
	ctx context.Context,
	transactionID string,
	protocolVersion uint16,
	payload []byte,
) (RadioDispatchAttempt, error) {
	repository, ok := s.repository.(RadioRepository)
	if !ok {
		return RadioDispatchAttempt{}, errors.New("repository does not implement radio dispatch")
	}
	transactionProtocolID, err := hex.DecodeString(transactionID)
	if err != nil || len(transactionProtocolID) != 8 {
		return RadioDispatchAttempt{}, fmt.Errorf("invalid transaction id")
	}
	dispatchID, nonce, err := newRadioIdentity(s.random)
	if err != nil {
		return RadioDispatchAttempt{}, err
	}
	return repository.StartRadioDispatch(ctx, StartRadioDispatchCommand{
		TransactionProtocolID: transactionProtocolID,
		DispatchID:            dispatchID,
		ChallengeNonce:        nonce,
		ProtocolVersion:       protocolVersion,
		Payload:               append([]byte(nil), payload...),
		Now:                   s.clock().UTC(),
	})
}

type RadioWorker struct {
	repository RadioRepository
	transport  RadioTransport
	random     io.Reader
	clock      func() time.Time
	workerID   string
	batchSize  int32
}

type RadioWorkerOption func(*RadioWorker)

func WithRadioWorkerRandom(reader io.Reader) RadioWorkerOption {
	return func(worker *RadioWorker) { worker.random = reader }
}

func WithRadioWorkerClock(clock func() time.Time) RadioWorkerOption {
	return func(worker *RadioWorker) { worker.clock = clock }
}

func WithRadioWorkerID(workerID string) RadioWorkerOption {
	return func(worker *RadioWorker) { worker.workerID = workerID }
}

func NewRadioWorker(repository RadioRepository, transport RadioTransport, options ...RadioWorkerOption) (*RadioWorker, error) {
	worker := &RadioWorker{
		repository: repository,
		transport:  transport,
		random:     rand.Reader,
		clock:      time.Now,
		batchSize:  32,
	}
	for _, option := range options {
		option(worker)
	}
	if worker.random == nil {
		return nil, errors.New("radio worker random source is nil")
	}
	if worker.workerID == "" {
		workerID, err := uuid.NewRandomFromReader(worker.random)
		if err != nil {
			return nil, fmt.Errorf("generate radio worker id: %w", err)
		}
		worker.workerID = workerID.String()
	}
	if _, err := uuid.Parse(worker.workerID); err != nil {
		return nil, fmt.Errorf("parse radio worker id: %w", err)
	}
	return worker, nil
}

func (w *RadioWorker) RunOnce(ctx context.Context) error {
	now := w.clock().UTC()
	due, err := w.repository.DueRadioDispatches(ctx, now, w.batchSize)
	if err != nil {
		return fmt.Errorf("list due radio dispatches: %w", err)
	}
	for _, item := range due {
		outcome := RadioTimedOut
		failureKind := ""
		if item.Status == RadioWaitingForRadio {
			outcome = RadioFailed
			failureKind = FailureNoRadioGateway
		}
		if _, err := w.finish(ctx, RadioDispatchResult{
			DispatchID:     item.DispatchID,
			TransactionID:  item.TransactionID,
			Attempt:        item.Attempt,
			ChallengeNonce: item.ChallengeNonce,
			Outcome:        outcome,
			FailureKind:    failureKind,
		}, "", now); err != nil {
			return err
		}
	}

	commands, err := w.repository.AcquireRadioDispatches(ctx, w.workerID, now, w.batchSize)
	if err != nil {
		return fmt.Errorf("acquire radio dispatches: %w", err)
	}
	for _, command := range commands {
		result, dispatchErr := w.dispatch(ctx, command)
		if dispatchErr != nil {
			result = expectedRadioResult(command)
			result.Outcome = RadioFailed
			result.FailureKind = FailureTransportError
		}
		if !resultMatchesCommand(result, command) || !validTransportOutcome(result) {
			result = expectedRadioResult(command)
			result.Outcome = RadioFailed
			result.FailureKind = FailureTransportError
		}
		if _, err := w.finish(ctx, result, w.workerID, w.clock().UTC()); err != nil {
			return err
		}
	}
	return nil
}

func (w *RadioWorker) Run(ctx context.Context, pollInterval time.Duration) error {
	if pollInterval <= 0 {
		return errors.New("radio worker poll interval must be positive")
	}
	ticker := time.NewTicker(pollInterval)
	defer ticker.Stop()
	for {
		if err := w.RunOnce(ctx); err != nil {
			return err
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
		}
	}
}

func (w *RadioWorker) dispatch(ctx context.Context, command RadioDispatchCommand) (RadioDispatchResult, error) {
	dispatchContext, cancel := context.WithDeadline(ctx, command.Deadline)
	defer cancel()
	return w.transport.Dispatch(dispatchContext, command)
}

func (w *RadioWorker) finish(
	ctx context.Context,
	result RadioDispatchResult,
	workerID string,
	now time.Time,
) (FinishRadioDispatchResult, error) {
	nextDispatchID, nextNonce, err := newRadioIdentity(w.random)
	if err != nil {
		return FinishRadioDispatchResult{}, err
	}
	finished, err := w.repository.FinishRadioDispatch(ctx, FinishRadioDispatchCommand{
		RadioDispatchResult: result,
		WorkerID:            workerID,
		Now:                 now,
		NextDispatchID:      nextDispatchID,
		NextChallengeNonce:  nextNonce,
	})
	if err != nil {
		return FinishRadioDispatchResult{}, fmt.Errorf("finish radio dispatch: %w", err)
	}
	return finished, nil
}

func newRadioIdentity(reader io.Reader) (string, []byte, error) {
	dispatchID, err := uuid.NewRandomFromReader(reader)
	if err != nil {
		return "", nil, fmt.Errorf("generate dispatch id: %w", err)
	}
	nonce := make([]byte, 8)
	if _, err := io.ReadFull(reader, nonce); err != nil {
		return "", nil, fmt.Errorf("generate challenge nonce: %w", err)
	}
	return dispatchID.String(), nonce, nil
}

func expectedRadioResult(command RadioDispatchCommand) RadioDispatchResult {
	return RadioDispatchResult{
		DispatchID:     command.DispatchID,
		TransactionID:  command.TransactionID,
		Attempt:        command.Attempt,
		ChallengeNonce: append([]byte(nil), command.ChallengeNonce...),
	}
}

func resultMatchesCommand(result RadioDispatchResult, command RadioDispatchCommand) bool {
	return result.DispatchID == command.DispatchID &&
		result.TransactionID == command.TransactionID &&
		result.Attempt == command.Attempt &&
		hex.EncodeToString(result.ChallengeNonce) == hex.EncodeToString(command.ChallengeNonce)
}

func validTransportOutcome(result RadioDispatchResult) bool {
	switch result.Outcome {
	case RadioDelivered, RadioTimedOut:
		return result.FailureKind == ""
	case RadioFailed:
		switch result.FailureKind {
		case FailureGatewayOffline, FailureConnectFailed, FailureWriteNotConfirmed, FailureTransportError:
			return true
		}
	}
	return false
}
