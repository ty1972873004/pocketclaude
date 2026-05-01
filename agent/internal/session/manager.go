package session

import (
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/pocketclaude/agent/internal/pty"
)

// Manager manages CLI sessions through the PTY subsystem.
type Manager struct {
	ptyManager *pty.Manager
	outputSubs map[string][]chan []byte // sessionID -> subscribers
	mu         sync.RWMutex
}

// NewManager creates a new session manager.
func NewManager(ptyMgr *pty.Manager) *Manager {
	m := &Manager{
		ptyManager: ptyMgr,
		outputSubs: make(map[string][]chan []byte),
	}

	// Set up PTY output handler to broadcast to subscribers
	ptyMgr.SetOutputHandler(func(sessionID string, data []byte) {
		m.broadcastOutput(sessionID, data)
	})

	return m
}

// CreateSessionRequest is the input for creating a session.
type CreateSessionRequest struct {
	ProjectDir string `json:"project_dir"`
	Command    string `json:"command"`
}

// SessionInfo represents a session's metadata.
type SessionInfo struct {
	ID         string    `json:"id"`
	Command    string    `json:"command"`
	ProjectDir string    `json:"project_dir"`
	Alive      bool      `json:"alive"`
	StartTime  time.Time `json:"start_time"`
}

// Create creates a new PTY session.
func (m *Manager) Create(req CreateSessionRequest) (*SessionInfo, error) {
	if req.ProjectDir == "" {
		return nil, fmt.Errorf("project_dir is required")
	}

	sess, err := m.ptyManager.CreateSession(req.ProjectDir, req.Command)
	if err != nil {
		return nil, fmt.Errorf("failed to create session: %w", err)
	}

	info := sess.Info()
	return &SessionInfo{
		ID:         info.ID,
		Command:    info.Command,
		ProjectDir: info.ProjectDir,
		Alive:      info.Alive,
		StartTime:  info.StartTime,
	}, nil
}

// List returns all active sessions.
func (m *Manager) List() []SessionInfo {
	sessions := m.ptyManager.ListSessions()
	result := make([]SessionInfo, 0, len(sessions))
	for _, s := range sessions {
		info := s.Info()
		result = append(result, SessionInfo{
			ID:         info.ID,
			Command:    info.Command,
			ProjectDir: info.ProjectDir,
			Alive:      info.Alive,
			StartTime:  info.StartTime,
		})
	}
	return result
}

// Get returns info about a specific session.
func (m *Manager) Get(id string) (*SessionInfo, error) {
	sess, ok := m.ptyManager.GetSession(id)
	if !ok {
		return nil, fmt.Errorf("session not found: %s", id)
	}
	info := sess.Info()
	return &SessionInfo{
		ID:         info.ID,
		Command:    info.Command,
		ProjectDir: info.ProjectDir,
		Alive:      info.Alive,
		StartTime:  info.StartTime,
	}, nil
}

// SendInput writes data to a session's PTY.
func (m *Manager) SendInput(sessionID string, data []byte) error {
	sess, ok := m.ptyManager.GetSession(sessionID)
	if !ok {
		return fmt.Errorf("session not found: %s", sessionID)
	}
	return sess.WriteInput(data)
}

// SendInputString writes a string to a session's PTY.
func (m *Manager) SendInputString(sessionID string, text string) error {
	return m.SendInput(sessionID, []byte(text))
}

// Destroy kills and removes a session.
func (m *Manager) Destroy(sessionID string) error {
	// Clean up subscribers
	m.mu.Lock()
	if subs, ok := m.outputSubs[sessionID]; ok {
		for _, ch := range subs {
			close(ch)
		}
		delete(m.outputSubs, sessionID)
	}
	m.mu.Unlock()

	return m.ptyManager.DestroySession(sessionID)
}

// SubscribeOutput returns a channel that receives session output.
func (m *Manager) SubscribeOutput(sessionID string) (<-chan []byte, error) {
	sess, ok := m.ptyManager.GetSession(sessionID)
	if !ok {
		return nil, fmt.Errorf("session not found: %s", sessionID)
	}
	_ = sess // just verifying it exists

	ch := make(chan []byte, 256)

	m.mu.Lock()
	m.outputSubs[sessionID] = append(m.outputSubs[sessionID], ch)
	m.mu.Unlock()

	return ch, nil
}

// UnsubscribeOutput removes an output subscriber.
func (m *Manager) UnsubscribeOutput(sessionID string, ch <-chan []byte) {
	m.mu.Lock()
	defer m.mu.Unlock()

	subs, ok := m.outputSubs[sessionID]
	if !ok {
		return
	}

	for i, sub := range subs {
		if sub == ch {
			// Remove from slice
			m.outputSubs[sessionID] = append(subs[:i], subs[i+1:]...)
			close(sub)
			break
		}
	}

	if len(m.outputSubs[sessionID]) == 0 {
		delete(m.outputSubs, sessionID)
	}
}

// broadcastOutput sends output data to all subscribers of a session.
func (m *Manager) broadcastOutput(sessionID string, data []byte) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	subs, ok := m.outputSubs[sessionID]
	if !ok {
		return
	}

	for _, ch := range subs {
		select {
		case ch <- data:
		default:
			log.Printf("[Session] Dropping output for subscriber (buffer full), session=%s", sessionID)
		}
	}
}

// HandleRPC handles a JSON-RPC request for session management.
func (m *Manager) HandleRPC(method string, params json.RawMessage) (interface{}, error) {
	switch method {
	case "session.create":
		var req CreateSessionRequest
		if err := json.Unmarshal(params, &req); err != nil {
			return nil, fmt.Errorf("invalid params: %w", err)
		}
		return m.Create(req)

	case "session.list":
		return m.List(), nil

	case "session.attach":
		var req struct {
			SessionID string `json:"session_id"`
		}
		if err := json.Unmarshal(params, &req); err != nil {
			return nil, fmt.Errorf("invalid params: %w", err)
		}
		return m.SubscribeOutput(req.SessionID)

	case "session.send_input":
		var req struct {
			SessionID string `json:"session_id"`
			Data      string `json:"data"`
		}
		if err := json.Unmarshal(params, &req); err != nil {
			return nil, fmt.Errorf("invalid params: %w", err)
		}
		if err := m.SendInputString(req.SessionID, req.Data); err != nil {
			return nil, err
		}
		return map[string]string{"status": "ok"}, nil

	case "session.destroy":
		var req struct {
			SessionID string `json:"session_id"`
		}
		if err := json.Unmarshal(params, &req); err != nil {
			return nil, fmt.Errorf("invalid params: %w", err)
		}
		if err := m.Destroy(req.SessionID); err != nil {
			return nil, err
		}
		return map[string]string{"status": "ok"}, nil

	default:
		return nil, fmt.Errorf("unknown session method: %s", method)
	}
}

// CloseAll destroys all sessions.
func (m *Manager) CloseAll() {
	m.mu.Lock()
	for id, subs := range m.outputSubs {
		for _, ch := range subs {
			close(ch)
		}
		delete(m.outputSubs, id)
	}
	m.mu.Unlock()

	m.ptyManager.CloseAll()
}
