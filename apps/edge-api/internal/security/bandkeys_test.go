package security

import (
	"bytes"
	"testing"
)

func TestBandKeyEnvelopeIsBoundToBand(t *testing.T) {
	box, err := NewBandKeyBox(bytes.Repeat([]byte{0x42}, 32))
	if err != nil {
		t.Fatal(err)
	}
	key := bytes.Repeat([]byte{0x24}, 16)
	envelope, err := box.Encrypt("band-one", key)
	if err != nil {
		t.Fatal(err)
	}
	decrypted, err := box.Decrypt("band-one", envelope)
	if err != nil || !bytes.Equal(decrypted, key) {
		t.Fatalf("decrypted=%x err=%v", decrypted, err)
	}
	if _, err := box.Decrypt("band-two", envelope); err == nil {
		t.Fatal("expected AAD binding to reject another band")
	}
}
