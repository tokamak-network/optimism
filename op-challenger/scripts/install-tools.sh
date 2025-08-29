
#!/bin/bash

# Challenger Network - 시스템 도구 설치 스크립트

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 변수 정의
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPTIMISM_ROOT="$(cd "$SCRIPT_DIR/../../../optimism" && pwd)"

# 로그 함수
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Installation functions
install_go() {
    log_info "Installing Go 1.23.10..."
    if command -v mise &> /dev/null; then
        mise install go@1.23.10
        mise use go@1.23.10
        log_success "Go 1.23.10 installation completed"
    else
        log_error "Mise is not installed. Please install Mise first."
        return 1
    fi
}

install_docker() {
    log_info "Installing Docker..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew install --cask docker
            log_success "Docker installation completed (Homebrew)"
        else
            log_error "Homebrew is not installed. Download from https://docs.docker.com/get-docker/"
            return 1
        fi
    else
        log_error "Unsupported OS. Download from https://docs.docker.com/get-docker/"
        return 1
    fi
}

install_mise() {
    log_info "Installing Mise..."
    curl -fsSL https://mise.run | sh
    log_success "Mise installation completed"
    log_warning "Open a new terminal or run:"
    echo "   eval \"\$(/Users/zena/.local/bin/mise activate zsh)\""
}

install_kurtosis() {
    log_info "Installing Kurtosis..."
    if command -v mise &> /dev/null; then
        mise install kurtosis
        log_success "Kurtosis installation completed"
    else
        log_error "Mise is not installed. Please install Mise first."
        return 1
    fi
}

install_just() {
    log_info "Installing Just..."
    if command -v mise &> /dev/null; then
        mise install just
        log_success "Just installation completed"
    else
        log_error "Mise is not installed. Please install Mise first."
        return 1
    fi
}

# Fix Dockerfile for go-libp2p-mplex compatibility issues
fix_dockerfile() {
    log_info "Checking Dockerfile for go-libp2p-mplex compatibility issues..."

    local dockerfile="$OPTIMISM_ROOT/ops/docker/op-stack-go/Dockerfile"
    local backup_file="$dockerfile.backup.$(date +%Y%m%d_%H%M%S)"

    if [ ! -f "$dockerfile" ]; then
        log_error "Dockerfile not found: $dockerfile"
        return 1
    fi

    # Check if fix is already applied
    if grep -q "Fix go-libp2p-mplex compatibility issues" "$dockerfile"; then
        log_success "Dockerfile fix is already applied"
        return 0
    fi

    # Create backup
    cp "$dockerfile" "$backup_file"
    log_info "Created backup: $backup_file"

    # Find the line after go mod download and before ARG GIT_COMMIT
    local insert_line=$(grep -n "ARG GIT_COMMIT" "$dockerfile" | head -1 | cut -d: -f1)

    if [ -z "$insert_line" ]; then
        log_error "Could not find insertion point in Dockerfile"
        return 1
    fi

    # Create temporary file with the fix
    local temp_file=$(mktemp)

    # Copy lines before insertion point
    head -n $((insert_line - 1)) "$dockerfile" > "$temp_file"

    # Add the fix
    cat >> "$temp_file" << 'EOF'

# Fix go-libp2p-mplex compatibility issues in Docker build
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build go mod download && \
    cd /go/pkg/mod/github.com/libp2p/go-libp2p-mplex@v0.9.0 && \
    if ! grep -q "func (c \*conn) CloseWithError" conn.go; then \
        sed -i '/var _ network.MuxedConn = &conn{}/a\\nfunc (c *conn) CloseWithError(code int) error {\n\treturn c.mplex().Close()\n}' conn.go; \
    fi && \
    if ! grep -q "func (s \*stream) ResetWithError" stream.go; then \
        sed -i '/var _ network.MuxedStream = &stream{}/a\\nfunc (s *stream) ResetWithError(code int) error {\n\treturn s.mplex().Reset()\n}' stream.go; \
    fi

EOF

    # Copy remaining lines
    tail -n +$insert_line "$dockerfile" >> "$temp_file"

    # Replace original file
    mv "$temp_file" "$dockerfile"

    log_success "Dockerfile fixed for go-libp2p-mplex compatibility"
    log_info "Backup saved as: $backup_file"

    return 0
}

