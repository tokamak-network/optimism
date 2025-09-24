#!/bin/bash

# Pre-download Required Docker Images for Optimism Devnet
# This script downloads essential Docker images to avoid network timeouts during deployment

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Required Docker images
IMAGES=(
    "protolambda/eth2-val-tools:latest"
    "consensys/teku:25.7.0"
    "ethereum/client-go:latest"
    "python:3.12-alpine"
    "us-docker.pkg.dev/oplabs-tools-artifacts/images/proxyd:v4.14.5"
)

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if Docker is running
check_docker() {
    print_status "Checking Docker status..."
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    print_success "Docker is running"
}

# Function to check available disk space
check_disk_space() {
    print_status "Checking available disk space..."

    # Get available space in GB (works on both macOS and Linux)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        AVAILABLE_GB=$(df -g . | tail -1 | awk '{print $4}')
    else
        # Linux
        AVAILABLE_GB=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
    fi

    print_status "Available disk space: ${AVAILABLE_GB}GB"

    if [ "$AVAILABLE_GB" -lt 10 ]; then
        print_warning "Low disk space detected (${AVAILABLE_GB}GB available)"
        print_warning "Recommended: at least 10GB free space for Docker images"

        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Operation cancelled"
            exit 1
        fi
    fi
}

# Function to pull a single image with retry logic
pull_image() {
    local image=$1
    local max_retries=3
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        print_status "Pulling $image (attempt $((retry_count + 1))/$max_retries)..."

        if docker pull "$image"; then
            print_success "Successfully pulled $image"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                print_warning "Failed to pull $image, retrying in 5 seconds..."
                sleep 5
            else
                print_error "Failed to pull $image after $max_retries attempts"
                return 1
            fi
        fi
    done
}

# Function to check if image already exists
image_exists() {
    docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "^$1$"
}

# Main function
main() {
    echo "=================================================="
    echo "Pre-downloading Required Docker Images"
    echo "=================================================="

    check_docker
    check_disk_space

    local failed_images=()
    local skipped_images=()
    local pulled_images=()

    echo
    print_status "Starting image download process..."
    echo

    for image in "${IMAGES[@]}"; do
        if image_exists "$image"; then
            print_warning "Image $image already exists, skipping"
            skipped_images+=("$image")
        else
            if pull_image "$image"; then
                pulled_images+=("$image")
            else
                failed_images+=("$image")
            fi
        fi
        echo
    done

    echo "=================================================="
    echo "Download Summary"
    echo "=================================================="

    if [ ${#pulled_images[@]} -gt 0 ]; then
        print_success "Successfully pulled ${#pulled_images[@]} image(s):"
        for image in "${pulled_images[@]}"; do
            echo "  ✓ $image"
        done
        echo
    fi

    if [ ${#skipped_images[@]} -gt 0 ]; then
        print_warning "Skipped ${#skipped_images[@]} existing image(s):"
        for image in "${skipped_images[@]}"; do
            echo "  - $image"
        done
        echo
    fi

    if [ ${#failed_images[@]} -gt 0 ]; then
        print_error "Failed to pull ${#failed_images[@]} image(s):"
        for image in "${failed_images[@]}"; do
            echo "  ✗ $image"
        done
        echo
        print_error "Some images failed to download. You may encounter timeouts during devnet deployment."
        print_status "You can re-run this script to retry failed downloads."
        exit 1
    fi

    print_success "All required Docker images are now available!"
    print_status "You can proceed to the next step in the setup process."
}

# Show help if requested
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Pre-download Required Docker Images for Optimism Devnet"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "This script downloads essential Docker images to avoid network timeouts"
    echo "during devnet deployment."
    echo
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo
    echo "Images that will be downloaded:"
    for image in "${IMAGES[@]}"; do
        echo "  - $image"
    done
    echo
    echo "Requirements:"
    echo "  - Docker must be running"
    echo "  - At least 10GB free disk space recommended"
    echo
    exit 0
fi

# Run main function
main