package pty

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// StoredSession is the persisted metadata for a session.
type StoredSession struct {
	ID          string    `json:"id"`
	Command     string    `json:"command"`
	ProjectDir  string    `json:"project_dir"`
	UsesTmux    bool      `json:"uses_tmux"`
	CreatedAt   time.Time `json:"created_at"`
	LastSeenAt  time.Time `json:"last_seen_at"`
}

// SessionStore persists session metadata to disk.
type SessionStore struct {
	mu       sync.Mutex
	path     string
	sessions map[string]*StoredSession
}

// NewSessionStore creates a session store backed by the given file path.
func NewSessionStore(configDir string) *SessionStore {
	path := filepath.Join(configDir, "sessions.json")
	return &SessionStore{
		path:     path,
		sessions: make(map[string]*StoredSession),
	}
}

// Load reads persisted sessions from disk.
func (s *SessionStore) Load() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	data, err := os.ReadFile(s.path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}

	if len(data) == 0 {
		return nil
	}

	var list []*StoredSession
	if err := json.Unmarshal(data, &list); err != nil {
		return err
	}

	s.sessions = make(map[string]*StoredSession, len(list))
	for _, ss := range list {
		s.sessions[ss.ID] = ss
	}
	return nil
}

// Save writes current sessions to disk.
func (s *SessionStore) Save() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	return s.writeLocked()
}

func (s *SessionStore) writeLocked() error {
	list := make([]*StoredSession, 0, len(s.sessions))
	for _, ss := range s.sessions {
		list = append(list, ss)
	}

	data, err := json.MarshalIndent(list, "", "  ")
	if err != nil {
		return err
	}

	dir := filepath.Dir(s.path)
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}

	return os.WriteFile(s.path, data, 0600)
}

// Put adds or updates a stored session.
func (s *SessionStore) Put(ss *StoredSession) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	ss.LastSeenAt = time.Now()
	s.sessions[ss.ID] = ss
	return s.writeLocked()
}

// Get returns a stored session by ID.
func (s *SessionStore) Get(id string) (*StoredSession, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	ss, ok := s.sessions[id]
	return ss, ok
}

// Delete removes a stored session.
func (s *SessionStore) Delete(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	delete(s.sessions, id)
	return s.writeLocked()
}

// List returns all stored sessions.
func (s *SessionStore) List() []*StoredSession {
	s.mu.Lock()
	defer s.mu.Unlock()

	result := make([]*StoredSession, 0, len(s.sessions))
	for _, ss := range s.sessions {
		result = append(result, ss)
	}
	return result
}
