package radiosim

import (
	"context"
	"errors"
	"sync"

	"github.com/rodrigo-s-lange/smart-band/apps/edge-api/internal/application"
)

type Behavior struct {
	FailureKind        string
	WaitForDeadline    bool
	FullWriteConfirmed bool
}

type Transport struct {
	mu        sync.Mutex
	behaviors []Behavior
	results   map[string]application.RadioDispatchResult
	calls     []application.RadioDispatchCommand
}

func New(behaviors ...Behavior) *Transport {
	return &Transport{
		behaviors: append([]Behavior(nil), behaviors...),
		results:   make(map[string]application.RadioDispatchResult),
	}
}

func (transport *Transport) Dispatch(
	ctx context.Context,
	command application.RadioDispatchCommand,
) (application.RadioDispatchResult, error) {
	transport.mu.Lock()
	if result, ok := transport.results[command.DispatchID]; ok {
		transport.mu.Unlock()
		return cloneResult(result), nil
	}
	index := len(transport.calls)
	transport.calls = append(transport.calls, cloneCommand(command))
	behavior := Behavior{FailureKind: application.FailureGatewayOffline}
	if index < len(transport.behaviors) {
		behavior = transport.behaviors[index]
	}
	transport.mu.Unlock()

	result := application.RadioDispatchResult{
		DispatchID:     command.DispatchID,
		TransactionID:  command.TransactionID,
		Attempt:        command.Attempt,
		ChallengeNonce: append([]byte(nil), command.ChallengeNonce...),
	}
	if behavior.WaitForDeadline {
		<-ctx.Done()
		result.Outcome = application.RadioTimedOut
	} else if behavior.FailureKind != "" {
		result.Outcome = application.RadioFailed
		result.FailureKind = behavior.FailureKind
	} else if behavior.FullWriteConfirmed {
		result.Outcome = application.RadioDelivered
	} else {
		result.Outcome = application.RadioFailed
		result.FailureKind = application.FailureWriteNotConfirmed
	}

	transport.mu.Lock()
	transport.results[command.DispatchID] = cloneResult(result)
	transport.mu.Unlock()
	return result, nil
}

func (transport *Transport) Calls() []application.RadioDispatchCommand {
	transport.mu.Lock()
	defer transport.mu.Unlock()
	items := make([]application.RadioDispatchCommand, len(transport.calls))
	for index, call := range transport.calls {
		items[index] = cloneCommand(call)
	}
	return items
}

func (transport *Transport) Result(dispatchID string) (application.RadioDispatchResult, error) {
	transport.mu.Lock()
	defer transport.mu.Unlock()
	result, ok := transport.results[dispatchID]
	if !ok {
		return application.RadioDispatchResult{}, errors.New("dispatch was not simulated")
	}
	return cloneResult(result), nil
}

func cloneCommand(command application.RadioDispatchCommand) application.RadioDispatchCommand {
	command.ChallengeNonce = append([]byte(nil), command.ChallengeNonce...)
	command.Payload = append([]byte(nil), command.Payload...)
	return command
}

func cloneResult(result application.RadioDispatchResult) application.RadioDispatchResult {
	result.ChallengeNonce = append([]byte(nil), result.ChallengeNonce...)
	return result
}
