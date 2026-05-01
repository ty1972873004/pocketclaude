package crypto

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	qrcode "github.com/skip2/go-qrcode"
)

// PairingData is the data encoded in the QR code.
type PairingData struct {
	AgentID        string `json:"agent_id"`
	AgentIP        string `json:"agent_ip"`
	X25519PubKey   string `json:"x25519_pub_key"`
	Ed25519PubKey  string `json:"ed25519_pub_key"`
	RelayURL       string `json:"relay_url"`
	PairingPort    int    `json:"pairing_port"`
}

// PairingResponse is what the mobile client sends back after scanning.
type PairingResponse struct {
	ClientID       string `json:"client_id"`
	X25519PubKey   string `json:"x25519_pub_key"`
	Ed25519PubKey  string `json:"ed25519_pub_key"`
	DeviceName     string `json:"device_name"`
	Signature      string `json:"signature"`
}

// PairingResult contains the outcome of a successful pairing.
type PairingResult struct {
	ClientID     string
	ClientPubKey [32]byte
	Cipher       *E2ECipher
}

var pairingUpgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

// getLocalIP detects the machine's LAN IP by attempting a UDP dial.
func getLocalIP() string {
	conn, err := net.DialTimeout("udp", "8.8.8.8:80", time.Second)
	if err != nil {
		return "127.0.0.1"
	}
	defer conn.Close()
	addr := conn.LocalAddr().(*net.UDPAddr)
	return addr.IP.String()
}

// RunPairingFlow starts the pairing process:
// 1. Displays QR code in terminal
// 2. Starts temporary WebSocket server
// 3. Waits for mobile client to connect and exchange keys
// 4. Returns the pairing result
func RunPairingFlow(kp *KeyPair, cfg *Config) (*PairingResult, error) {
	// Find an available port for the pairing server
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, fmt.Errorf("failed to find available port: %w", err)
	}
	pairingPort := listener.Addr().(*net.TCPAddr).Port
	listener.Close()

	// Prepare pairing data for QR code
	pairingData := PairingData{
		AgentID:       cfg.DeviceID,
		AgentIP:       getLocalIP(),
		X25519PubKey:  base64.StdEncoding.EncodeToString(kp.X25519PublicKey[:]),
		Ed25519PubKey: base64.StdEncoding.EncodeToString(kp.Ed25519PublicKey),
		RelayURL:      cfg.RelayURL,
		PairingPort:   pairingPort,
	}

	qrJSON, err := json.Marshal(pairingData)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal pairing data: %w", err)
	}

	// Generate and display QR code
	qr, err := qrcode.New(string(qrJSON), qrcode.Medium)
	if err != nil {
		return nil, fmt.Errorf("failed to generate QR code: %w", err)
	}

	fmt.Println()
	fmt.Println("=== PocketClaude Agent Pairing ===")
	fmt.Println()
	fmt.Println("Scan this QR code with the PocketClaude mobile app:")
	fmt.Println()
	fmt.Println(qr.ToSmallString(false))
	fmt.Println()
	fmt.Printf("Agent ID: %s\n", cfg.DeviceID)
	fmt.Printf("Public Key Fingerprint: %s\n", kp.Fingerprint())
	fmt.Printf("Waiting for pairing on port %d...\n", pairingPort)
	fmt.Println()

	// Channel to receive pairing result
	resultChan := make(chan *PairingResult, 1)
	errChan := make(chan error, 1)

	// Set up HTTP server for pairing
	mux := http.NewServeMux()
	mux.HandleFunc("/pair", func(w http.ResponseWriter, r *http.Request) {
		conn, err := pairingUpgrader.Upgrade(w, r, nil)
		if err != nil {
			errChan <- fmt.Errorf("WebSocket upgrade failed: %w", err)
			return
		}
		defer conn.Close()

		// Set read deadline
		conn.SetReadDeadline(time.Now().Add(30 * time.Second))

		// Read pairing response from client
		_, msg, err := conn.ReadMessage()
		if err != nil {
			errChan <- fmt.Errorf("failed to read pairing message: %w", err)
			return
		}

		var resp PairingResponse
		if err := json.Unmarshal(msg, &resp); err != nil {
			errChan <- fmt.Errorf("invalid pairing response: %w", err)
			return
		}

		// Decode client's X25519 public key
		clientPubKeyBytes, err := base64.StdEncoding.DecodeString(resp.X25519PubKey)
		if err != nil {
			errChan <- fmt.Errorf("invalid client public key: %w", err)
			return
		}

		if len(clientPubKeyBytes) != 32 {
			errChan <- fmt.Errorf("client public key must be 32 bytes, got %d", len(clientPubKeyBytes))
			return
		}

		var clientPubKey [32]byte
		copy(clientPubKey[:], clientPubKeyBytes)

		// Derive shared secret
		cipher, err := NewE2ECipher(kp.X25519PrivateKey, clientPubKey)
		if err != nil {
			errChan <- fmt.Errorf("failed to derive shared secret: %w", err)
			return
		}

		// Send confirmation back to client
		confirmMsg := map[string]string{
			"status":   "paired",
			"agent_id": cfg.DeviceID,
		}
		confirmJSON, _ := json.Marshal(confirmMsg)
		if err := conn.WriteMessage(websocket.TextMessage, confirmJSON); err != nil {
			errChan <- fmt.Errorf("failed to send confirmation: %w", err)
			return
		}

		resultChan <- &PairingResult{
			ClientID:     resp.ClientID,
			ClientPubKey: clientPubKey,
			Cipher:       cipher,
		}
	})

	server := &http.Server{
		Handler: mux,
		Addr:    fmt.Sprintf("0.0.0.0:%d", pairingPort),
	}

	// Start server in goroutine
	go func() {
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			select {
			case errChan <- fmt.Errorf("pairing server error: %w", err):
			default:
			}
		}
	}()

	// Wait for result or timeout
	select {
	case result := <-resultChan:
		server.Close()
		return result, nil
	case err := <-errChan:
		server.Close()
		return nil, err
	case <-time.After(5 * time.Minute):
		server.Close()
		return nil, fmt.Errorf("pairing timed out after 5 minutes")
	}
}

