package api

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"
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

func (h *Handler) handleReadDir(req JSONRPCRequest) JSONRPCResponse {
	var params ReadDirParams
	if err := json.Unmarshal(req.Params, &params); err != nil {
		return NewError(req.ID, ErrInvalidParams, "invalid params")
	}

	path := params.Path
	if path == "" {
		path, _ = os.UserHomeDir()
	}

	entries, err := os.ReadDir(path)
	if err != nil {
		return NewError(req.ID, ErrInternal, err.Error())
	}

	type DirEntry struct {
		Name  string `json:"name"`
		IsDir bool   `json:"is_dir"`
		Size  int64  `json:"size,omitempty"`
	}

	result := make([]DirEntry, 0, len(entries))
	for _, e := range entries {
		info, _ := e.Info()
		result = append(result, DirEntry{
			Name:  e.Name(),
			IsDir: e.IsDir(),
			Size:  info.Size(),
		})
	}

	return NewResponse(req.ID, map[string]any{"path": path, "entries": result})
}

func (h *Handler) handleReadFile(req JSONRPCRequest) JSONRPCResponse {
	var params ReadFileParams
	if err := json.Unmarshal(req.Params, &params); err != nil {
		return NewError(req.ID, ErrInvalidParams, "invalid params")
	}

	data, err := os.ReadFile(params.Path)
	if err != nil {
		return NewError(req.ID, ErrInternal, err.Error())
	}

	return NewResponse(req.ID, map[string]string{"path": params.Path, "content": string(data)})
}

func (h *Handler) handleWriteFile(req JSONRPCRequest) JSONRPCResponse {
	var params WriteFileParams
	if err := json.Unmarshal(req.Params, &params); err != nil {
		return NewError(req.ID, ErrInvalidParams, "invalid params")
	}

	if err := os.WriteFile(params.Path, []byte(params.Content), 0644); err != nil {
		return NewError(req.ID, ErrInternal, err.Error())
	}

	return NewResponse(req.ID, map[string]bool{"success": true})
}

func (h *Handler) handleGitStatus(req JSONRPCRequest) JSONRPCResponse {
	var params GitStatusParams
	if err := json.Unmarshal(req.Params, &params); err != nil {
		return NewError(req.ID, ErrInvalidParams, "invalid params")
	}

	out, err := exec.Command("git", "-C", params.Path, "status", "--porcelain").Output()
	if err != nil {
		return NewError(req.ID, ErrInternal, err.Error())
	}

	return NewResponse(req.ID, map[string]string{"status": string(out)})
}

func (h *Handler) handleGitDiff(req JSONRPCRequest) JSONRPCResponse {
	var params GitDiffParams
	if err := json.Unmarshal(req.Params, &params); err != nil {
		return NewError(req.ID, ErrInvalidParams, "invalid params")
	}

	out, err := exec.Command("git", "-C", params.Path, "diff").Output()
	if err != nil {
		return NewError(req.ID, ErrInternal, err.Error())
	}

	return NewResponse(req.ID, map[string]string{"diff": string(out)})
}

func (h *Handler) handleGitLog(req JSONRPCRequest) JSONRPCResponse {
	var params GitLogParams
	if err := json.Unmarshal(req.Params, &params); err != nil {
		return NewError(req.ID, ErrInvalidParams, "invalid params")
	}

	count := params.Count
	if count <= 0 {
		count = 20
	}

	out, err := exec.Command("git", "-C", params.Path, "log", fmt.Sprintf("-%d", count), "--oneline").Output()
	if err != nil {
		return NewError(req.ID, ErrInternal, err.Error())
	}

	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	return NewResponse(req.ID, map[string]any{"log": lines})
}

func (h *Handler) handleSystemInfo(req JSONRPCRequest) JSONRPCResponse {
	hostname, _ := os.Hostname()
	info := SystemInfoResult{
		OS:       runtime.GOOS,
		Arch:     runtime.GOARCH,
		Hostname: hostname,
		CPUCount: runtime.NumCPU(),
	}
	return NewResponse(req.ID, info)
}
