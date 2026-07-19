package application

import (
	"context"
	"errors"
	"testing"
	"time"
)

type radioRepositoryStub struct {
	due      []DueRadioDispatch
	commands []RadioDispatchCommand
	finished []FinishRadioDispatchCommand
}

func (stub *radioRepositoryStub) StartRadioDispatch(context.Context, StartRadioDispatchCommand) (RadioDispatchAttempt, error) {
	return RadioDispatchAttempt{}, errors.New("not used")
}

func (stub *radioRepositoryStub) DueRadioDispatches(context.Context, time.Time, int32) ([]DueRadioDispatch, error) {
	return append([]DueRadioDispatch(nil), stub.due...), nil
}

func (stub *radioRepositoryStub) AcquireRadioDispatches(context.Context, string, time.Time, int32) ([]RadioDispatchCommand, error) {
	return append([]RadioDispatchCommand(nil), stub.commands...), nil
}

func (stub *radioRepositoryStub) FinishRadioDispatch(_ context.Context, command FinishRadioDispatchCommand) (FinishRadioDispatchResult, error) {
	stub.finished = append(stub.finished, command)
	return FinishRadioDispatchResult{Classification: "accepted"}, nil
}

type radioTransportStub struct {
	called int
	result RadioDispatchResult
	err    error
}

func (stub *radioTransportStub) Dispatch(context.Context, RadioDispatchCommand) (RadioDispatchResult, error) {
	stub.called++
	return stub.result, stub.err
}

func TestRadioWorkerNeverPerformsIOWhileWaitingForRadio(t *testing.T) {
	now := time.Date(2026, 7, 18, 20, 0, 0, 0, time.UTC)
	repository := &radioRepositoryStub{due: []DueRadioDispatch{{
		DispatchID:     "11111111-1111-4111-8111-111111111111",
		TransactionID:  "33333333-3333-4333-8333-333333333333",
		Attempt:        1,
		ChallengeNonce: []byte("12345678"),
		Status:         RadioWaitingForRadio,
	}}}
	transport := &radioTransportStub{}
	worker, err := NewRadioWorker(
		repository,
		transport,
		WithRadioWorkerID("22222222-2222-4222-8222-222222222222"),
		WithRadioWorkerClock(func() time.Time { return now }),
	)
	if err != nil {
		t.Fatal(err)
	}
	if err := worker.RunOnce(context.Background()); err != nil {
		t.Fatal(err)
	}
	if transport.called != 0 {
		t.Fatalf("transport called %d times while waiting", transport.called)
	}
	if len(repository.finished) != 1 || repository.finished[0].FailureKind != FailureNoRadioGateway {
		t.Fatalf("unexpected finish: %+v", repository.finished)
	}
}

func TestRadioWorkerRejectsMismatchedTransportCorrelation(t *testing.T) {
	now := time.Date(2026, 7, 18, 20, 0, 0, 0, time.UTC)
	command := RadioDispatchCommand{
		DispatchID:     "11111111-1111-4111-8111-111111111111",
		TransactionID:  "33333333-3333-4333-8333-333333333333",
		Attempt:        1,
		ChallengeNonce: []byte("12345678"),
		Deadline:       now.Add(10 * time.Second),
	}
	repository := &radioRepositoryStub{commands: []RadioDispatchCommand{command}}
	transport := &radioTransportStub{result: RadioDispatchResult{
		DispatchID:     "44444444-4444-4444-8444-444444444444",
		TransactionID:  command.TransactionID,
		Attempt:        1,
		ChallengeNonce: command.ChallengeNonce,
		Outcome:        RadioDelivered,
	}}
	worker, err := NewRadioWorker(
		repository,
		transport,
		WithRadioWorkerID("22222222-2222-4222-8222-222222222222"),
		WithRadioWorkerClock(func() time.Time { return now }),
	)
	if err != nil {
		t.Fatal(err)
	}
	if err := worker.RunOnce(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(repository.finished) != 1 || repository.finished[0].Outcome != RadioFailed ||
		repository.finished[0].FailureKind != FailureTransportError ||
		repository.finished[0].DispatchID != command.DispatchID {
		t.Fatalf("mismatched result was not fenced: %+v", repository.finished)
	}
}
