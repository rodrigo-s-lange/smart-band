package radiosim

import (
	"context"
	"testing"
	"time"

	"github.com/rodrigo-s-lange/smart-band/apps/edge-api/internal/application"
)

func TestTransportRequiresFullWriteAndIsIdempotent(t *testing.T) {
	transport := New(Behavior{FullWriteConfirmed: false})
	command := application.RadioDispatchCommand{
		DispatchID:      "11111111-1111-4111-8111-111111111111",
		TransactionID:   "22222222-2222-4222-8222-222222222222",
		Attempt:         1,
		ChallengeNonce:  []byte("12345678"),
		ProtocolVersion: 9,
		Payload:         []byte{0xde, 0xad, 0xbe, 0xef},
		Deadline:        time.Now().Add(time.Second),
	}
	first, err := transport.Dispatch(context.Background(), command)
	if err != nil {
		t.Fatal(err)
	}
	if first.Outcome != application.RadioFailed || first.FailureKind != application.FailureWriteNotConfirmed {
		t.Fatalf("unexpected result: %+v", first)
	}
	second, err := transport.Dispatch(context.Background(), command)
	if err != nil {
		t.Fatal(err)
	}
	if second.Outcome != first.Outcome || len(transport.Calls()) != 1 {
		t.Fatalf("repeat was not idempotent: first=%+v second=%+v calls=%d", first, second, len(transport.Calls()))
	}
	if got := transport.Calls()[0]; got.ProtocolVersion != 9 || string(got.Payload) != string(command.Payload) {
		t.Fatalf("opaque command changed: %+v", got)
	}
}

func TestTransportOnlyDeliversAfterFullWriteConfirmation(t *testing.T) {
	transport := New(Behavior{FullWriteConfirmed: true})
	command := application.RadioDispatchCommand{
		DispatchID:     "11111111-1111-4111-8111-111111111112",
		TransactionID:  "22222222-2222-4222-8222-222222222223",
		Attempt:        1,
		ChallengeNonce: []byte("abcdefgh"),
		Deadline:       time.Now().Add(time.Second),
	}
	result, err := transport.Dispatch(context.Background(), command)
	if err != nil {
		t.Fatal(err)
	}
	if result.Outcome != application.RadioDelivered {
		t.Fatalf("unexpected result: %+v", result)
	}
}
