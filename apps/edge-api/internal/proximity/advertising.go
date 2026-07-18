package proximity

import (
	"crypto/aes"
	"crypto/subtle"
	"encoding/binary"
	"errors"
	"fmt"
)

const (
	AdvertisingLength = 22
	ProtocolVersion   = 1
	RequestTTLSeconds = 60
	advertisingDomain = 0x01
)

var crockfordAlphabet = []byte("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

type Advertising struct {
	ProtocolVersion uint8
	SessionNonce    [8]byte
	Tag             [8]byte
	DisplayCodeRaw  uint32
	DisplayCode     string
	TTLSeconds      uint8
}

func ParseAdvertising(payload []byte) (Advertising, error) {
	if len(payload) != AdvertisingLength {
		return Advertising{}, fmt.Errorf("advertising payload must contain %d bytes", AdvertisingLength)
	}
	var value Advertising
	value.ProtocolVersion = payload[0]
	copy(value.SessionNonce[:], payload[1:9])
	copy(value.Tag[:], payload[9:17])
	value.DisplayCodeRaw = binary.LittleEndian.Uint32(payload[17:21])
	value.TTLSeconds = payload[21]
	if value.ProtocolVersion != ProtocolVersion {
		return Advertising{}, errors.New("unsupported advertising protocol version")
	}
	if value.TTLSeconds != RequestTTLSeconds {
		return Advertising{}, errors.New("unsupported advertising ttl")
	}
	displayCode, err := EncodeDisplayCode(value.DisplayCodeRaw)
	if err != nil {
		return Advertising{}, err
	}
	value.DisplayCode = displayCode
	return value, nil
}

func EncodeDisplayCode(value uint32) (string, error) {
	if value >= 1<<30 {
		return "", errors.New("display code uses reserved upper bits")
	}
	encoded := [7]byte{0, 0, 0, '-', 0, 0, 0}
	for index := len(encoded) - 1; index >= 0; index-- {
		if index == 3 {
			continue
		}
		encoded[index] = crockfordAlphabet[value&31]
		value >>= 5
	}
	return string(encoded[:]), nil
}

func AuthenticateAdvertising(key []byte, value Advertising) (bool, error) {
	if len(key) != 16 {
		return false, errors.New("band key must contain 16 bytes")
	}
	message := make([]byte, 0, 16)
	message = append(message, advertisingDomain, value.ProtocolVersion)
	message = append(message, value.SessionNonce[:]...)
	var code [4]byte
	icon := value.DisplayCodeRaw
	binary.LittleEndian.PutUint32(code[:], icon)
	message = append(message, code[:]...)
	message = append(message, value.TTLSeconds)
	fullTag, err := AESCMAC(key, message)
	if err != nil {
		return false, err
	}
	return subtle.ConstantTimeCompare(value.Tag[:], fullTag[:8]) == 1, nil
}

func AESCMAC(key, message []byte) ([16]byte, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return [16]byte{}, err
	}
	var zero, l [16]byte
	block.Encrypt(l[:], zero[:])
	k1 := cmacSubkey(l)
	k2 := cmacSubkey(k1)

	blockCount := (len(message) + 15) / 16
	complete := len(message) > 0 && len(message)%16 == 0
	if blockCount == 0 {
		blockCount = 1
	}
	var last [16]byte
	if complete {
		copy(last[:], message[(blockCount-1)*16:])
		xorBlock(&last, k1)
	} else {
		remainder := message[(blockCount-1)*16:]
		copy(last[:], remainder)
		last[len(remainder)] = 0x80
		xorBlock(&last, k2)
	}

	var state, input [16]byte
	for index := 0; index < blockCount-1; index++ {
		copy(input[:], message[index*16:(index+1)*16])
		xorBlock(&input, state)
		block.Encrypt(state[:], input[:])
	}
	xorBlock(&last, state)
	block.Encrypt(state[:], last[:])
	return state, nil
}

func cmacSubkey(input [16]byte) [16]byte {
	var output [16]byte
	carry := byte(0)
	for index := len(input) - 1; index >= 0; index-- {
		nextCarry := input[index] >> 7
		output[index] = input[index]<<1 | carry
		carry = nextCarry
	}
	if input[0]&0x80 != 0 {
		output[15] ^= 0x87
	}
	return output
}

func xorBlock(destination *[16]byte, source [16]byte) {
	for index := range destination {
		destination[index] ^= source[index]
	}
}
