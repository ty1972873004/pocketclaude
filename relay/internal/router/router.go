package router

import (
	"encoding/json"
	"log/slog"
	"time"

	"github.com/gorilla/websocket"

	"github.com/pocketclaude/relay/internal/protocol"
	"github.com/pocketclaude/relay/internal/registry"
)

// Router handles JSON-RPC control messages and binary message forwarding.
// It is created once per WebSocket connection and dispatches incoming
// messages to the appropriate handler.
type Router struct {
	registry   *registry.Registry
	deviceID   string // empty until registration
	registered bool
	logger     *slog.Logger
}

// New creates a Router for a new, not-yet-registered connection.
func New(reg *registry.Registry, logger *slog.Logger) *Router {
	return &Router{
		registry: reg,
		logger:   logger,
	}
}

// HandleText parses a JSON text frame and dispatches the control message.
// Returns true if the connection should remain open, false if it should be
// closed (e.g. after a protocol error).
func (r *Router) HandleText(conn *websocket.Conn, data []byte) bool {
	var req protocol.JSONRPCRequest
	if err := json.Unmarshal(data, &req); err != nil {
		r.logger.Warn("failed to parse JSON-RPC message", "error", err)
		sendError(conn, nil, protocol.ErrorCodeParseError, "parse error")
		return true
	}

	if req.JSONRPC != protocol.JsonRPCVersion {
		sendError(conn, req.ID, protocol.ErrorCodeInvalidRequest, "invalid jsonrpc version")
		return true
	}

	switch req.Method {
	case protocol.MethodDeviceRegister:
		return r.handleRegister(conn, req)
	case protocol.MethodDeviceListOnline:
		return r.handleListOnline(conn, req)
	case protocol.MethodMessageSend:
		return r.handleMessageSend(conn, req)
	case protocol.MethodPresenceHeartbeat:
		return r.handleHeartbeat(conn, req)
	default:
		sendError(conn, req.ID, protocol.ErrorCodeMethodNotFound, "method not found: "+req.Method)
		return true
	}
}

// HandleBinary forwards a binary frame to the target device. The first 32 bytes
// of the payload are the target device_id (fixed-size, null-padded), followed by
// the encrypted blob that gets forwarded as-is.
//
// Binary frame layout:
//
//	[0:32]  target_device_id (null-padded UTF-8)
//	[32:]   encrypted payload (forwarded as-is)
func (r *Router) HandleBinary(data []byte) bool {
	if !r.registered {
		r.logger.Warn("binary frame from unregistered device")
		return true
	}

	if len(data) < 33 {
		r.logger.Warn("binary frame too short", "len", len(data))
		return true
	}

	// Extract target device ID (first 32 bytes, trim null padding).
	rawID := data[:32]
	targetID := ""
	for i, b := range rawID {
		if b == 0 {
			targetID = string(rawID[:i])
			break
		}
	}
	if targetID == "" {
		targetID = string(rawID)
	}

	payload := data[32:]

	targetDev, ok := r.registry.Get(targetID)
	if !ok {
		r.logger.Warn("binary forward target not found",
			"source", r.deviceID, "target", targetID)
		return true
	}

	// Reconstruct the binary frame for the target:
	// [0:32]  source_device_id (null-padded)
	// [32:]   payload
	srcID := padDeviceID(r.deviceID)
	fwd := make([]byte, 0, 32+len(payload))
	fwd = append(fwd, srcID...)
	fwd = append(fwd, payload...)

	if err := targetDev.WriteMessage(1, fwd); err != nil { // 1 = binary
		r.logger.Error("failed to forward binary message",
			"source", r.deviceID, "target", targetID, "error", err)
	}
	return true
}

// DeviceID returns the registered device ID (empty string before registration).
func (r *Router) DeviceID() string {
	return r.deviceID
}

// IsRegistered returns whether this connection has completed registration.
func (r *Router) IsRegistered() bool {
	return r.registered
}

// --- Handler methods ---

