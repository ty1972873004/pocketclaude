package crypto

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"golang.org/x/crypto/curve25519"
)

// KeyPair holds the agent's cryptographic key pairs.
type KeyPair struct {
	Ed25519PrivateKey ed25519.PrivateKey
	Ed25519PublicKey  ed25519.PublicKey
	X25519PrivateKey  [32]byte // curve25519 private key
	X25519PublicKey   [32]byte // curve25519 public key
}

// Config represents the agent configuration stored on disk.
type Config struct {
	DeviceID           string `json:"device_id"`
	Ed25519PrivKeyB64  string `json:"ed25519_private_key"`
	Ed25519PubKeyB64   string `json:"ed25519_public_key"`
	X25519PrivKeyB64   string `json:"x25519_private_key"`
	X25519PubKeyB64    string `json:"x25519_public_key"`
	RelayURL           string `json:"relay_url"`
	APIPort            int    `json:"api_port"`
	PairedClientPubKey string `json:"paired_client_pub_key,omitempty"`
	PairedClientID     string `json:"paired_client_id,omitempty"`
}

// DefaultConfigDir returns the default config directory path.
func DefaultConfigDir() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("cannot determine home directory: %w", err)
	}
	return filepath.Join(home, ".pocketclaude"), nil
}

// ConfigPath returns the full path to the config file.
func ConfigPath() (string, error) {
	dir, err := DefaultConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "config.json"), nil
}

// GenerateKeyPair creates new Ed25519 and X25519 key pairs.
func GenerateKeyPair() (*KeyPair, error) {
	// Generate Ed25519 key pair
	edPub, edPriv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("failed to generate Ed25519 key pair: %w", err)
	}

	// Generate X25519 key pair
	// We generate a random 32-byte private key and derive the public key
	var xPriv [32]byte
	if _, err := rand.Read(xPriv[:]); err != nil {
		return nil, fmt.Errorf("failed to generate X25519 private key: %w", err)
	}
	// Clamp private key per curve25519 spec
	xPriv[0] &= 248
	xPriv[31] &= 127
	xPriv[31] |= 64

	xPub, err := curve25519.X25519(xPriv[:], curve25519.Basepoint)
	if err != nil {
		return nil, fmt.Errorf("failed to derive X25519 public key: %w", err)
	}

	var xPubArr [32]byte
	copy(xPubArr[:], xPub)

	return &KeyPair{
		Ed25519PrivateKey: edPriv,
		Ed25519PublicKey:  edPub,
		X25519PrivateKey:  xPriv,
		X25519PublicKey:   xPubArr,
	}, nil
}

// SaveConfig writes the configuration and keys to disk.
func SaveConfig(kp *KeyPair, deviceID, relayURL string, apiPort int) error {
	configDir, err := DefaultConfigDir()
	if err != nil {
		return err
	}

	if err := os.MkdirAll(configDir, 0700); err != nil {
		return fmt.Errorf("failed to create config directory: %w", err)
	}

	cfg := Config{
		DeviceID:          deviceID,
		Ed25519PrivKeyB64: base64.StdEncoding.EncodeToString(kp.Ed25519PrivateKey),
		Ed25519PubKeyB64:  base64.StdEncoding.EncodeToString(kp.Ed25519PublicKey),
		X25519PrivKeyB64:  base64.StdEncoding.EncodeToString(kp.X25519PrivateKey[:]),
		X25519PubKeyB64:   base64.StdEncoding.EncodeToString(kp.X25519PublicKey[:]),
		RelayURL:          relayURL,
		APIPort:           apiPort,
	}

	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal config: %w", err)
	}

	configFile := filepath.Join(configDir, "config.json")
	if err := os.WriteFile(configFile, data, 0600); err != nil {
		return fmt.Errorf("failed to write config file: %w", err)
	}

	return nil
}

// LoadConfig reads the configuration from disk.
func LoadConfig() (*Config, error) {
	cp, err := ConfigPath()
	if err != nil {
		return nil, err
	}

	data, err := os.ReadFile(cp)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config file: %w", err)
	}

	return &cfg, nil
}

// LoadKeyPair reconstructs the KeyPair from a loaded Config.
func LoadKeyPair(cfg *Config) (*KeyPair, error) {
	edPriv, err := base64.StdEncoding.DecodeString(cfg.Ed25519PrivKeyB64)
	if err != nil {
		return nil, fmt.Errorf("failed to decode Ed25519 private key: %w", err)
	}
	edPub, err := base64.StdEncoding.DecodeString(cfg.Ed25519PubKeyB64)
	if err != nil {
		return nil, fmt.Errorf("failed to decode Ed25519 public key: %w", err)
	}
	xPriv, err := base64.StdEncoding.DecodeString(cfg.X25519PrivKeyB64)
	if err != nil {
		return nil, fmt.Errorf("failed to decode X25519 private key: %w", err)
	}
	xPub, err := base64.StdEncoding.DecodeString(cfg.X25519PubKeyB64)
	if err != nil {
		return nil, fmt.Errorf("failed to decode X25519 public key: %w", err)
	}

	var xPrivArr, xPubArr [32]byte
	copy(xPrivArr[:], xPriv)
	copy(xPubArr[:], xPub)

	return &KeyPair{
		Ed25519PrivateKey: edPriv,
		Ed25519PublicKey:  edPub,
		X25519PrivateKey:  xPrivArr,
		X25519PublicKey:   xPubArr,
	}, nil
}

// Fingerprint returns a human-readable fingerprint of the Ed25519 public key.
func (kp *KeyPair) Fingerprint() string {
	h := sha256.Sum256(kp.Ed25519PublicKey)
	return fmt.Sprintf("%x", h)[:16]
}

// SavePairedClient saves the paired client information to the config.
func SavePairedClient(clientID, clientPubKeyB64 string) error {
	cfg, err := LoadConfig()
	if err != nil {
		return err
	}
	cfg.PairedClientID = clientID
	cfg.PairedClientPubKey = clientPubKeyB64
	return saveConfigFile(cfg)
}

func saveConfigFile(cfg *Config) error {
	configDir, err := DefaultConfigDir()
	if err != nil {
		return err
	}
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(configDir, "config.json"), data, 0600)
}
