package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/binary"
	"fmt"
	"io"
	"sync"

	"golang.org/x/crypto/curve25519"
)

// E2ECipher provides end-to-end encryption using AES-256-GCM with X25519 key exchange.
type E2ECipher struct {
	mu        sync.Mutex
	encryptor cipher.AEAD
	decryptor cipher.AEAD
	sendNonce uint64
	recvNonce uint64
}

// NewE2ECipher creates a new E2E cipher by performing X25519 Diffie-Hellman
// with the local private key and the remote public key.
func NewE2ECipher(localPrivKey [32]byte, remotePubKey [32]byte) (*E2ECipher, error) {
	// Perform X25519 DH to derive shared secret
	sharedSecret, err := curve25519.X25519(localPrivKey[:], remotePubKey[:])
	if err != nil {
		return nil, fmt.Errorf("X25519 key exchange failed: %w", err)
	}

	// Use the shared secret directly as the AES-256 key (it's 32 bytes)
	block, err := aes.NewCipher(sharedSecret)
	if err != nil {
		return nil, fmt.Errorf("failed to create AES cipher: %w", err)
	}

	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("failed to create GCM: %w", err)
	}

	return &E2ECipher{
		encryptor: aead,
		decryptor: aead,
	}, nil
}

// Encrypt encrypts plaintext using AES-256-GCM with an incrementing nonce.
// The output format is: [8-byte nonce counter] + [GCM ciphertext + tag]
func (c *E2ECipher) Encrypt(plaintext []byte) ([]byte, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	// Generate nonce from counter
	var nonce [12]byte
	binary.BigEndian.PutUint64(nonce[4:12], c.sendNonce)
	c.sendNonce++

	// Encrypt
	ciphertext := c.encryptor.Seal(nil, nonce[:], plaintext, nil)

	// Prepend nonce counter (8 bytes)
	result := make([]byte, 8+len(ciphertext))
	binary.BigEndian.PutUint64(result[0:8], c.sendNonce-1)
	copy(result[8:], ciphertext)

	return result, nil
}

// Decrypt decrypts data encrypted by Encrypt.
// Input format: [8-byte nonce counter] + [GCM ciphertext + tag]
func (c *E2ECipher) Decrypt(data []byte) ([]byte, error) {
	if len(data) < 8 {
		return nil, fmt.Errorf("ciphertext too short")
	}

	c.mu.Lock()
	defer c.mu.Unlock()

	// Extract nonce counter
	nonceCounter := binary.BigEndian.Uint64(data[0:8])
	ciphertext := data[8:]

	// Reconstruct nonce
	var nonce [12]byte
	binary.BigEndian.PutUint64(nonce[4:12], nonceCounter)

	// Decrypt
	plaintext, err := c.decryptor.Open(nil, nonce[:], ciphertext, nil)
	if err != nil {
		return nil, fmt.Errorf("decryption failed: %w", err)
	}

	c.recvNonce = nonceCounter + 1

	return plaintext, nil
}

// GenerateRandomBytes generates cryptographically random bytes.
func GenerateRandomBytes(n int) ([]byte, error) {
	b := make([]byte, n)
	if _, err := io.ReadFull(rand.Reader, b); err != nil {
		return nil, fmt.Errorf("failed to generate random bytes: %w", err)
	}
	return b, nil
}
