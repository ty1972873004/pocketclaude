package pty

import (
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"runtime"
	"sync"
	"time"

	"github.com/google/uuid"
)

// Session represents a running PTY session.
type Session struct {
	ID          string
	Command     string
	ProjectDir  string
	Process     *os.Process
	PtyFile     *os.File // Unix: ptmx file; Windows: nil
	WinSession  *WindowsSession
	Output      chan []byte
	Done        chan struct{}
	StartTime   time.Time
	mu          sync.Mutex
	closed      bool
}

// Manager manages PTY sessions.
type Manager struct {
	sessions map[string]*Session
	mu       sync.RWMutex
	onOutput func(sessionID string, data []byte)
}

// NewManager creates a new PTY manager.
func NewManager() *Manager {
	return &Manager{
		sessions: make(map[string]*Session),
	}
}

// SetOutputHandler sets the callback for session output.
func (m *Manager) SetOutputHandler(handler func(sessionID string, data []byte)) {
	m.onOutput = handler
}

// CreateSession creates and starts a new PTY session.
func (m *Manager) CreateSession(projectDir string, command string) (*Session, error) {
	if command == "" {
		command = "claude"
	}

	id := uuid.New().String()

	session := &Session{
		ID:         id,
		Command:    command,
		ProjectDir: projectDir,
		Output:     make(chan []byte, 1024),
		Done:       make(chan struct{}),
		StartTime:  time.Now(),
	}

	if runtime.GOOS == "windows" {
		if err := m.startWindowsSession(session); err != nil {
			return nil, err
		}
	} else {
		if err := m.startUnixSession(session); err != nil {
			return nil, err
		}
	}

	m.mu.Lock()
	m.sessions[id] = session
	m.mu.Unlock()

	// Start reading output
	go m.readOutput(session)

	log.Printf("[PTY] Session created: %s (command=%s, dir=%s)", id, command, projectDir)
	return session, nil
}

func (m *Manager) startUnixSession(session *Session) error {
	cmd := exec.Command(session.Command)
	cmd.Dir = session.ProjectDir
	cmd.Env = append(os.Environ(), "TERM=xterm-256color")

	ptmx, err := startPty(cmd)
	if err != nil {
		return fmt.Errorf("failed to start PTY: %w", err)
	}

	session.PtyFile = ptmx
	session.Process = cmd.Process

	return nil
}

func (m *Manager) startWindowsSession(session *Session) error {
	winSess, err := NewWindowsSession(session.Command, session.ProjectDir, 120, 40)
	if err != nil {
		return fmt.Errorf("failed to create Windows ConPTY: %w", err)
	}
	session.WinSession = winSess
	return nil
}

func (m *Manager) readOutput(session *Session) {
	defer close(session.Output)
	defer close(session.Done)

	buf := make([]byte, 4096)

	var reader io.Reader
	if runtime.GOOS == "windows" && session.WinSession != nil {
		reader = session.WinSession
	} else if session.PtyFile != nil {
		reader = session.PtyFile
	} else {
		log.Printf("[PTY] Session %s: no reader available", session.ID)
		return
	}

	for {
		n, err := reader.Read(buf)
		if n > 0 {
			data := make([]byte, n)
			copy(data, buf[:n])

			// Send to output channel (non-blocking)
			select {
			case session.Output <- data:
			default:
				// Buffer full, drop oldest
				log.Printf("[PTY] Session %s: output buffer full, dropping data", session.ID)
			}

			// Forward to output handler
			if m.onOutput != nil {
				m.onOutput(session.ID, data)
			}
		}
		if err != nil {
			if err != io.EOF {
				log.Printf("[PTY] Session %s: read error: %v", session.ID, err)
			}
			return
		}
	}
}

