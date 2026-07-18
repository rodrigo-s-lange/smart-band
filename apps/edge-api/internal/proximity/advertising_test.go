package proximity

import (
	"encoding/hex"
	"testing"
)

func TestAdvertisingContractVector(t *testing.T) {
	key := mustDecodeHex(t, "2b7e151628aed2a6abf7158809cf4f3c")
	payload := mustDecodeHex(t, "0101020304050607085317788fcfee63d0785634123c")
	value, err := ParseAdvertising(payload)
	if err != nil {
		t.Fatal(err)
	}
	if value.DisplayCode != "938-NKR" {
		t.Fatalf("display code = %q", value.DisplayCode)
	}
	ok, err := AuthenticateAdvertising(key, value)
	if err != nil || !ok {
		t.Fatalf("authenticated=%v err=%v", ok, err)
	}
	payload[17]++
	tampered, err := ParseAdvertising(payload)
	if err != nil {
		t.Fatal(err)
	}
	ok, err = AuthenticateAdvertising(key, tampered)
	if err != nil || ok {
		t.Fatalf("tampered authenticated=%v err=%v", ok, err)
	}
}

func TestAESCMACRFC4493(t *testing.T) {
	key := mustDecodeHex(t, "2b7e151628aed2a6abf7158809cf4f3c")
	message := mustDecodeHex(t, "6bc1bee22e409f96e93d7e117393172a")
	actual, err := AESCMAC(key, message)
	if err != nil {
		t.Fatal(err)
	}
	if hex.EncodeToString(actual[:]) != "070a16b46b4d4144f79bdd9dd04a287c" {
		t.Fatalf("cmac = %x", actual)
	}
}

func TestAdvertisingRejectsReservedDisplayBits(t *testing.T) {
	payload := make([]byte, AdvertisingLength)
	payload[0] = ProtocolVersion
	payload[20] = 0x40
	payload[21] = RequestTTLSeconds
	if _, err := ParseAdvertising(payload); err == nil {
		t.Fatal("expected reserved display bits to be rejected")
	}
}

func mustDecodeHex(t *testing.T, value string) []byte {
	t.Helper()
	decoded, err := hex.DecodeString(value)
	if err != nil {
		t.Fatal(err)
	}
	return decoded
}
