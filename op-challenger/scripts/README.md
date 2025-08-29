Phase 1 P2P Challenger Network

🚀 Quick Installation (Recommended)
Local Devnet Development Environment
# Step 1: Install system tools
cd op-challenger/scripts/p2p

# Step 2: Build Devnet Environment
./build-devnet.sh

# Step 3: Run Challenger
./run-challenger-devnet.sh
System Tools Auto Installation
# Install system tools only
cd op-challenger/scripts/p2p
./install-tools.sh
What the auto-installation script does:

✅ Automatic system status verification
✅ Auto-installation of missing tools
✅ Go 1.24.6+ auto-installation
✅ Docker, Mise, Kurtosis, Just auto-installation
✅ Optimized installation order (considering dependencies)
✅ User confirmation before installation




Devnet Status Check
# Check Devnet running status
kurtosis enclave inspect simple-devnet

# Check challenger status
docker ps | grep challenger

현재 실행 중인 Devnet 완전 정리

# Kurtosis enclave 정리
kurtosis enclave rm --force simple-devnet

# Docker 컨테이너들 정리 (혹시 남아있는 경우)
docker stop $(docker ps -q) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true

# Docker 볼륨 정리 (선택사항)
docker volume prune -f




