package api

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"

	"github.com/pocketclaude/agent/internal/pty"
)

// Handler manages WebSocket API connections.
type Handler struct {
	ptyManager *pty.Manager
	upgrader   websocket.Upgrader
	clients    map[*websocket.Conn]bool
	broadcast  chan JSONRPCNotification
	mu         sync.Mutex
}

// NewHandler creates a new API handler.
func NewHandler(ptyMgr *pty.Manager) *Handler {
	h := &Handler{
		ptyManager: ptyMgr,
		upgrader:   websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }},
		clients:    make(map[*websocket.Conn]bool),
		broadcast:  make(chan JSONRPCNotification, 256),
	}

	// Start broadcast goroutine
	go h.broadcastLoop()

	// Wire PTY output to broadcast
	ptyMgr.SetOutputHandler(func(sessionID string, data []byte) {
		h.broadcast <- NewNotification("session.on_output", OutputNotification{
			SessionID: sessionID,
			Data:      string(data),
			Type:      "stream",
		})
	})

	return h
}

// ServeHTTP handles WebSocket upgrades and message routing.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	conn, err := h.upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[API] Upgrade failed: %v", err)
		return
	}
	defer conn.Close()

	h.mu.Lock()
	h.clients[conn] = true
	h.mu.Unlock()

	defer func() {
		h.mu.Lock()
		delete(h.clients, conn)
		h.mu.Unlock()
	}()

	log.Printf("[API] Client connected: %s", conn.RemoteAddr())

	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseNormalClosure) {
				log.Printf("[API] Read error: %v", err)
			}
			return
		}

		resp := h.HandleMessage(msg)
		if resp != nil {
			if err := conn.WriteJSON(resp); err != nil {
				log.Printf("[API] Write error: %v", err)
				return
			}
		}
	}
}

// HandleMessage processes a raw JSON-RPC message and returns the response.
// This is used both by WebSocket connections and relay-routed messages.
func (h *Handler) HandleMessage(raw []byte) *JSONRPCResponse {
	var req JSONRPCRequest
	if err := json.Unmarshal(raw, &req); err != nil {
		resp := NewError(nil, ErrParseError, "parse error")
		return &resp
	}

	if req.JSONRPC != JsonRPCVersion {
		resp := NewError(req.ID, ErrInvalidRequest, "invalid jsonrpc version")
		return &resp
	}

	var resp JSONRPCResponse

	switch req.Method {
	case "session.create":
		resp = h.handleSessionCreate(req)
	case "session.list":
		resp = h.handleSessionList(req)
	case "session.send_input":
		resp = h.handleSendInput(req)
	case "session.destroy":
		resp = h.handleSessionDestroy(req)
	case "fs.read_dir":
		resp = h.handleReadDir(req)
	case "fs.read_file":
		resp = h.handleReadFile(req)
	case "fs.write_file":
		resp = h.handleWriteFile(req)
	case "git.status":
		resp = h.handleGitStatus(req)
	case "git.diff":
		resp = h.handleGitDiff(req)
	case "git.log":
		resp = h.handleGitLog(req)
	case "system.info":
		resp = h.handleSystemInfo(req)
	default:
		resp = NewError(req.ID, ErrMethodNotFound, "method not found: "+req.Method)
	}

	// Only return response for requests (with ID), not notifications
	if req.ID != nil {
		return &resp
	}
	return nil
}

// BroadcastNotification sends a notification to all connected clients.
func (h *Handler) BroadcastNotification(method string, params any) {
	h.broadcast <- NewNotification(method, params)
}

func (h *Handler) broadcastLoop() {
	for msg := range h.broadcast {
		h.mu.Lock()
		for conn := range h.clients {
			if err := conn.WriteJSON(msg); err != nil {
				log.Printf("[API] Broadcast error: %v", err)
				conn.Close()
				delete(h.clients, conn)
			}
		}
		h.mu.Unlock()
	}
}
