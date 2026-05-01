package connection

import (
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// RelayClient manages the connection to the relay server with auto-reconnect.
type RelayClient struct {
	url         string
	deviceID    string
	publicKey   string
	conn        *websocket.Conn
	mu          sync.Mutex
	done        chan struct{}
	closed      bool
	onMessage   func(msg map[string]any)
	onConnect   func()
	onDisconnect func(err error)
	reconnectInterval time.Duration
}

// NewRelayClient creates a new relay client.
func NewRelayClient(url, deviceID string) *RelayClient {
	return &RelayClient{
		url:               url,
		deviceID:          deviceID,
		done:              make(chan struct{}),
		reconnectInterval: 5 * time.Second,
	}
}

// SetMessageHandler sets the callback for incoming messages.
func (c *RelayClient) SetMessageHandler(handler func(msg map[string]any)) {
	c.onMessage = handler
}

// SetOnConnect sets the callback for when connection is established.
func (c *RelayClient) SetOnConnect(handler func()) {
	c.onConnect = handler
}

// SetOnDisconnect sets the callback for when connection is lost.
func (c *RelayClient) SetOnDisconnect(handler func(err error)) {
	c.onDisconnect = handler
}

// SetPublicKey sets the agent's public key for registration.
func (c *RelayClient) SetPublicKey(pubKey string) {
	c.publicKey = pubKey
}

// Connect establishes a WebSocket connection to the relay and registers the device.
// It blocks and auto-reconnects until Close() is called.
func (c *RelayClient) Connect() error {
	for {
		if c.isClosed() {
			return nil
		}

		err := c.connectOnce()
		if c.isClosed() {
			return nil
		}

		if err != nil {
			log.Printf("[Relay] Connection error: %v", err)
			if c.onDisconnect != nil {
				c.onDisconnect(err)
			}
		}

		log.Printf("[Relay] Reconnecting in %v...", c.reconnectInterval)

		select {
		case <-time.After(c.reconnectInterval):
			continue
		case <-c.done:
			return nil
		}
	}
}

// connectOnce makes a single connection attempt.
func (c *RelayClient) connectOnce() error {
	wsURL := c.url + "/ws"
	log.Printf("[Relay] Connecting to %s", wsURL)

	dialer := websocket.DefaultDialer
	dialer.HandshakeTimeout = 10 * time.Second

	conn, _, err := dialer.Dial(wsURL, nil)
	if err != nil {
		return fmt.Errorf("dial failed: %w", err)
	}

	c.mu.Lock()
	c.conn = conn
	c.mu.Unlock()

	// Register with relay
	registerMsg := map[string]any{
		"jsonrpc": "2.0",
		"id":      "register",
		"method":  "device.register",
		"params": map[string]any{
			"device_id":   c.deviceID,
			"device_type": "agent",
			"public_key":  c.publicKey,
		},
	}
	if err := conn.WriteJSON(registerMsg); err != nil {
		conn.Close()
		return fmt.Errorf("registration failed: %w", err)
	}

	log.Printf("[Relay] Registered device %s", c.deviceID)

	if c.onConnect != nil {
		c.onConnect()
	}

	// Start heartbeat
	stopHeartbeat := make(chan struct{})
	go c.heartbeat(stopHeartbeat)

	// Read loop (blocks until disconnect)
	err = c.readLoop()

	close(stopHeartbeat)

	c.mu.Lock()
	c.conn = nil
	c.mu.Unlock()

	return err
}

// Send forwards an encrypted message to a target device via the relay.
func (c *RelayClient) Send(targetID string, payload []byte, nonce []byte) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.conn == nil {
		return ErrNotConnected
	}

	msg := map[string]any{
		"jsonrpc": "2.0",
		"method":  "message.send",
		"params": map[string]any{
			"target_id":         targetID,
			"encrypted_payload": payload,
			"nonce":             nonce,
		},
	}
	return c.conn.WriteJSON(msg)
}

// SendJSONRPC sends a JSON-RPC request to the relay.
func (c *RelayClient) SendJSONRPC(method string, params map[string]any) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.conn == nil {
		return ErrNotConnected
	}

	msg := map[string]any{
		"jsonrpc": "2.0",
		"id":      fmt.Sprintf("%d", time.Now().UnixNano()),
		"method":  method,
		"params":  params,
	}
	return c.conn.WriteJSON(msg)
}

// SendJSON sends a raw JSON message to the relay.
func (c *RelayClient) SendJSON(msg any) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.conn == nil {
		return ErrNotConnected
	}
	return c.conn.WriteJSON(msg)
}

func (c *RelayClient) heartbeat(stop <-chan struct{}) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			c.mu.Lock()
			if c.conn != nil {
				msg := map[string]any{
					"jsonrpc": "2.0",
					"method":  "presence.heartbeat",
					"id":      fmt.Sprintf("hb-%d", time.Now().Unix()),
				}
				if err := c.conn.WriteJSON(msg); err != nil {
					log.Printf("[Relay] Heartbeat failed: %v", err)
				}
			}
			c.mu.Unlock()
		case <-stop:
			return
		case <-c.done:
			return
		}
	}
}

func (c *RelayClient) readLoop() error {
	for {
		if c.isClosed() {
			return nil
		}

		c.mu.Lock()
		conn := c.conn
		c.mu.Unlock()

		if conn == nil {
			return fmt.Errorf("connection lost")
		}

		_, msg, err := conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseNormalClosure) {
				return fmt.Errorf("read error: %w", err)
			}
			return nil // clean close
		}

		var jsonMsg map[string]any
		if err := json.Unmarshal(msg, &jsonMsg); err != nil {
			log.Printf("[Relay] Invalid JSON: %v", err)
			continue
		}

		if c.onMessage != nil {
			c.onMessage(jsonMsg)
		}
	}
}

// IsConnected returns whether the client is currently connected.
func (c *RelayClient) IsConnected() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.conn != nil
}

func (c *RelayClient) isClosed() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.closed
}

// Close closes the relay connection and stops auto-reconnect.
func (c *RelayClient) Close() {
	c.mu.Lock()
	c.closed = true
	if c.conn != nil {
		c.conn.WriteMessage(websocket.CloseMessage,
			websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""))
		c.conn.Close()
		c.conn = nil
	}
	c.mu.Unlock()

	select {
	case <-c.done:
		// already closed
	default:
		close(c.done)
	}
}

// ErrNotConnected is returned when an operation requires a connection.
var ErrNotConnected = &ConnectionError{"not connected to relay"}

// ConnectionError represents a connection-related error.
type ConnectionError struct {
	msg string
}

func (e *ConnectionError) Error() string { return e.msg }