# Fix madns import issue in op-node/p2p/host.go
fix_op_node_madns() {
    log_info "Fixing madns import issue in op-node/p2p/host.go..."

    local host_go="$OPTIMISM_ROOT/op-node/p2p/host.go"

    if [ ! -f "$host_go" ]; then
        log_error "host.go not found: $host_go"
        return 1
    fi

    # Check if madns import exists
    if ! grep -q 'madns "github.com/multiformats/go-multiaddr-dns"' "$host_go"; then
        log_success "madns import issue already fixed"
        return 0
    fi

    # Create backup
    local backup_file="$host_go.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$host_go" "$backup_file"
    log_info "Created backup: $backup_file"

    # Remove unused madns import
    sed -i '' '/madns "github\.com\/multiformats\/go-multiaddr-dns"/d' "$host_go"

    log_success "madns import issue fixed"
    log_info "Backup saved as: $backup_file"

    return 0
}

# Fix go.mod dependencies
fix_go_dependencies() {
    log_info "Fixing go.mod dependencies..."

    cd "$OPTIMISM_ROOT"

    # Check if go.mod exists
    if [ ! -f "go.mod" ]; then
        log_error "go.mod not found in $OPTIMISM_ROOT"
        return 1
    fi

    # Run go mod tidy to fix missing dependencies
    log_info "Running go mod tidy..."
    if go mod tidy; then
        log_success "go.mod dependencies fixed successfully"
        return 0
    else
        log_error "Failed to fix go.mod dependencies"
        return 1
    fi
}

