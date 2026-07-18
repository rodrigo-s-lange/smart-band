package security

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"os"
	"strings"
)

const envelopeVersion = 1

type BandKeyBox struct {
	aead cipher.AEAD
}

func NewBandKeyBox(keyEncryptionKey []byte) (*BandKeyBox, error) {
	if len(keyEncryptionKey) != 32 {
		return nil, errors.New("band key encryption key must contain 32 bytes")
	}
	block, err := aes.NewCipher(keyEncryptionKey)
	if err != nil {
		return nil, err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	return &BandKeyBox{aead: aead}, nil
}

func LoadBandKeyEncryptionKey(path string) ([]byte, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read band key encryption key: %w", err)
	}
	if len(raw) == 32 {
		return raw, nil
	}
	decoded, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(raw)))
	if err != nil || len(decoded) != 32 {
		return nil, errors.New("band key encryption key file must be 32 raw bytes or base64 for 32 bytes")
	}
	return decoded, nil
}

func (b *BandKeyBox) Encrypt(bandID string, bandKey []byte) ([]byte, error) {
	if len(bandKey) != 16 {
		return nil, errors.New("band key must contain 16 bytes")
	}
	nonce := make([]byte, b.aead.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return nil, err
	}
	envelope := make([]byte, 1, 1+len(nonce)+len(bandKey)+b.aead.Overhead())
	envelope[0] = envelopeVersion
	envelope = append(envelope, nonce...)
	envelope = b.aead.Seal(envelope, nonce, bandKey, []byte(bandID))
	return envelope, nil
}

func (b *BandKeyBox) Decrypt(bandID string, envelope []byte) ([]byte, error) {
	nonceSize := b.aead.NonceSize()
	if len(envelope) != 1+nonceSize+16+b.aead.Overhead() || envelope[0] != envelopeVersion {
		return nil, errors.New("invalid band key envelope")
	}
	nonce := envelope[1 : 1+nonceSize]
	plaintext, err := b.aead.Open(nil, nonce, envelope[1+nonceSize:], []byte(bandID))
	if err != nil {
		return nil, errors.New("cannot decrypt band key")
	}
	if len(plaintext) != 16 {
		return nil, errors.New("decrypted band key has invalid length")
	}
	return plaintext, nil
}
