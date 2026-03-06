# Crossler Build Configuration
# Cross-compilation for all 6 target platforms

VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
BUILD_TIME := $(shell date -u '+%Y-%m-%d_%H:%M:%S')
LDFLAGS := -s -w -X main.Version=$(VERSION) -X main.BuildTime=$(BUILD_TIME)

DIST_DIR := dist
GO_BUILD := CGO_ENABLED=0 go build -buildvcs=false -ldflags "$(LDFLAGS)"

.PHONY: all clean test \
	windows-x64 windows-arm64 \
	linux-x64 linux-arm64 \
	darwin-x64 darwin-arm64

all: linux-x64 linux-arm64 darwin-x64 darwin-arm64 windows-x64 windows-arm64
	@echo "================================"
	@echo "Build complete! Version: $(VERSION)"
	@ls -lh $(DIST_DIR)/

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(DIST_DIR)
	@echo "Clean complete!"

test:
	@echo "Running tests..."
	@go test ./...
	@echo "Tests complete!"

$(DIST_DIR):
	@mkdir -p $(DIST_DIR)

# === Linux ===

linux-x64: $(DIST_DIR)
	@echo "Building for Linux x64..."
	@GOOS=linux GOARCH=amd64 $(GO_BUILD) -o $(DIST_DIR)/crossler-linux-x64 ./cmd/crossler

linux-arm64: $(DIST_DIR)
	@echo "Building for Linux ARM64..."
	@GOOS=linux GOARCH=arm64 $(GO_BUILD) -o $(DIST_DIR)/crossler-linux-arm64 ./cmd/crossler

# === macOS ===

darwin-x64: $(DIST_DIR)
	@echo "Building for macOS x64..."
	@GOOS=darwin GOARCH=amd64 $(GO_BUILD) -o $(DIST_DIR)/crossler-darwin-x64 ./cmd/crossler

darwin-arm64: $(DIST_DIR)
	@echo "Building for macOS ARM64..."
	@GOOS=darwin GOARCH=arm64 $(GO_BUILD) -o $(DIST_DIR)/crossler-darwin-arm64 ./cmd/crossler

# === Windows ===

windows-x64: $(DIST_DIR)
	@echo "Building for Windows x64..."
	@GOOS=windows GOARCH=amd64 $(GO_BUILD) -o $(DIST_DIR)/crossler-windows-x64.exe ./cmd/crossler

windows-arm64: $(DIST_DIR)
	@echo "Building for Windows ARM64..."
	@GOOS=windows GOARCH=arm64 $(GO_BUILD) -o $(DIST_DIR)/crossler-windows-arm64.exe ./cmd/crossler

help:
	@echo "Crossler Build System"
	@echo "====================="
	@echo ""
	@echo "Available targets:"
	@echo "  all            - Build for all platforms (default)"
	@echo "  clean          - Remove build artifacts"
	@echo "  test           - Run tests"
	@echo "  linux-x64      - Build for Linux x64"
	@echo "  linux-arm64    - Build for Linux ARM64"
	@echo "  darwin-x64     - Build for macOS x64"
	@echo "  darwin-arm64   - Build for macOS ARM64"
	@echo "  windows-x64    - Build for Windows x64"
	@echo "  windows-arm64  - Build for Windows ARM64"
