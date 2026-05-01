package registry

import (
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// DeviceInfo holds metadata and the active WebSocket connection for a device.
type DeviceInfo struct {
	DeviceID   string
	DeviceType string // "agent" or "client"
	PublicKey  string
	Conn       *websocket.Conn
	Registered time.Time
	LastSeen   time.Time
	mu         sync.Mutex // protects writes to Conn
}

// WriteJSON safely writes a JSON message to the device's WebSocket connection.
// Concurrent writes to a single websocket.Conn are not allowed, so we serialize
// them with a per-device mutex.
func (d *DeviceInfo) WriteJSON(v any) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.Conn.WriteJSON(v)
}

// WriteMessage safely writes a raw message (binary or text) to the device's
// WebSocket connection.
func (d *DeviceInfo) WriteMessage(msgType int, data []byte) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.Conn.WriteMessage(msgType, data)
}

// Registry is a thread-safe in-memory store of connected devices.
type Registry struct {
	mu      sync.RWMutex
	devices map[string]*DeviceInfo // keyed by device_id
}

// New creates an empty Registry.
func New() *Registry {
	return &Registry{
		devices: make(map[string]*DeviceInfo),
	}
}

// Register adds or updates a device in the registry. If the device already
// exists (e.g. reconnection), the old entry is replaced.
func (r *Registry) Register(deviceID, deviceType, publicKey string, conn *websocket.Conn) *DeviceInfo {
	r.mu.Lock()
	defer r.mu.Unlock()

	now := time.Now()
	info := &DeviceInfo{
		DeviceID:   deviceID,
		DeviceType: deviceType,
		PublicKey:  publicKey,
		Conn:       conn,
		Registered: now,
		LastSeen:   now,
	}
	r.devices[deviceID] = info
	return info
}

// Unregister removes a device from the registry. Returns the removed device
// info, or nil if the device was not found or the connection did not match.
func (r *Registry) Unregister(deviceID string, conn *websocket.Conn) *DeviceInfo {
	r.mu.Lock()
	defer r.mu.Unlock()

	dev, ok := r.devices[deviceID]
	if !ok {
		return nil
	}
	// Only remove if the connection matches, to avoid removing a
	// re-connected device whose old connection is being cleaned up.
	if dev.Conn != conn {
		return nil
	}
	delete(r.devices, deviceID)
	return dev
}

// Get retrieves a device by ID.
func (r *Registry) Get(deviceID string) (*DeviceInfo, bool) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	dev, ok := r.devices[deviceID]
	if !ok {
		return nil, false
	}
	return dev, true
}

// UpdateLastSeen refreshes the heartbeat timestamp for a device.
func (r *Registry) UpdateLastSeen(deviceID string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if dev, ok := r.devices[deviceID]; ok {
		dev.LastSeen = time.Now()
	}
}

// ListOnline returns a snapshot of all currently online devices.
func (r *Registry) ListOnline() []DeviceInfo {
	r.mu.RLock()
	defer r.mu.RUnlock()

	result := make([]DeviceInfo, 0, len(r.devices))
	for _, dev := range r.devices {
		result = append(result, DeviceInfo{
			DeviceID:   dev.DeviceID,
			DeviceType: dev.DeviceType,
			PublicKey:  dev.PublicKey,
		})
	}
	return result
}

// ListOnlineByType returns a snapshot of online devices filtered by device type.
func (r *Registry) ListOnlineByType(deviceType string) []DeviceInfo {
	r.mu.RLock()
	defer r.mu.RUnlock()

	result := make([]DeviceInfo, 0, len(r.devices))
	for _, dev := range r.devices {
		if dev.DeviceType == deviceType {
			result = append(result, DeviceInfo{
				DeviceID:   dev.DeviceID,
				DeviceType: dev.DeviceType,
				PublicKey:  dev.PublicKey,
			})
		}
	}
	return result
}

// ForEach iterates over all devices with a read lock. The callback must NOT
// modify the DeviceInfo or block for extended periods.
func (r *Registry) ForEach(fn func(*DeviceInfo)) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	for _, dev := range r.devices {
		fn(dev)
	}
}

// Size returns the number of registered devices.
func (r *Registry) Size() int {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return len(r.devices)
}
