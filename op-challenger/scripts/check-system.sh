
#!/bin/bash

# Challenger Network - System Status Check Script

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log Functions
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

echo "=========================================="
echo "Challenger Network - System Status Check"
echo "=========================================="
echo

# System information
log_info "Checking system information..."
echo "OS: $(uname -s) $(uname -m)"
echo "Shell: $SHELL"
echo "User: $USER"
echo

# Go version check
log_info "Checking Go version..."
if command -v go &> /dev/null; then
    GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
    GO_MAJOR=$(echo $GO_VERSION | cut -d. -f1)
    GO_MINOR=$(echo $GO_VERSION | cut -d. -f2)
    GO_PATCH=$(echo $GO_VERSION | cut -d. -f3)

    if [ "$GO_MAJOR" -lt 1 ] || ([ "$GO_MAJOR" -eq 1 ] && [ "$GO_MINOR" -lt 23 ]) || ([ "$GO_MAJOR" -eq 1 ] && [ "$GO_MINOR" -eq 23 ] && [ "$GO_PATCH" -lt 10 ]); then
        log_warning "Go version update required: current $GO_VERSION, need 1.23.10+"
        echo "   Solution:"
        echo "   - mise install go@1.23.10"
        echo "   - mise use go@1.23.10"
        echo "   - or download from https://golang.org/dl/"
        echo
    else
        log_success "Go version check: $GO_VERSION"
        echo
    fi
else
    log_error "Go is not installed"
    echo "   Solution:"
    echo "   - mise install go@1.23.10"
    echo "   - or download from https://golang.org/dl/"
    echo
fi

# Check Docker
log_info "Checking Docker..."
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version)
    log_success "Docker installed: $DOCKER_VERSION"

    # Check Docker service status
    if docker system info &> /dev/null; then
        log_success "Docker service working normally"
    else
        log_warning "Docker service is not running"
        echo "   Solution: Start Docker Desktop"
    fi
    echo
else
    log_error "Docker is not installed"
    echo "   Solution:"
    echo "   - macOS: brew install --cask docker"
    echo "   - Ubuntu: sudo apt install docker.io"
    echo "   - or download from https://docs.docker.com/get-docker/"
    echo
fi

# Check Mise
log_info "Checking Mise..."
if command -v mise &> /dev/null; then
    MISE_VERSION=$(mise --version | head -1)
    log_success "Mise installed: $MISE_VERSION"
    echo
else
    log_error "Mise is not installed"
    echo "   Solution:"
    echo "   - curl -fsSL https://mise.run | sh"
    echo "   - eval \"\$(/Users/zena/.local/bin/mise activate zsh)\""
    echo
fi

# Check Kurtosis
log_info "Checking Kurtosis..."
if command -v kurtosis &> /dev/null; then
    KURTOSIS_VERSION=$(kurtosis version 2>/dev/null | grep "CLI Version" | awk '{print $3}')
    if [ -n "$KURTOSIS_VERSION" ]; then
        log_success "Kurtosis installed: CLI Version $KURTOSIS_VERSION"
    else
        log_success "Kurtosis installed"
    fi
    echo
else
    log_error "Kurtosis is not installed"
    echo "   Solution:"
    echo "   - mise install kurtosis"
    echo "   - or brew install kurtosis-tech/tap/kurtosis-cli"
    echo
fi

# Check Just
log_info "Checking Just..."
if command -v just &> /dev/null; then
    JUST_VERSION=$(just --version)
    log_success "Just installed: $JUST_VERSION"
    echo
else
    log_error "Just is not installed"
    echo "   Solution:"
    echo "   - mise install just"
    echo "   - or brew install just"
    echo
fi

# Check Git
log_info "Checking Git..."
if command -v git &> /dev/null; then
    GIT_VERSION=$(git --version)
    log_success "Git installed: $GIT_VERSION"
    echo
else
    log_error "Git is not installed"
    echo "   Solution:"
    echo "   - macOS: brew install git"
    echo "   - Ubuntu: sudo apt install git"
    echo
fi

# Check Make
log_info "Checking Make..."
if command -v make &> /dev/null; then
    MAKE_VERSION=$(make --version | head -1)
    log_success "Make installed: $MAKE_VERSION"
    echo
else
    log_error "Make is not installed"
    echo "   Solution:"
    echo "   - macOS: xcode-select --install"
    echo "   - Ubuntu: sudo apt install make"
    echo
fi

# Check System Resources
log_info "Checking system resources..."

# Check memory
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    MEMORY_GB=$(sysctl -n hw.memsize | awk '{print $0/1024/1024/1024}')
else
    # Linux
    MEMORY_GB=$(grep MemTotal /proc/meminfo | awk '{print $2/1024/1024}')
fi

if (( $(echo "$MEMORY_GB >= 8" | bc -l) )); then
    log_success "Memory check: ${MEMORY_GB}GB (recommended: 8GB+)"
else
    log_warning "Insufficient memory: ${MEMORY_GB}GB (recommended: 8GB+)"
fi

# Check disk space
DISK_GB=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
if [ "$DISK_GB" -ge 50 ]; then
    log_success "Disk space check: ${DISK_GB}GB (recommended: 50GB+)"
else
    log_warning "Insufficient disk space: ${DISK_GB}GB (recommended: 50GB+)"
fi

echo

# Summary
echo "=========================================="
echo "Check completed!"
echo "=========================================="

# Check if there are any issues
if command -v go &> /dev/null && command -v docker &> /dev/null && command -v mise &> /dev/null && command -v kurtosis &> /dev/null && command -v just &> /dev/null; then
    log_success "All required tools are installed!"
    echo
    echo "Next steps:"
    echo "1. ./build-devnet.sh (Builds and starts the challenger devnet)"
    echo
else
    log_warning "Some tools are not installed."
    echo "Please install them following the solutions above and run again."
    echo
fi

echo "Additional information:"
echo "- Detailed installation guide: docs/devnet-guide.md"
echo "- Troubleshooting: docs/troubleshooting-guide.md"
