package api

import "encoding/json"

const JsonRPCVersion = "2.0"

// JSONRPCRequest is a generic JSON-RPC 2.0 request.
type JSONRPCRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
	ID      *string         `json:"id,omitempty"`
}

// JSONRPCResponse is a JSON-RPC 2.0 response.
type JSONRPCResponse struct {
	JSONRPC string        `json:"jsonrpc"`
	Result  any           `json:"result,omitempty"`
	Error   *RPCError     `json:"error,omitempty"`
	ID      *string       `json:"id"`
}

// RPCError represents a JSON-RPC error.
type RPCError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

// JSONRPCNotification is a server-initiated notification.
type JSONRPCNotification struct {
	JSONRPC string `json:"jsonrpc"`
	Method  string `json:"method"`
	Params  any    `json:"params,omitempty"`
}

func NewResponse(id *string, result any) JSONRPCResponse {
	return JSONRPCResponse{JSONRPC: JsonRPCVersion, Result: result, ID: id}
}

func NewError(id *string, code int, msg string) JSONRPCResponse {
	return JSONRPCResponse{
		JSONRPC: JsonRPCVersion,
		ID:      id,
		Error:   &RPCError{Code: code, Message: msg},
	}
}

func NewNotification(method string, params any) JSONRPCNotification {
	return JSONRPCNotification{JSONRPC: JsonRPCVersion, Method: method, Params: params}
}

// Standard error codes
const (
	ErrParseError      = -32700
	ErrInvalidRequest  = -32600
	ErrMethodNotFound  = -32601
	ErrInvalidParams   = -32602
	ErrInternal        = -32603
	ErrSessionNotFound = -32001
	ErrNotInitialized  = -32002
)

// Session params
type CreateSessionParams struct {
	SessionID  string `json:"session_id"`
	ProjectDir string `json:"project_dir"`
	Command    string `json:"command"`
}

type SendInputParams struct {
	SessionID string `json:"session_id"`
	Input     string `json:"input"`
}

type AttachSessionParams struct {
	SessionID string `json:"session_id"`
}

type DestroySessionParams struct {
	SessionID string `json:"session_id"`
}

// Session result
type SessionResult struct {
	ID         string `json:"id"`
	Command    string `json:"command"`
	ProjectDir string `json:"project_dir"`
	Alive      bool   `json:"alive"`
}

type OutputNotification struct {
	SessionID string `json:"session_id"`
	Data      string `json:"data"`
	Type      string `json:"type"` // "stream", "error", "exit"
}

// Filesystem params
type ReadDirParams struct {
	Path string `json:"path"`
}

type ReadFileParams struct {
	Path string `json:"path"`
}

type WriteFileParams struct {
	Path    string `json:"path"`
	Content string `json:"content"`
}

// Git params
type GitStatusParams struct {
	Path string `json:"path"`
}

type GitDiffParams struct {
	Path string `json:"path"`
}

type GitLogParams struct {
	Path  string `json:"path"`
	Count int    `json:"count,omitempty"`
}

// System params/results
type SystemInfoResult struct {
	OS       string `json:"os"`
	Arch     string `json:"arch"`
	Hostname string `json:"hostname"`
	CPUCount int    `json:"cpu_count"`
}
