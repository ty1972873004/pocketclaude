package api

import (
	"log/slog"
	"net/http"
	"time"

	"github.com/gorilla/websocket"

	"github.com/pocketclaude/relay/internal/protocol"
	"github.com/pocketclaude/relay/internal/registry"
	"github.com/pocketclaude/relay/internal/router"
)

// Handler implements http.Handler and upgrades HTTP connections to WebSocket,
// then dispatches incoming frames through the Router.
type Handler struct {
	registry *registry.Registry
	upgrader websocket.Upgrader
	logger   *slog.Logger
}

// NewHandler creates a WebSocket Handler backed by the given registry.
func NewHandler(reg *registry.Registry, logger *slog.Logger) *Handler {
	return &Handler{
		registry: reg,
		upgrader: websocket.Upgrader{
			// Allow all origins; device authentication is handled via
			// the device.register JSON-RPC call, not HTTP headers.
			CheckOrigin: func(r *http.Request) bool { return true },
		},
		logger: logger,
	}
}

// ServeHTTP upgrades the request to WebSocket and starts the read loop.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	conn, err := h.upgrader.Upgrade(w, r, nil)
	if err != nil {
		h.logger.Error("websocket upgrade failed", "remote", r.RemoteAddr, "error", err)
		return
	}

	rt := router.New(h.registry, h.logger)
	defer h.cleanup(conn, rt)

	h.logger.Info("websocket connection established", "remote", conn.RemoteAddr())

	// Read loop: process messages until error or close.
	for {
		msgType, data, err := conn.ReadMessage()
		if err != nil {
			// Normal close or unexpected close from client.
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseNormalClosure) {
				h.logger.Warn("websocket read error",
					"remote", conn.RemoteAddr(), "error", err)
			}
			return
		}

		var keepOpen bool
		switch msgType {
		case websocket.TextMessage:
			keepOpen = rt.HandleText(conn, data)
		case websocket.BinaryMessage:
			keepOpen = rt.HandleBinary(data)
		default:
			// Ping/Pong handled by gorilla/websocket internally.
			keepOpen = true
		}

		if !keepOpen {
			return
		}
	}
}

// cleanup handles disconnection: unregister the device, close the connection,
// and broadcast an offline notification to remaining devices.
func (h *Handler) cleanup(conn *websocket.Conn, rt *router.Router) {
	deviceID := rt.DeviceID()
	if deviceID != "" {
		removed := h.registry.Unregister(deviceID, conn)
		if removed != nil {
			h.logger.Info("device disconnected",
				"device_id", deviceID, "remote", conn.RemoteAddr())

			// Broadcast offline notification.
			notify := protocol.NewNotification(protocol.MethodPresenceOffline, protocol.OfflineParams{
				DeviceID: deviceID,
			})
			h.registry.ForEach(func(dev *registry.DeviceInfo) {
				if err := dev.WriteJSON(notify); err != nil {
					h.logger.Warn("failed to send offline notification",
						"to", dev.DeviceID, "error", err)
				}
			})
		}
	}

	// Set a deadline for the close write and close the connection.
	_ = conn.WriteControl(
		websocket.CloseMessage,
		websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""),
		time.Now().Add(time.Second*5),
	)
	conn.Close()

	h.logger.Debug("connection cleaned up", "remote", conn.RemoteAddr())
}
