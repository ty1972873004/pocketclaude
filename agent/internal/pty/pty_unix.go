//go:build !windows
// +build !windows

package pty

import (
	"os"
	"os/exec"

	"github.com/creack/pty"
)

// startPty starts a pseudo-terminal on Unix systems using /dev/ptmx.
func startPty(cmd *exec.Cmd) (ptyFile *os.File, err error) {
	ptmx, err := pty.Start(cmd)
	if err != nil {
		return nil, err
	}
	return ptmx, nil
}

// WindowsSession is a no-op stub on non-Windows platforms.
type WindowsSession struct{}

func (s *WindowsSession) Read(b []byte) (int, error)  { return 0, nil }
func (s *WindowsSession) Write(b []byte) (int, error) { return 0, nil }
func (s *WindowsSession) Close() error                { return nil }
func (s *WindowsSession) Resize(width, height int) error { return nil }

// NewWindowsSession should never be called on non-Windows.
func NewWindowsSession(command string, dir string, width, height int) (*WindowsSession, error) {
	return nil, nil
}
