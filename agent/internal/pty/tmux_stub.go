//go:build windows
// +build windows

package pty

import "fmt"

// HasTmux always returns false on Windows.
func HasTmux() bool { return false }

func CreateTmuxSession(name, command, dir string) error {
	return fmt.Errorf("tmux not available on Windows")
}

func TmuxSessionExists(name string) bool { return false }

func CaptureTmuxOutput(name string) ([]byte, error) {
	return nil, fmt.Errorf("tmux not available on Windows")
}

func WriteTmuxInput(name, input string) error {
	return fmt.Errorf("tmux not available on Windows")
}

func WriteTmuxKey(name, key string) error {
	return fmt.Errorf("tmux not available on Windows")
}

func KillTmuxSession(name string) error {
	return fmt.Errorf("tmux not available on Windows")
}

func ListTmuxSessions() ([]string, error) {
	return nil, nil
}

func ResizeTmuxSession(name string, width, height int) error {
	return fmt.Errorf("tmux not available on Windows")
}
