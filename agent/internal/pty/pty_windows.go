//go:build windows
// +build windows

package pty

import (
	"fmt"
	"os"
	"os/exec"

	conpty "github.com/UserExistsError/conpty"
)

func startPty(cmd *exec.Cmd) (*os.File, error) {
	return nil, fmt.Errorf("Windows uses NewWindowsSession, not startPty")
}

// WindowsSession wraps a conpty session for Windows.
type WindowsSession struct {
	conpty *conpty.ConPty
}

// NewWindowsSession creates a new ConPTY session on Windows.
func NewWindowsSession(command string, dir string, width, height int) (*WindowsSession, error) {
	opts := []conpty.ConPtyOption{
		conpty.ConPtyDimensions(width, height),
	}
	if dir != "" {
		opts = append(opts, conpty.ConPtyWorkDir(dir))
	}

	cpty, err := conpty.Start(command, opts...)
	if err != nil {
		return nil, fmt.Errorf("failed to start ConPTY: %w", err)
	}

	return &WindowsSession{conpty: cpty}, nil
}

// Read reads output from the ConPTY.
func (s *WindowsSession) Read(b []byte) (int, error) {
	return s.conpty.Read(b)
}

// Write writes input to the ConPTY.
func (s *WindowsSession) Write(b []byte) (int, error) {
	return s.conpty.Write(b)
}

// Close closes the ConPTY.
func (s *WindowsSession) Close() error {
	return s.conpty.Close()
}

// Resize resizes the ConPTY.
func (s *WindowsSession) Resize(width, height int) error {
	return s.conpty.Resize(width, height)
}
