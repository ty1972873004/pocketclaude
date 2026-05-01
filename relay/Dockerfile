# Build stage
FROM golang:1.22-alpine AS builder

WORKDIR /app

# Cache dependency downloads.
COPY go.mod go.sum ./
RUN go mod download

# Copy source and build.
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /relay-server ./cmd/main.go

# Runtime stage
FROM alpine:3.19

RUN apk --no-cache add ca-certificates

COPY --from=builder /relay-server /usr/local/bin/relay-server

EXPOSE 8080

ENTRYPOINT ["relay-server"]
CMD ["-addr", ":8080"]
