//go:build !windows
// +build !windows

package pty

import (
	"fmt"
	"os/exec"
	"strings"
)

const tmuxSessionPrefix = "pocketclaude_"

// HasTmux checks whether tmux is available on the system.
func HasTmux() bool {
	_, err := exec.LookPath("tmux")
	return err == nil
}

// CreateTmuxSession creates a new detached tmux session and returns its name.
func CreateTmuxSession(name, command, dir string) error {
	fullName := tmuxSessionPrefix + name
	args := []string{"new-session", "-d", "-s", fullName, "-x", "200", "-y", "50"}
	if dir != "" {
		args = append(args, "-c", dir)
	}
	args = append(args, command)

	out, err := exec.Command("tmux", args...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("tmux new-session failed: %w (%s)", err, strings.TrimSpace(string(out)))
	}
	return nil
}

// TmuxSessionExists checks whether a tmux session with the given name exists.
func TmuxSessionExists(name string) bool {
	fullName := tmuxSessionPrefix + name
	out, err := exec.Command("tmux", "has-session", "-t", fullName).CombinedOutput()
	return err == nil && strings.TrimSpace(string(out)) == ""
}

// CaptureTmuxOutput captures new output from a tmux session since the last read.
// It reads from the pane and clears the buffer.
func CaptureTmuxOutput(name string) ([]byte, error) {
	fullName := tmuxSessionPrefix + name
	out, err := exec.Command("tmux", "capture-pane", "-t", fullName, "-p", "-J").Output()
	if err != nil {
		return nil, fmt.Errorf("tmux capture-pane failed: %w", err)
	}
	return out, nil
}

// WriteTmuxInput sends text to a tmux session's pane.
func WriteTmuxInput(name, input string) error {
	fullName := tmuxSessionPrefix + name
	// Use send-keys with literal flag to avoid special character interpretation
	out, err := exec.Command("tmux", "send-keys", "-t", fullName, "-l", input).CombinedOutput()
	if err != nil {
		return fmt.Errorf("tmux send-keys failed: %w (%s)", err, strings.TrimSpace(string(out)))
	}
	return nil
}

// WriteTmuxKey sends a special key (e.g. Enter, C-c) to a tmux session.
func WriteTmuxKey(name, key string) error {
	fullName := tmuxSessionPrefix + name
	out, err := exec.Command("tmux", "send-keys", "-t", fullName, key).CombinedOutput()
	if err != nil {
		return fmt.Errorf("tmux send-keys failed: %w (%s)", err, strings.TrimSpace(string(out)))
	}
	return nil
}

// KillTmuxSession kills a tmux session.
func KillTmuxSession(name string) error {
	fullName := tmuxSessionPrefix + name
	out, err := exec.Command("tmux", "kill-session", "-t", fullName).CombinedOutput()
	if err != nil {
		return fmt.Errorf("tmux kill-session failed: %w (%s)", err, strings.TrimSpace(string(out)))
	}
	return nil
}

// ListTmuxSessions lists all pocketclaude tmux session names (without prefix).
func ListTmuxSessions() ([]string, error) {
	out, err := exec.Command("tmux", "list-sessions", "-F", "#{session_name}").Output()
	if err != nil {
		// No sessions is not an error
		if strings.Contains(err.Error(), "no server running") ||
			strings.Contains(err.Error(), "no sessions") {
			return nil, nil
		}
		return nil, fmt.Errorf("tmux list-sessions failed: %w", err)
	}

	var result []string
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, tmuxSessionPrefix) {
			result = append(result, strings.TrimPrefix(line, tmuxSessionPrefix))
		}
	}
	return result, nil
}

// ResizeTmuxSession changes the terminal dimensions of a tmux session.
func ResizeTmuxSession(name string, width, height int) error {
	fullName := tmuxSessionPrefix + name
	out, err := exec.Command("tmux", "resize-window", "-t", fullName, "-x", fmt.Sprintf("%d", width), "-y", fmt.Sprintf("%d", height)).CombinedOutput()
	if err != nil {
		return fmt.Errorf("tmux resize-window failed: %w (%s)", err, strings.TrimSpace(string(out)))
	}
	return nil
}