func (r *Router) handleRegister(conn *websocket.Conn, req protocol.JSONRPCRequest) bool {
	var params protocol.RegisterParams
	if err := json.Unmarshal(req.Params, &params); err != nil {
		sendError(conn, req.ID, protocol.ErrorCodeInvalidParams, "invalid register params")
		return true
	}

	if params.DeviceID == "" {
		sendError(conn, req.ID, protocol.ErrorCodeInvalidParams, "device_id is required")
		return true
	}
	if params.DeviceType != "agent" && params.DeviceType != "client" {
		sendError(conn, req.ID, protocol.ErrorCodeInvalidParams, "device_type must be 'agent' or 'client'")
		return true
	}

	// Check if this device_id is already registered with a different connection.
	if existing, ok := r.registry.Get(params.DeviceID); ok {
		if existing.Conn == conn {
			// Same connection re-registering, just update.
			r.logger.Info("device re-registering on same connection", "device_id", params.DeviceID)
		} else {
			// Different connection, close the old one.
			r.logger.Info("device reconnecting, closing old connection",
				"device_id", params.DeviceID)
			existing.WriteMessage(8, []byte("replaced by new connection")) // 8 = CloseMessage
			existing.Conn.Close()
		}
	}

	r.registry.Register(params.DeviceID, params.DeviceType, params.PublicKey, conn)
	r.deviceID = params.DeviceID
	r.registered = true

	r.logger.Info("device registered",
		"device_id", params.DeviceID, "type", params.DeviceType)

	// Send success response.
	resp := protocol.NewResponse(req.ID, protocol.RegisterResult{
		Success:   true,
		Timestamp: time.Now().Unix(),
	})
	if err := conn.WriteJSON(resp); err != nil {
		r.logger.Error("failed to send register response", "error", err)
		return false
	}

	// Broadcast presence.online to all other devices.
	notify := protocol.NewNotification(protocol.MethodPresenceOnline, protocol.OnlineParams{
		DeviceID:   params.DeviceID,
		DeviceType: params.DeviceType,
		PublicKey:  params.PublicKey,
	})
	r.registry.ForEach(func(dev *registry.DeviceInfo) {
		if dev.DeviceID != params.DeviceID {
			if err := dev.WriteJSON(notify); err != nil {
				r.logger.Warn("failed to send online notification",
					"to", dev.DeviceID, "error", err)
			}
		}
	})

	return true
}

func (r *Router) handleListOnline(conn *websocket.Conn, req protocol.JSONRPCRequest) bool {
	if !r.registered {
		sendError(conn, req.ID, protocol.ErrorCodeNotRegistered, "device not registered")
		return true
	}

	devices := r.registry.ListOnline()
	infos := make([]protocol.OnlineDeviceInfo, 0, len(devices))
	for _, d := range devices {
		infos = append(infos, protocol.OnlineDeviceInfo{
			DeviceID:   d.DeviceID,
			DeviceType: d.DeviceType,
			PublicKey:  d.PublicKey,
		})
	}

	resp := protocol.NewResponse(req.ID, protocol.ListOnlineResult{Devices: infos})
	if err := conn.WriteJSON(resp); err != nil {
		r.logger.Error("failed to send list_online response", "error", err)
		return false
	}
	return true
}

func (r *Router) handleMessageSend(conn *websocket.Conn, req protocol.JSONRPCRequest) bool {
	if !r.registered {
		sendError(conn, req.ID, protocol.ErrorCodeNotRegistered, "device not registered")
		return true
	}

	var params protocol.SendParams
	if err := json.Unmarshal(req.Params, &params); err != nil {
		sendError(conn, req.ID, protocol.ErrorCodeInvalidParams, "invalid send params")
		return true
	}

	if params.TargetID == "" {
		sendError(conn, req.ID, protocol.ErrorCodeInvalidParams, "target_id is required")
		return true
	}

	targetDev, ok := r.registry.Get(params.TargetID)
	if !ok {
		sendError(conn, req.ID, protocol.ErrorCodeDeviceNotFound, "target device not online: "+params.TargetID)
		return true
	}

	// Forward the message to the target as a message.forward notification.
	fwd := protocol.NewNotification(protocol.MethodMessageForward, protocol.ForwardParams{
		SourceID:         r.deviceID,
		EncryptedPayload: params.EncryptedPayload,
		Nonce:            params.Nonce,
	})
	if err := targetDev.WriteJSON(fwd); err != nil {
		r.logger.Error("failed to forward message",
			"source", r.deviceID, "target", params.TargetID, "error", err)
		sendError(conn, req.ID, protocol.ErrorCodeInternal, "forward failed")
		return true
	}

	// Acknowledge to sender.
	resp := protocol.NewResponse(req.ID, map[string]bool{"success": true})
	if err := conn.WriteJSON(resp); err != nil {
		r.logger.Error("failed to send ack", "error", err)
		return false
	}

	r.logger.Debug("message forwarded",
		"source", r.deviceID, "target", params.TargetID,
		"payload_size", len(params.EncryptedPayload))
	return true
}

func (r *Router) handleHeartbeat(conn *websocket.Conn, req protocol.JSONRPCRequest) bool {
	if !r.registered {
		sendError(conn, req.ID, protocol.ErrorCodeNotRegistered, "device not registered")
		return true
	}

	r.registry.UpdateLastSeen(r.deviceID)

	resp := protocol.NewResponse(req.ID, protocol.HeartbeatResult{
		Timestamp: time.Now().Unix(),
	})
	if err := conn.WriteJSON(resp); err != nil {
		r.logger.Error("failed to send heartbeat response", "error", err)
		return false
	}
	return true
}

// --- Helpers ---

func sendError(conn *websocket.Conn, id *int64, code int, message string) {
	resp := protocol.NewErrorResponse(id, code, message)
	// Best-effort write; ignore errors since the connection may be broken.
	_ = conn.WriteJSON(resp)
}

func padDeviceID(id string) []byte {
	buf := make([]byte, 32)
	copy(buf, id)
	return buf
}
