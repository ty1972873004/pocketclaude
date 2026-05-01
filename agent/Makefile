.PHONY: build build-all clean run test tidy lint fmt install deps

BINARY=pocketclaude-agent
VERSION?=0.1.0
LDFLAGS=-ldflags "-s -w -X main.version=$(VERSION)"

build:
	go build $(LDFLAGS) -o bin/$(BINARY) ./cmd/

build-all: build-linux build-darwin build-windows

build-linux:
	GOOS=linux GOARCH=amd64 go build $(LDFLAGS) -o bin/$(BINARY)-linux-amd64 ./cmd/
	GOOS=linux GOARCH=arm64 go build $(LDFLAGS) -o bin/$(BINARY)-linux-arm64 ./cmd/

build-darwin:
	GOOS=darwin GOARCH=amd64 go build $(LDFLAGS) -o bin/$(BINARY)-darwin-amd64 ./cmd/
	GOOS=darwin GOARCH=arm64 go build $(LDFLAGS) -o bin/$(BINARY)-darwin-arm64 ./cmd/

build-windows:
	GOOS=windows GOARCH=amd64 go build $(LDFLAGS) -o bin/$(BINARY)-windows-amd64.exe ./cmd/
	GOOS=windows GOARCH=arm64 go build $(LDFLAGS) -o bin/$(BINARY)-windows-arm64.exe ./cmd/

clean:
	rm -rf bin/

run:
	go run ./cmd/ start

test:
	go test -v -race ./...

lint:
	go vet ./...

fmt:
	go fmt ./...

deps:
	go mod download

tidy:
	go mod tidy

install: build
	cp bin/$(BINARY) /usr/local/bin/ 2>/dev/null || echo "Run with sudo or copy bin/$(BINARY) to your PATH"

init:
	go run ./cmd/ init

pair:
	go run ./cmd/ pair
