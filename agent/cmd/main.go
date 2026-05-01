package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/google/uuid"
	"github.com/spf13/cobra"

	"github.com/pocketclaude/agent/internal/api"
	"github.com/pocketclaude/agent/internal/connection"
	"github.com/pocketclaude/agent/internal/crypto"
	"github.com/pocketclaude/agent/internal/pty"
)

var (
	relayURL string
	apiPort  int
)

func main() {
	rootCmd := &cobra.Command{
		Use:   "pocketclaude-agent",
		Short: "PocketClaude desktop agent - remote AI coding companion",
	}

	rootCmd.PersistentFlags().StringVar(&relayURL, "relay", "ws://relay.pocketclaude.dev:8080", "relay server URL")
	rootCmd.PersistentFlags().IntVar(&apiPort, "port", 9090, "local API server port")

	rootCmd.AddCommand(initCmd())
	rootCmd.AddCommand(pairCmd())
	rootCmd.AddCommand(startCmd())

	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}

func initCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "init",
		Short: "Initialize agent: generate keys and config",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfgPath, _ := crypto.ConfigPath()
			if _, err := os.Stat(cfgPath); err == nil {
				return fmt.Errorf("already initialized (config at %s). Delete config to reinitialize", cfgPath)
			}

			fmt.Println("Initializing PocketClaude Agent...")
			fmt.Println()

			kp, err := crypto.GenerateKeyPair()
			if err != nil {
				return fmt.Errorf("failed to generate keys: %w", err)
			}

			deviceID := uuid.New().String()

			if err := crypto.SaveConfig(kp, deviceID, relayURL, apiPort); err != nil {
				return fmt.Errorf("failed to save config: %w", err)
			}

			configDir, _ := crypto.DefaultConfigDir()
			fmt.Println("Agent initialized successfully!")
			fmt.Println()
			fmt.Printf("  Device ID:    %s\n", deviceID)
			fmt.Printf("  Fingerprint:  %s\n", kp.Fingerprint())
			fmt.Printf("  Config dir:   %s\n", configDir)
			fmt.Printf("  Relay URL:    %s\n", relayURL)
			fmt.Println()
			fmt.Println("Next steps:")
			fmt.Println("  1. Run 'pocketclaude-agent pair' to pair with your phone")
			fmt.Println("  2. Run 'pocketclaude-agent start' to start the agent")

			return nil
		},
	}
}

func pairCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "pair",
		Short: "Pair with a mobile device via QR code",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := crypto.LoadConfig()
			if err != nil {
				return fmt.Errorf("not initialized. Run 'pocketclaude-agent init' first")
			}

			kp, err := crypto.LoadKeyPair(cfg)
			if err != nil {
				return fmt.Errorf("failed to load keys: %w", err)
			}

			if crypto.IsPaired() {
				fmt.Printf("Already paired with device: %s\n", cfg.PairedClientID)
				fmt.Println("To pair with a new device, delete the config and reinitialize.")
				return nil
			}

			result, err := crypto.RunPairingFlow(kp, cfg)
			if err != nil {
				return fmt.Errorf("pairing failed: %w", err)
			}

			// Save as base64 to match ParseClientPubKey expectations
			clientPubKeyB64 := base64.StdEncoding.EncodeToString(result.ClientPubKey[:])
			if err := crypto.SavePairedClient(result.ClientID, clientPubKeyB64); err != nil {
				return fmt.Errorf("failed to save pairing: %w", err)
			}

			fmt.Println()
			fmt.Println("Pairing successful!")
			fmt.Printf("  Client ID: %s\n", result.ClientID)
			fmt.Println()
			fmt.Println("Run 'pocketclaude-agent start' to begin.")

			return nil
		},
	}
}

func startCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "start",
		Short: "Start the agent daemon",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := crypto.LoadConfig()
			if err != nil {
				return fmt.Errorf("not initialized. Run 'pocketclaude-agent init' first")
			}

			kp, err := crypto.LoadKeyPair(cfg)
			if err != nil {
				return fmt.Errorf("failed to load keys: %w", err)
			}

			log.Printf("[Agent] Starting PocketClaude Agent (device: %s)", cfg.DeviceID)

			// Initialize E2E cipher if paired
			var e2eCipher *crypto.E2ECipher
			if cfg.PairedClientPubKey != "" {
				clientPubKey, err := crypto.ParseClientPubKey(cfg.PairedClientPubKey)
				if err != nil {
					log.Printf("[Agent] Warning: failed to parse client key: %v", err)
				} else {
					e2eCipher, err = crypto.NewE2ECipher(kp.X25519PrivateKey, clientPubKey)
					if err != nil {
						log.Printf("[Agent] Warning: failed to derive E2E key: %v", err)
					} else {
						log.Printf("[Agent] E2E encryption enabled with client %s", cfg.PairedClientID)
					}
				}
			}

			// Initialize PTY manager
			ptyMgr := pty.NewManager()
			defer ptyMgr.CloseAll()

			// Initialize API handler
			handler := api.NewHandler(ptyMgr)

			// Start local WebSocket API server
			mux := http.NewServeMux()
			mux.Handle("/ws", handler)
			mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(http.StatusOK)
				w.Write([]byte(`{"status":"ok"}`))
			})

			addr := fmt.Sprintf("127.0.0.1:%d", cfg.APIPort)
			server := &http.Server{Addr: addr, Handler: mux}

			go func() {
				log.Printf("[Agent] API server listening on %s", addr)
				if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
					log.Fatalf("[Agent] API server error: %v", err)
				}
			}()

			// Connect to relay
			relayClient := connection.NewRelayClient(cfg.RelayURL, cfg.DeviceID)
			relayClient.SetPublicKey(cfg.Ed25519PubKeyB64)

			// Set up relay message handler
			relayClient.SetMessageHandler(func(msg map[string]any) {
				method, _ := msg["method"].(string)
				log.Printf("[Relay] Message received: %s", method)

				switch method {
				case "message.relay":
					// Encrypted message from mobile client
					params, ok := msg["params"].(map[string]any)
					if !ok {
						return
					}

					encryptedPayload := params["encrypted_payload"]
					if encryptedPayload == nil || e2eCipher == nil {
						log.Printf("[Relay] No encrypted payload or no E2E cipher")
						return
					}

					// Decode payload to bytes
					payloadBytes, err := toBytes(encryptedPayload)
					if err != nil {
						log.Printf("[Relay] Failed to decode payload: %v", err)
						return
					}

					// Decrypt
					decrypted, err := e2eCipher.Decrypt(payloadBytes)
					if err != nil {
						log.Printf("[Relay] Failed to decrypt: %v", err)
						return
					}

					// Route decrypted request to local API handler
					resp := handler.HandleMessage(decrypted)
					if resp == nil {
						return // notification, no response needed
					}

					// Encrypt response and send back
					respJSON, err := json.Marshal(resp)
					if err != nil {
						log.Printf("[Relay] Failed to marshal response: %v", err)
						return
					}

					encryptedResp, err := e2eCipher.Encrypt(respJSON)
					if err != nil {
						log.Printf("[Relay] Failed to encrypt response: %v", err)
						return
					}

					if err := relayClient.SendJSONRPC("message.send", map[string]any{
						"target_id":         cfg.PairedClientID,
						"encrypted_payload": encryptedResp,
					}); err != nil {
						log.Printf("[Relay] Failed to send response: %v", err)
					}

				case "device.registered":
					log.Printf("[Relay] Device registered successfully")

				case "presence.heartbeat_ack":
					// Heartbeat acknowledged, no action needed

				default:
					log.Printf("[Relay] Unhandled method: %s", method)
				}
			})

			relayClient.SetOnConnect(func() {
				log.Printf("[Relay] Connected to relay server")
			})

			relayClient.SetOnDisconnect(func(err error) {
				log.Printf("[Relay] Disconnected: %v (will auto-reconnect)", err)
			})

			go func() {
				if err := relayClient.Connect(); err != nil {
					log.Printf("[Relay] Connection exited: %v", err)
				}
			}()

			log.Println("[Agent] Agent is running. Press Ctrl+C to stop.")
			log.Printf("[Agent] Pairing status: %s", pairingStatus(cfg))

			// Wait for shutdown signal
			quit := make(chan os.Signal, 1)
			signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
			<-quit

			log.Println("[Agent] Shutting down...")
			relayClient.Close()
			server.Close()

			return nil
		},
	}
}

func pairingStatus(cfg *crypto.Config) string {
	if cfg.PairedClientID != "" {
		return "paired with " + cfg.PairedClientID
	}
	return "not paired - run 'pocketclaude-agent pair'"
}

// toBytes converts an interface{} to []byte.
func toBytes(v interface{}) ([]byte, error) {
	switch val := v.(type) {
	case string:
		return []byte(val), nil
	case []byte:
		return val, nil
	case json.RawMessage:
		return []byte(val), nil
	default:
		b, err := json.Marshal(v)
		if err != nil {
			return nil, fmt.Errorf("cannot convert to bytes: %w", err)
		}
		return b, nil
	}
}
