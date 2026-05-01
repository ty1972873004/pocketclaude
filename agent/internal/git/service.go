package git

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
)

// Service provides Git operations.
type Service struct{}

// NewService creates a new Git service.
func NewService() *Service {
	return &Service{}
}

// StatusResult is the result of git status.
type StatusResult struct {
	Dir     string   `json:"dir"`
	Branch  string   `json:"branch"`
	Files   []string `json:"files"`
	Clean   bool     `json:"clean"`
	Raw     string   `json:"raw"`
}

// Status runs git status --porcelain in the given directory.
func (s *Service) Status(dir string) (*StatusResult, error) {
	// Get status
	raw, err := s.runGit(dir, "status", "--porcelain")
	if err != nil {
		return nil, fmt.Errorf("git status failed: %w", err)
	}

	// Get current branch
	branch, err := s.runGit(dir, "rev-parse", "--abbrev-ref", "HEAD")
	if err != nil {
		branch = "unknown"
	}

	files := []string{}
	if raw != "" {
		files = strings.Split(strings.TrimSpace(raw), "\n")
	}

	return &StatusResult{
		Dir:    dir,
		Branch: strings.TrimSpace(branch),
		Files:  files,
		Clean:  len(files) == 0,
		Raw:    raw,
	}, nil
}

// DiffResult is the result of git diff.
type DiffResult struct {
	Dir      string `json:"dir"`
	Diff     string `json:"diff"`
	HasChanges bool  `json:"has_changes"`
}

// Diff runs git diff in the given directory.
func (s *Service) Diff(dir string) (*DiffResult, error) {
	raw, err := s.runGit(dir, "diff")
	if err != nil {
		return nil, fmt.Errorf("git diff failed: %w", err)
	}

	return &DiffResult{
		Dir:        dir,
		Diff:       raw,
		HasChanges: raw != "",
	}, nil
}

// DiffCached runs git diff --cached (staged changes) in the given directory.
func (s *Service) DiffCached(dir string) (*DiffResult, error) {
	raw, err := s.runGit(dir, "diff", "--cached")
	if err != nil {
		return nil, fmt.Errorf("git diff --cached failed: %w", err)
	}

	return &DiffResult{
		Dir:        dir,
		Diff:       raw,
		HasChanges: raw != "",
	}, nil
}

// LogEntry represents a single git log entry.
type LogEntry struct {
	Hash    string `json:"hash"`
	Message string `json:"message"`
	Author  string `json:"author"`
	Date    string `json:"date"`
}

// LogResult is the result of git log.
type LogResult struct {
	Dir     string     `json:"dir"`
	Entries []LogEntry `json:"entries"`
	Count   int        `json:"count"`
}

// Log runs git log --oneline -20 in the given directory.
func (s *Service) Log(dir string) (*LogResult, error) {
	raw, err := s.runGit(dir, "log", "--pretty=format:%h|%s|%an|%ar", "-20")
	if err != nil {
		return nil, fmt.Errorf("git log failed: %w", err)
	}

	entries := []LogEntry{}
	if raw != "" {
		lines := strings.Split(strings.TrimSpace(raw), "\n")
		for _, line := range lines {
			parts := strings.SplitN(line, "|", 4)
			if len(parts) >= 4 {
				entries = append(entries, LogEntry{
					Hash:    parts[0],
					Message: parts[1],
					Author:  parts[2],
					Date:    parts[3],
				})
			} else if len(parts) >= 2 {
				entries = append(entries, LogEntry{
					Hash:    parts[0],
					Message: parts[1],
				})
			}
		}
	}

	return &LogResult{
		Dir:     dir,
		Entries: entries,
		Count:   len(entries),
	}, nil
}

// runGit executes a git command in the given directory.
func (s *Service) runGit(dir string, args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = dir

	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("%w: %s", err, string(output))
	}

	return string(output), nil
}

// HandleRPC handles a JSON-RPC request for git operations.
func (s *Service) HandleRPC(method string, params json.RawMessage) (interface{}, error) {
	switch method {
	case "git.status":
		var req struct {
			Dir string `json:"dir"`
		}
		if err := json.Unmarshal(params, &req); err != nil {
			return nil, fmt.Errorf("invalid params: %w", err)
		}
		return s.Status(req.Dir)

	case "git.diff":
		var req struct {
			Dir    string `json:"dir"`
			Cached bool   `json:"cached,omitempty"`
		}
		if err := json.Unmarshal(params, &req); err != nil {
			return nil, fmt.Errorf("invalid params: %w", err)
		}
		if req.Cached {
			return s.DiffCached(req.Dir)
		}
		return s.Diff(req.Dir)

	case "git.log":
		var req struct {
			Dir   string `json:"dir"`
			Count int    `json:"count,omitempty"`
		}
		if err := json.Unmarshal(params, &req); err != nil {
			return nil, fmt.Errorf("invalid params: %w", err)
		}
		return s.Log(req.Dir)

	default:
		return nil, fmt.Errorf("unknown git method: %s", method)
	}
}