// WriteInput writes data to the session's PTY stdin.
func (s *Session) WriteInput(data []byte) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.closed {
		return fmt.Errorf("session is closed")
	}

	var writer io.Writer
	if runtime.GOOS == "windows" && s.WinSession != nil {
		writer = s.WinSession
	} else if s.PtyFile != nil {
		writer = s.PtyFile
	} else {
		return fmt.Errorf("no writer available for session")
	}

	_, err := writer.Write(data)
	return err
}

// Resize changes the terminal dimensions (Unix only, no-op on Windows currently).
func (s *Session) Resize(rows, cols uint16) error {
	if runtime.GOOS == "windows" {
		if s.WinSession != nil {
			return s.WinSession.Resize(int(cols), int(rows))
		}
		return nil
	}
	// Unix PTY resize would use pty.Setsize
	// This is a placeholder - the creack/pty package supports this
	return nil
}

// GetSession returns a session by ID.
func (m *Manager) GetSession(id string) (*Session, bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	s, ok := m.sessions[id]
	return s, ok
}

// ListSessions returns all active sessions.
func (m *Manager) ListSessions() []*Session {
	m.mu.RLock()
	defer m.mu.RUnlock()

	result := make([]*Session, 0, len(m.sessions))
	for _, s := range m.sessions {
		result = append(result, s)
	}
	return result
}

// DestroySession kills and removes a session.
func (m *Manager) DestroySession(id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	session, ok := m.sessions[id]
	if !ok {
		return fmt.Errorf("session not found: %s", id)
	}

	session.mu.Lock()
	defer session.mu.Unlock()

	if session.closed {
		delete(m.sessions, id)
		return nil
	}

	session.closed = true

	// Kill the process
	if session.Process != nil {
		if err := session.Process.Kill(); err != nil {
			log.Printf("[PTY] Failed to kill process for session %s: %v", id, err)
		}
	}

	// Close PTY file
	if session.PtyFile != nil {
		session.PtyFile.Close()
	}

	// Close Windows session
	if session.WinSession != nil {
		session.WinSession.Close()
	}

	delete(m.sessions, id)
	log.Printf("[PTY] Session destroyed: %s", id)
	return nil
}

// CloseAll destroys all sessions.
func (m *Manager) CloseAll() {
	m.mu.Lock()
	defer m.mu.Unlock()

	for id, session := range m.sessions {
		session.mu.Lock()
		session.closed = true
		if session.Process != nil {
			session.Process.Kill()
		}
		if session.PtyFile != nil {
			session.PtyFile.Close()
		}
		if session.WinSession != nil {
			session.WinSession.Close()
		}
		session.mu.Unlock()
		delete(m.sessions, id)
		log.Printf("[PTY] Session destroyed (shutdown): %s", id)
	}
}

// IsAlive checks if the session process is still running.
func (s *Session) IsAlive() bool {
	if s.Process == nil {
		// On Windows, WinSession has no separate Process; assume alive if not closed
		if runtime.GOOS == "windows" && s.WinSession != nil {
			s.mu.Lock()
			defer s.mu.Unlock()
			return !s.closed
		}
		return false
	}
	// On Unix, try signal 0 to check if process exists
	if runtime.GOOS != "windows" {
		err := s.Process.Signal(os.Signal(nil))
		return err == nil
	}
	// On Windows with a Process, just check closed flag
	s.mu.Lock()
	defer s.mu.Unlock()
	return !s.closed
}

// SessionInfo returns serializable info about the session.
type SessionInfo struct {
	ID         string    `json:"id"`
	Command    string    `json:"command"`
	ProjectDir string    `json:"project_dir"`
	Alive      bool      `json:"alive"`
	StartTime  time.Time `json:"start_time"`
}

// Info returns serializable info about the session.
func (s *Session) Info() SessionInfo {
	return SessionInfo{
		ID:         s.ID,
		Command:    s.Command,
		ProjectDir: s.ProjectDir,
		Alive:      s.IsAlive(),
		StartTime:  s.StartTime,
	}
}
