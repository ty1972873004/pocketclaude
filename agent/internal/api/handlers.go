package api

import (
	"encoding/json"
	"fmt"
	"os"

	git "github.com/pocketclaude/agent/internal/git"
	process "github.com/pocketclaude/agent/internal/process"

	fs "github.com/pocketclaude/agent/internal/fs"
)

func (h *Handler) handleSessionCreate(req JSONRPCRequest) JSONRPCResponse {
	var params CreateSessionParams
	if err := json.Unmarshal(req.Params, &params); err != nil {
		return NewError(req.ID, ErrInvalidParams, "invalid params")
	}

	session, err := h.ptyManager.CreateSession(params.ProjectDir, params.Command)
	if err != nil {
		return NewError(req.ID, ErrInternal, err.Error())
	}

	return NewResponse(req.ID, SessionResult{
		ID:         session.ID,
		Command:    session.Command,
		ProjectDir: session.ProjectDir,
		Alive:      true,
	})
}

func (h *Handler) handleSessionList(req JSONRPCRequest) JSONRPCResponse {
	sessions := h.ptyManager.ListSessions()
	results := make([]SessionResult, 0, len(sessions))
	for _, s := range sessions {
		results = append(results, SessionResult{
			ID:         s.ID,
			Command:    s.Command,
			ProjectDir: s.ProjectDir,
			Alive:      s.IsAlive(),
		})
	}
	return NewResponse(req.ID, results)
}

func (h *Handler) handleSendInput(req JSONRPCRequest) JSONRPCResponse {
	var params SendInputParams
	if err := json.Unmarshal(req.Params, &params); err != nil {
		return NewError(req.ID, ErrInvalidParams, "invalid params")
	}

	session, ok := h.ptyManager.GetSession(params.SessionID)
	if !ok {
		return NewError(req.ID, ErrSessionNotFound, "session not found")
	}

	if err := session.WriteInput([]byte(params.Input + "\n")); err != nil {
		return NewError(req.ID, ErrInternal, err.Error())
	}

	return NewResponse(req.ID, map[string]bool{"success": true})
}

func (h *Handler) handleSessionDestroy(req JSONRPCRequest) JSONRPCResponse {
	var params DestroySessionParams
	if err := json.Unmarshal(req.Params, &params); err != nil {
		return NewError(req.ID, ErrInvalidParams, "invalid params")
	}

	if err := h.ptyManager.DestroySession(params.SessionID); err != nil {
		return NewError(req.ID, ErrSessionNotFound, err.Error())
	}

	return NewResponse(req.ID, map[string]bool{"success": true})
}

// dispatchServiceRPC delegates a method to the appropriate service HandleRPC.
func (h *Handler) dispatchServiceRPC(req JSONRPCRequest) (JSONRPCResponse, bool) {
	var handler func(string, json.RawMessage) (interface{}, error)

	switch {
	case hasPrefix(req.Method, "fs."):
		handler = h.fsService.HandleRPC
	case hasPrefix(req.Method, "git."):
		handler = h.gitService.HandleRPC
	case hasPrefix(req.Method, "system."):
		handler = h.procMonitor.HandleRPC
	case hasPrefix(req.Method, "plugin."):
		handler = h.pluginRegistry.HandleRPC
	default:
		return JSONRPCResponse{}, false
	}

	result, err := handler(req.Method, req.Params)
	if err != nil {
		return NewError(req.ID, ErrInternal, err.Error()), true
	}
	return NewResponse(req.ID, result), true
}

func hasPrefix(s, prefix string) bool {
	return len(s) >= len(prefix) && s[:len(prefix)] == prefix
}

// newDefaultServices creates default service instances for standalone use.
func newDefaultServices() (*fs.Service, *git.Service, *process.Monitor) {
	return fs.NewService(), git.NewService(), process.NewMonitor()
}

// ResolvePath resolves relative paths to absolute paths (for convenience).
func ResolvePath(path string) string {
	if path == "" {
		home, _ := os.UserHomeDir()
		return home
	}
	return path
}

// Compile-time interface check.
var _ = fmt.Sprintf
