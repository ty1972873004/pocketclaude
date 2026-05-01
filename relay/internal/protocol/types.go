package protocol

import "encoding/json"

// JSON-RPC 2.0 message types used for control communication between
// devices and the relay server. All control messages are JSON text frames.
// Binary WebSocket frames are forwarded as-is without parsing.

const (
	JsonRPCVersion = "2.0"

	// Control methods (client/agent -> relay)
	MethodDeviceRegister    = "device.register"
	MethodDeviceListOnline  = "device.list_online"
	MethodMessageSend       = "message.send"
	MethodPresenceHeartbeat = "presence.heartbeat"

	// Server-initiated methods (relay -> client/agent)
	MethodMessageForward  = "message.forward"
	MethodPresenceOnline  = "presence.online"
	MethodPresenceOffline = "presence.offline"
)

// JSONRPCRequest is a generic JSON-RPC 2.0 request/notification.
type JSONRPCRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
	ID      *int64          `json:"id,omitempty"`
}

// JSONRPCResponse is a JSON-RPC 2.0 response.
type JSONRPCResponse struct {
	JSONRPC string        `json:"jsonrpc"`
	Result  any           `json:"result,omitempty"`
	Error   *JSONRPCError `json:"error,omitempty"`
	ID      *int64        `json:"id"`
}

// JSONRPCError represents a JSON-RPC 2.0 error object.
type JSONRPCError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

// NewResponse creates a success response for the given request ID.
func NewResponse(id *int64, result any) JSONRPCResponse {
	return JSONRPCResponse{
		JSONRPC: JsonRPCVersion,
		Result:  result,
		ID:      id,
	}
}

// NewErrorResponse creates an error response for the given request ID.
func NewErrorResponse(id *int64, code int, message string) JSONRPCResponse {
	return JSONRPCResponse{
		JSONRPC: JsonRPCVersion,
		Error: &JSONRPCError{
			Code:    code,
			Message: message,
		},
		ID: id,
	}
}

// NewNotification creates a server-initiated notification (no ID).
func NewNotification(method string, params any) JSONRPCRequest {
	return JSONRPCRequest{
		JSONRPC: JsonRPCVersion,
		Method:  method,
		Params:  mustMarshal(params),
	}
}

// --- Params structures for each method ---

// RegisterParams is the params for device.register.
type RegisterParams struct {
	DeviceID   string `json:"device_id"`
	DeviceType string `json:"device_type"` // "agent" or "client"
	PublicKey  string `json:"public_key"`
}

// ListOnlineParams is the params for device.list_online.
type ListOnlineParams struct {
	// optional filters can be added later
}

// SendParams is the params for message.send.
type SendParams struct {
	TargetID         string `json:"target_id"`
	EncryptedPayload []byte `json:"encrypted_payload"`
	Nonce            []byte `json:"nonce"`
}

// ForwardParams is the params for message.forward (server -> device).
type ForwardParams struct {
	SourceID         string `json:"source_id"`
	EncryptedPayload []byte `json:"encrypted_payload"`
	Nonce            []byte `json:"nonce"`
}

// HeartbeatParams is the params for presence.heartbeat.
type HeartbeatParams struct {
	Timestamp int64 `json:"timestamp"`
}

// OnlineParams is the params for presence.online (server -> devices).
type OnlineParams struct {
	DeviceID   string `json:"device_id"`
	DeviceType string `json:"device_type"`
	PublicKey  string `json:"public_key"`
}

// OfflineParams is the params for presence.offline (server -> devices).
type OfflineParams struct {
	DeviceID string `json:"device_id"`
}

// ListOnlineResult is the result for device.list_online.
type ListOnlineResult struct {
	Devices []OnlineDeviceInfo `json:"devices"`
}

// OnlineDeviceInfo describes an online device.
type OnlineDeviceInfo struct {
	DeviceID   string `json:"device_id"`
	DeviceType string `json:"device_type"`
	PublicKey  string `json:"public_key"`
}

// RegisterResult is the result for device.register.
type RegisterResult struct {
	Success   bool  `json:"success"`
	Timestamp int64 `json:"timestamp"`
}

// HeartbeatResult is the result for presence.heartbeat.
type HeartbeatResult struct {
	Timestamp int64 `json:"timestamp"`
}

// Standard JSON-RPC error codes.
const (
	ErrorCodeParseError        = -32700
	ErrorCodeInvalidRequest    = -32600
	ErrorCodeMethodNotFound    = -32601
	ErrorCodeInvalidParams     = -32602
	ErrorCodeInternal          = -32603
	ErrorCodeDeviceNotFound    = -32001
	ErrorCodeNotRegistered     = -32002
	ErrorCodeAlreadyRegistered = -32003
)

func mustMarshal(v any) json.RawMessage {
	b, err := json.Marshal(v)
	if err != nil {
		return json.RawMessage("{}")
	}
	return json.RawMessage(b)
}