// GeneratePairingQRString generates the QR code content string for pairing.
func GeneratePairingQRString(kp *KeyPair, cfg *Config, port int) (string, error) {
	pairingData := PairingData{
		AgentID:       cfg.DeviceID,
		AgentIP:       getLocalIP(),
		X25519PubKey:  base64.StdEncoding.EncodeToString(kp.X25519PublicKey[:]),
		Ed25519PubKey: base64.StdEncoding.EncodeToString(kp.Ed25519PublicKey),
		RelayURL:      cfg.RelayURL,
		PairingPort:   port,
	}

	qrJSON, err := json.Marshal(pairingData)
	if err != nil {
		return "", err
	}

	return string(qrJSON), nil
}

// IsPaired checks if a client has been paired with this agent.
func IsPaired() bool {
	cfg, err := LoadConfig()
	if err != nil {
		return false
	}
	return cfg.PairedClientID != "" && cfg.PairedClientPubKey != ""
}

// ParseClientPubKey decodes the paired client's X25519 public key from config.
func ParseClientPubKey(b64 string) ([32]byte, error) {
	var key [32]byte
	bytes, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return key, fmt.Errorf("failed to decode client public key: %w", err)
	}
	if len(bytes) != 32 {
		return key, fmt.Errorf("client public key must be 32 bytes, got %d", len(bytes))
	}
	copy(key[:], bytes)
	return key, nil
}

// PrintQRCode prints a QR code to the terminal for the given content.
func PrintQRCode(content string) error {
	qr, err := qrcode.New(content, qrcode.Medium)
	if err != nil {
		return fmt.Errorf("failed to generate QR code: %w", err)
	}

	// Get terminal QR string
	terminalQR := qr.ToSmallString(false)
	lines := strings.Split(terminalQR, "\n")

	fmt.Println()
	fmt.Println("  +-------------------------------+")
	fmt.Println("  |   PocketClaude Pairing QR      |")
	fmt.Println("  +-------------------------------+")
	fmt.Println()
	for _, line := range lines {
		fmt.Printf("      %s\n", line)
	}
	fmt.Println()
	return nil
}

// NewUUID generates a new UUID string.
func NewUUID() string {
	return uuid.New().String()
}

// Log is a simple logger for the crypto package.
var Log = log.Default()
