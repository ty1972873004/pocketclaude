package fs

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Service provides file system operations.
type Service struct {
	allowedDirs []string // if empty, all dirs are allowed
}

// NewService creates a new file system service.
func NewService() *Service {
	return &Service{}
}

// SetAllowedDirs restricts file operations to specific directories.
func (s *Service) SetAllowedDirs(dirs []string) {
	s.allowedDirs = dirs
}

// DirEntry represents a directory entry.
type DirEntry struct {
	Name    string      `json:"name"`
	Path    string      `json:"path"`
	IsDir   bool        `json:"is_dir"`
	Size    int64       `json:"size,omitempty"`
	ModTime time.Time   `json:"mod_time"`
	Mode    string      `json:"mode"`
}

// ReadDirResult is the result of a read_dir operation.
type ReadDirResult struct {
	Path    string     `json:"path"`
	Entries []DirEntry `json:"entries"`
}

// ReadDir lists the contents of a directory.
func (s *Service) ReadDir(path string) (*ReadDirResult, error) {
	path = s.resolvePath(path)

	if err := s.checkAccess(path); err != nil {
		return nil, err
	}

	entries, err := os.ReadDir(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read directory: %w", err)
	}

	result := &ReadDirResult{
		Path:    path,
		Entries: make([]DirEntry, 0, len(entries)),
	}

	for _, entry := range entries {
		info, err := entry.Info()
		if err != nil {
			continue // skip entries we can't stat
		}

		result.Entries = append(result.Entries, DirEntry{
			Name:    entry.Name(),
			Path:    filepath.Join(path, entry.Name()),
			IsDir:   entry.IsDir(),
			Size:    info.Size(),
			ModTime: info.ModTime(),
			Mode:    info.Mode().String(),
		})
	}

	return result, nil
}

// ReadFileResult is the result of a read_file operation.
type ReadFileResult struct {
	Path    string `json:"path"`
	Content string `json:"content"`
	Size    int    `json:"size"`
}

// ReadFile reads the contents of a file.
func (s *Service) ReadFile(path string) (*ReadFileResult, error) {
	path = s.resolvePath(path)

	if err := s.checkAccess(path); err != nil {
		return nil, err
	}

	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read file: %w", err)
	}

	return &ReadFileResult{
		Path:    path,
		Content: string(data),
		Size:    len(data),
	}, nil
}

// WriteFileRequest is the input for a write_file operation.
type WriteFileRequest struct {
	Path    string `json:"path"`
	Content string `json:"content"`
}

// WriteFileResult is the result of a write_file operation.
type WriteFileResult struct {
	Path string `json:"path"`
	Size int    `json:"size"`
}

// WriteFile writes content to a file.
func (s *Service) WriteFile(req WriteFileRequest) (*WriteFileResult, error) {
	path := s.resolvePath(req.Path)

	if err := s.checkAccess(path); err != nil {
		return nil, err
	}

	// Ensure parent directory exists
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create parent directory: %w", err)
	}

	data := []byte(req.Content)
	if err := os.WriteFile(path, data, 0644); err != nil {
		return nil, fmt.Errorf("failed to write file: %w", err)
	}

	return &WriteFileResult{
		Path: path,
		Size: len(data),
	}, nil
}

// resolvePath resolves relative paths to absolute paths.
func (s *Service) resolvePath(path string) string {
	if filepath.IsAbs(path) {
		return filepath.Clean(path)
	}
	abs, err := filepath.Abs(path)
	if err != nil {
		return path
	}
	return abs
}

// checkAccess verifies the path is within allowed directories.
func (s *Service) checkAccess(path string) error {
	if len(s.allowedDirs) == 0 {
		return nil // no restrictions
	}

	absPath, err := filepath.Abs(path)
	if err != nil {
		return fmt.Errorf("cannot resolve path: %w", err)
	}

	for _, dir := range s.allowedDirs {
		absDir, err := filepath.Abs(dir)
		if err != nil {
			continue
		}
		if strings.HasPrefix(absPath, absDir) {
			return nil
		}
	}

	return fmt.Errorf("access denied: path outside allowed directories")
}

// HandleRPC handles a JSON-RPC request for file system operations.
func (s *Service) HandleRPC(method string, params json.RawMessage) (interface{}, error) {
	switch method {
	case "fs.read_dir":
		var req struct {
			Path string `json:"path"`
		}
		if err := json.Unmarshal(params, &req); err != nil {
			return nil, fmt.Errorf("invalid params: %w", err)
		}
		return s.ReadDir(req.Path)

	case "fs.read_file":
		var req struct {
			Path string `json:"path"`
		}
		if err := json.Unmarshal(params, &req); err != nil {
			return nil, fmt.Errorf("invalid params: %w", err)
		}
		return s.ReadFile(req.Path)

	case "fs.write_file":
		var req WriteFileRequest
		if err := json.Unmarshal(params, &req); err != nil {
			return nil, fmt.Errorf("invalid params: %w", err)
		}
		return s.WriteFile(req)

	default:
		return nil, fmt.Errorf("unknown fs method: %s", method)
	}
}
