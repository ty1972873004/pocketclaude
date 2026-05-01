package presence

import (
	"log/slog"
	"sync"
	"time"

	"github.com/gorilla/websocket"

	"github.com/pocketclaude/relay/internal/protocol"
	"github.com/pocketclaude/relay/internal/registry"
)

const (
	// HeartbeatInterval is how often the presence checker runs.
	HeartbeatInterval = 30 * time.Second

	// StaleThreshold is how long since last heartbeat before a device is
	// considered disconnected.
	StaleThreshold = 90 * time.Second
)

// Presence manages heartbeat checking and notifies other devices when a
// device goes offline.
type Presence struct {
	registry *registry.Registry
	logger   *slog.Logger

	mu      sync.Mutex
	done    chan struct{}
	running bool
}

// New creates a new Presence service.
func New(reg *registry.Registry, logger *slog.Logger) *Presence {
	return &Presence{
		registry: reg,
		logger:   logger,
		done:     make(chan struct{}),
	}
}

// Start begins the periodic presence check loop. It blocks until Stop is
// called, so it should be launched in a goroutine.
func (p *Presence) Start() {
	p.mu.Lock()
	if p.running {
		p.mu.Unlock()
		return
	}
	p.running = true
	p.mu.Unlock()

	ticker := time.NewTicker(HeartbeatInterval)
	defer ticker.Stop()

	p.logger.Info("presence service started",
		"interval", HeartbeatInterval, "stale_threshold", StaleThreshold)

	for {
		select {
		case <-ticker.C:
			p.check()
		case <-p.done:
			p.logger.Info("presence service stopped")
			return
		}
	}
}

// Stop terminates the presence check loop.
func (p *Presence) Stop() {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.running {
		close(p.done)
		p.running = false
	}
}

// check scans all devices and removes those whose LastSeen is older than
// StaleThreshold. Removed devices are notified as offline to all others.
func (p *Presence) check() {
	var stale []*registry.DeviceInfo

	p.registry.ForEach(func(dev *registry.DeviceInfo) {
		if time.Since(dev.LastSeen) > StaleThreshold {
			stale = append(stale, dev)
		}
	})

	for _, dev := range stale {
		p.logger.Info("removing stale device",
			"device_id", dev.DeviceID,
			"last_seen", dev.LastSeen,
			"stale_duration", time.Since(dev.LastSeen),
		)

		removed := p.registry.Unregister(dev.DeviceID, dev.Conn)
		if removed == nil {
			// Already removed or re-connected with a new connection.
			continue
		}

		// Attempt a clean close of the stale connection.
		_ = dev.WriteMessage(
			websocket.CloseMessage,
			websocket.FormatCloseMessage(websocket.CloseGoingAway, "heartbeat timeout"),
		)
		dev.Conn.Close()

		// Broadcast offline notification.
		notify := protocol.NewNotification(protocol.MethodPresenceOffline, protocol.OfflineParams{
			DeviceID: dev.DeviceID,
		})
		p.registry.ForEach(func(other *registry.DeviceInfo) {
			if err := other.WriteJSON(notify); err != nil {
				p.logger.Warn("failed to send offline notification",
					"to", other.DeviceID, "error", err)
			}
		})
	}

	if len(stale) > 0 {
		p.logger.Info("presence check completed", "removed", len(stale),
			"remaining", p.registry.Size())
	}
}
