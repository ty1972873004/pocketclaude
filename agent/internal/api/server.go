package api

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"

	git "github.com/pocketclaude/agent/internal/git"
	process "github.com/pocketclaude/agent/internal/process"
	plugin "github.com/pocketclaude/agent/internal/plugin"
	pty "github.com/pocketclaude/agent/internal/pty"

	fs "github.com/pocketclaude/agent/internal/fs"
)

// Handler manages WebSocket API connections.
type Handler struct {
	ptyManager    *pty.Manager
	fsService     *fs.Service
	gitService    *git.Service
	procMonitor   *process.Monitor
	pluginRegistry *plugin.Registry
	upgrader    websocket.Upgrader
	clients     map[*websocket.Conn]bool
	broadcast   chan JSONRPCNotification
	mu          sync.Mutex
}

// NewHandler creates a new API handler with default service instances.
func NewHandler(ptyMgr *pty.Manager) *Handler {
	fsSvc, gitSvc, mon := newDefaultServices()
	return NewHandlerWithServices(ptyMgr, fsSvc, gitSvc, mon, plugin.NewRegistry())
}

// NewHandlerWithServices creates an API handler with explicit service dependencies.
func NewHandlerWithServices(ptyMgr *pty.Manager, fsSvc *fs.Service, gitSvc *git.Service, mon *process.Monitor, pluginReg *plugin.Registry) *Handler {
	h := &Handler{
		ptyManager:     ptyMgr,
		fsService:      fsSvc,
		gitService:     gitSvc,
		procMonitor:    mon,
		pluginRegistry: pluginReg,
		upgrader:    websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }},
		clients:     make(map[*websocket.Conn]bool),
		broadcast:   make(chan JSONRPCNotification, 256),
	}

	go h.broadcastLoop()

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

	// Try session handlers first (direct PTY operations)
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
	default:
		// Delegate to service-layer HandleRPC
		if found, ok := h.dispatchServiceRPC(req); ok {
			resp = found
		} else {
			resp = NewError(req.ID, ErrMethodNotFound, "method not found: "+req.Method)
		}
	}

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