# Main function
main() {
    echo "=========================================="
    echo "Challenger Network - System Tools Installation"
    echo "=========================================="
    echo

    # List of tools to install
    TOOLS_TO_INSTALL=()

            # Go version check (1.23.10+ required)
    log_info "Checking Go version..."
    if command -v go &> /dev/null; then
        GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
        GO_MAJOR=$(echo $GO_VERSION | cut -d. -f1)
        GO_MINOR=$(echo $GO_VERSION | cut -d. -f2)
        GO_PATCH=$(echo $GO_VERSION | cut -d. -f3)

        if [ "$GO_MAJOR" -lt 1 ] || ([ "$GO_MAJOR" -eq 1 ] && [ "$GO_MINOR" -lt 23 ]) || ([ "$GO_MAJOR" -eq 1 ] && [ "$GO_MINOR" -eq 23 ] && [ "$GO_PATCH" -lt 10 ]); then
            log_warning "Go version update required: current $GO_VERSION, need 1.23.10+"
            log_warning "Note: Docker images use Go 1.23.8, which may cause compatibility issues"
            TOOLS_TO_INSTALL+=("go")
        else
            log_success "Go version check: $GO_VERSION (project requirement: 1.23.10+)"
        fi
    else
        log_error "Go is not installed"
        TOOLS_TO_INSTALL+=("go")
    fi

        # Docker check (24.0+ required)
    log_info "Checking Docker..."
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
        DOCKER_MAJOR=$(echo $DOCKER_VERSION | cut -d. -f1)
        DOCKER_MINOR=$(echo $DOCKER_VERSION | cut -d. -f2)

        if [ "$DOCKER_MAJOR" -lt 24 ]; then
            log_warning "Docker version update required: current $DOCKER_VERSION, need 24.0+"
            TOOLS_TO_INSTALL+=("docker")
        else
            log_success "Docker installed: $DOCKER_VERSION (container orchestration supported)"
        fi

        # Docker service status check
        if docker system info &> /dev/null; then
            log_success "Docker service is running"
        else
            log_warning "Docker service is not running"
            echo "   Solution: Start Docker Desktop"
        fi
    else
        log_error "Docker is not installed"
        TOOLS_TO_INSTALL+=("docker")
    fi

    # Mise check
    log_info "Checking Mise..."
    if command -v mise &> /dev/null; then
        MISE_VERSION=$(mise --version | head -1)
        log_success "Mise installed: $MISE_VERSION"
    else
        log_error "Mise is not installed"
        TOOLS_TO_INSTALL+=("mise")
    fi

    # Kurtosis check
    log_info "Checking Kurtosis..."
    if command -v kurtosis &> /dev/null; then
        KURTOSIS_VERSION=$(kurtosis version 2>/dev/null | grep "CLI Version" | awk '{print $3}')
        if [ -n "$KURTOSIS_VERSION" ]; then
            log_success "Kurtosis installed: CLI Version $KURTOSIS_VERSION"
        else
            log_success "Kurtosis installed"
        fi
    else
        log_error "Kurtosis is not installed"
        TOOLS_TO_INSTALL+=("kurtosis")
    fi

    # Just check
    log_info "Checking Just..."
    if command -v just &> /dev/null; then
        JUST_VERSION=$(just --version)
        log_success "Just installed: $JUST_VERSION"
    else
        log_error "Just is not installed"
        TOOLS_TO_INSTALL+=("just")
    fi

    echo

    # Check if tools need to be installed
    if [ ${#TOOLS_TO_INSTALL[@]} -eq 0 ]; then
        log_success "All required tools are already installed!"
        echo

        # Ask about Dockerfile fix (default: yes)
        read -p "Do you want to apply Dockerfile fix for go-libp2p-mplex compatibility? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            fix_dockerfile
            # Fix madns import issue
            fix_op_node_madns
            # Also fix go.mod dependencies after Dockerfile fix
            log_info "Fixing go.mod dependencies after Dockerfile update..."
            fix_go_dependencies
        fi

        echo
        echo "Next steps:"
        echo "1. ./build-devnet.sh (Builds and starts the challenger devnet)"
        return 0
    fi

    # Show tools to be installed
    echo "Tools to be installed:"
    for tool in "${TOOLS_TO_INSTALL[@]}"; do
        echo "  - $tool"
    done
    echo

    # User confirmation
    read -p "Do you want to install these tools automatically? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled."
        return 0
    fi

    # Install Mise first (dependency for other tools)
    if [[ " ${TOOLS_TO_INSTALL[@]} " =~ " mise " ]]; then
        install_mise
        # Update environment variables after Mise installation
        export PATH="$HOME/.local/bin:$PATH"
        if [ -f "$HOME/.zshrc" ]; then
            echo 'eval "$(/Users/zena/.local/bin/mise activate zsh)"' >> "$HOME/.zshrc"
        fi
    fi

    # Install remaining tools
    for tool in "${TOOLS_TO_INSTALL[@]}"; do
        case $tool in
            "go")
                install_go
                ;;
            "docker")
                install_docker
                ;;
            "kurtosis")
                install_kurtosis
                ;;
            "just")
                install_just
                ;;
        esac
    done

    echo
    log_success "Installation completed!"
    echo

    # Ask about Dockerfile fix (default: yes)
    read -p "Do you want to apply Dockerfile fix for go-libp2p-mplex compatibility? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        fix_dockerfile
        # Fix madns import issue
        fix_op_node_madns
        # Also fix go.mod dependencies after Dockerfile fix
        log_info "Fixing go.mod dependencies after Dockerfile update..."
        fix_go_dependencies
    fi

    echo
    echo "Next steps:"
    echo "1. Open a new terminal or run:"
    echo "   source ~/.zshrc"
    echo "2. ./build-devnet.sh (Builds and starts the challenger devnet)"
    echo
    echo "Note: If you encounter Go version compatibility issues:"
    echo "   AUTOFIX=true ./build-devnet.sh"
    echo
    echo "Or to check system status again:"
    echo "   ./check-system.sh"
}

# Script execution
main "$@"
