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

# Core Docker images required for devnet bootstrap
CORE_IMAGES=(
    "protolambda/eth2-val-tools:latest"
    "consensys/teku:25.7.0"
    "ethereum/client-go:latest"
    "python:3.12-alpine"
    "us-docker.pkg.dev/oplabs-tools-artifacts/images/proxyd:v4.14.5"
)

DEFAULT_VM_REGISTRY="${VM_REGISTRY:-ghcr.io/zena-park}"
VM_REGISTRY="$DEFAULT_VM_REGISTRY"
VM_IMAGE_TAG="${VM_IMAGE_TAG:-latest}"
INCLUDE_PERMISSIONED=true   # GameType 1 (permissioned cannon) uses the same base images
INCLUDE_ASTERISC=true       # GameType 2
INCLUDE_KONA=true           # GameType 3

VM_BASE_IMAGES=(
    "${VM_REGISTRY}/vm-cannon:${VM_IMAGE_TAG}"
    "${VM_REGISTRY}/vm-op-program:${VM_IMAGE_TAG}"
    "${VM_REGISTRY}/op-challenger:${VM_IMAGE_TAG}"
    "${VM_REGISTRY}/op-node:${VM_IMAGE_TAG}"
    "${VM_REGISTRY}/op-batcher:${VM_IMAGE_TAG}"
    "${VM_REGISTRY}/op-proposer:${VM_IMAGE_TAG}"
)
VM_ASTERISC_IMAGES=(
    "${VM_REGISTRY}/vm-asterisc:${VM_IMAGE_TAG}"
)
VM_KONA_IMAGES=(
    "${VM_REGISTRY}/vm-kona-client:${VM_IMAGE_TAG}"
)

SCRIPT_NAME="$(basename "$0")"

usage() {
    cat <<EOF
Optimism devnet & 챌린저용 Docker 이미지 사전 다운로드 스크립트

사용법: $SCRIPT_NAME [옵션]

옵션:
  -h, --help           도움말을 표시합니다.
  --registry REGISTRY  VM 이미지가 위치한 Docker 레지스트리 (기본: ${DEFAULT_VM_REGISTRY})
                       (환경변수 VM_REGISTRY 로도 지정 가능)
  --tag TAG            VM 이미지 태그 (기본: ${VM_IMAGE_TAG})
                       (환경변수 VM_IMAGE_TAG 로도 지정 가능)
  --skip-asterisc      ASTERISC(GameType 2) 이미지를 건너뜁니다.
  --skip-kona          KONA(GameType 3) 이미지를 건너뜁니다.

스크립트가 다운로드하는 항목:
  • Core: eth2-val-tools, teku, geth, python, proxyd
  • GameType 0/1 (CANNON/Permissioned) 공통 VM: vm-cannon, vm-op-program, op-challenger, op-node, op-batcher, op-proposer
  • GameType 2 (ASTERISC): vm-asterisc
  • GameType 3 (KONA): vm-kona-client

⚠️ 메모:
  - Private 레지스트리를 사용한다면 사전에 docker login 이 필요합니다.
  - GameType 2/3 테스트를 원하지 않으면 --skip-asterisc/--skip-kona 로 건너뛸 수 있습니다.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --registry)
            if [[ -z "${2:-}" ]]; then
                echo -e "${RED}[ERROR]${NC} --registry 옵션에는 값이 필요합니다."
                exit 1
            fi
            VM_REGISTRY="$2"
            shift 2
            ;;
        --tag)
            if [[ -z "${2:-}" ]]; then
                echo -e "${RED}[ERROR]${NC} --tag 옵션에는 값이 필요합니다."
                exit 1
            fi
            VM_IMAGE_TAG="$2"
            shift 2
            ;;
        --skip-asterisc)
            INCLUDE_ASTERISC=false
            shift
            ;;
        --skip-kona)
            INCLUDE_KONA=false
            shift
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} 알 수 없는 옵션입니다: $1"
            usage
            exit 1
            ;;
    esac
done

# Rebuild VM image arrays if registry or tag were overridden
VM_BASE_IMAGES=(
    "${VM_REGISTRY}/vm-cannon:${VM_IMAGE_TAG}"
    "${VM_REGISTRY}/vm-op-program:${VM_IMAGE_TAG}"
    "${VM_REGISTRY}/op-challenger:${VM_IMAGE_TAG}"
    "${VM_REGISTRY}/op-node:${VM_IMAGE_TAG}"
    "${VM_REGISTRY}/op-batcher:${VM_IMAGE_TAG}"
    "${VM_REGISTRY}/op-proposer:${VM_IMAGE_TAG}"
)

VM_ASTERISC_IMAGES=(
    "${VM_REGISTRY}/vm-asterisc:${VM_IMAGE_TAG}"
)

VM_KONA_IMAGES=(
    "${VM_REGISTRY}/vm-kona-client:${VM_IMAGE_TAG}"
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

    local images_to_pull=("${CORE_IMAGES[@]}")
    local failed_images=()
    local skipped_images=()
    local pulled_images=()
    local vm_images_added=()

    echo
    print_status "VM 이미지 레지스트리: ${VM_REGISTRY}"
    print_status "VM 이미지 태그: ${VM_IMAGE_TAG}"
    if ! docker info >/dev/null 2>&1; then
        print_warning "Docker 정보를 확인하지 못했습니다. private 레지스트리라면 docker login 이 필요할 수 있습니다."
    fi
    echo

    images_to_pull+=("${VM_BASE_IMAGES[@]}")
    vm_images_added+=("${VM_BASE_IMAGES[@]}")

    if [ "$INCLUDE_ASTERISC" = true ]; then
        images_to_pull+=("${VM_ASTERISC_IMAGES[@]}")
        vm_images_added+=("${VM_ASTERISC_IMAGES[@]}")
    else
        print_warning "ASTERISC(GameType 2) 이미지는 --skip-asterisc 옵션으로 건너뜀"
    fi

    if [ "$INCLUDE_KONA" = true ]; then
        images_to_pull+=("${VM_KONA_IMAGES[@]}")
        vm_images_added+=("${VM_KONA_IMAGES[@]}")
    else
        print_warning "KONA(GameType 3) 이미지는 --skip-kona 옵션으로 건너뜀"
    fi

    if [ ${#vm_images_added[@]} -gt 0 ]; then
        print_status "GameType 0/1/2/3 용 VM 이미지 총 ${#vm_images_added[@]}개를 다운로드 목록에 추가했습니다."
        echo
    fi

    echo
    print_status "Starting image download process..."
    echo

    for image in "${images_to_pull[@]}"; do
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

# Run main function
main