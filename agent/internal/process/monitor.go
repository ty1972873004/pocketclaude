package process

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"runtime"
	"time"
)

// SystemInfo contains system information.
type SystemInfo struct {
	OS        string `json:"os"`
	Arch      string `json:"arch"`
	Hostname  string `json:"hostname"`
	GoVersion string `json:"go_version"`
	NumCPU    int    `json:"num_cpu"`
	MemStats  MemInfo `json:"mem_stats"`
	Timestamp string `json:"timestamp"`
}

// MemInfo contains memory statistics.
type MemInfo struct {
	Alloc      uint64 `json:"alloc_mb"`
	TotalAlloc uint64 `json:"total_alloc_mb"`
	Sys        uint64 `json:"sys_mb"`
	NumGC      uint32 `json:"num_gc"`
}

// Monitor provides system and process monitoring.
type Monitor struct {
	startTime time.Time
}

// NewMonitor creates a new process monitor.
func NewMonitor() *Monitor {
	return &Monitor{
		startTime: time.Now(),
	}
}

// GetSystemInfo returns current system information.
func (m *Monitor) GetSystemInfo() *SystemInfo {
	var memStats runtime.MemStats
	runtime.ReadMemStats(&memStats)

	hostname, _ := os.Hostname()

	return &SystemInfo{
		OS:        runtime.GOOS,
		Arch:      runtime.GOARCH,
		Hostname:  hostname,
		GoVersion: runtime.Version(),
		NumCPU:    runtime.NumCPU(),
		MemStats: MemInfo{
			Alloc:      memStats.Alloc / 1024 / 1024,
			TotalAlloc: memStats.TotalAlloc / 1024 / 1024,
			Sys:        memStats.Sys / 1024 / 1024,
			NumGC:      memStats.NumGC,
		},
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	}
}

// Uptime returns how long the agent has been running.
func (m *Monitor) Uptime() time.Duration {
	return time.Since(m.startTime)
}

// ProcessInfo represents information about a running process.
type ProcessInfo struct {
	PID     int       `json:"pid"`
	Name    string    `json:"name"`
	Command string    `json:"command"`
	Running bool      `json:"running"`
	Started time.Time `json:"started"`
}

// FindClaudeCode looks for running Claude Code processes.
func (m *Monitor) FindClaudeCode() ([]ProcessInfo, error) {
	// This is platform-specific and simplified
	// On Linux/Mac: use ps aux | grep claude
	// On Windows: use tasklist
	var processes []ProcessInfo

	switch runtime.GOOS {
	case "windows":
		processes = m.findProcessesWindows()
	default:
		processes = m.findProcessesUnix()
	}

	return processes, nil
}

func (m *Monitor) findProcessesUnix() []ProcessInfo {
	// Simplified: in a real implementation we'd parse ps output
	log.Printf("[Monitor] Scanning for Claude Code processes (Unix)")
	return nil
}

func (m *Monitor) findProcessesWindows() []ProcessInfo {
	// Simplified: in a real implementation we'd use tasklist or WMI
	log.Printf("[Monitor] Scanning for Claude Code processes (Windows)")
	return nil
}

// HealthCheck returns the health status of the agent.
func (m *Monitor) HealthCheck() map[string]interface{} {
	return map[string]interface{}{
		"status":    "healthy",
		"uptime":    m.Uptime().String(),
		"goroutines": runtime.NumGoroutine(),
		"timestamp": time.Now().UTC().Format(time.RFC3339),
	}
}

// HandleRPC handles a JSON-RPC request for system/process operations.
func (m *Monitor) HandleRPC(method string, params json.RawMessage) (interface{}, error) {
	switch method {
	case "system.info":
		return m.GetSystemInfo(), nil

	case "system.health":
		return m.HealthCheck(), nil

	case "system.find_claude":
		return m.FindClaudeCode()

	default:
		return nil, fmt.Errorf("unknown system method: %s", method)
	}
}
