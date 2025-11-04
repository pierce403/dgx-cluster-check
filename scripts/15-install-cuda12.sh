#!/usr/bin/env bash
set -euo pipefail

echo "======================================================================"
echo "CUDA 12 Installation for ARM64/SBSA Systems"
echo "======================================================================"
echo ""

# Check current CUDA version
echo "Checking existing CUDA installation..."
if [[ -f /usr/local/cuda/bin/nvcc ]]; then
    CUDA_VERSION=$(/usr/local/cuda/bin/nvcc --version | grep "release" | awk '{print $5}' | cut -d',' -f1)
    echo "Current CUDA version: $CUDA_VERSION"
else
    echo "nvcc not found"
    CUDA_VERSION="unknown"
fi

echo ""

# Check architecture
ARCH=$(uname -m)
echo "System architecture: $ARCH"

if [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
    echo "✓ ARM64 system detected (SBSA)"
    ARCH_TYPE="sbsa"
    UBUNTU_ARCH="sbsa-linux"
else
    echo "✓ x86_64 system detected"
    ARCH_TYPE="x86_64"
    UBUNTU_ARCH="x86_64"
fi

echo ""
echo "======================================================================"
echo "Installing CUDA 12.6 Runtime"
echo "======================================================================"
echo ""

# Determine Ubuntu version
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    UBUNTU_VERSION=$(echo $VERSION_ID | tr -d '.')
    echo "Ubuntu version: $VERSION_ID (code: ubuntu${UBUNTU_VERSION})"
else
    UBUNTU_VERSION="2404"
    echo "Assuming Ubuntu 24.04"
fi

# Install CUDA 12 repository
echo ""
echo "Adding NVIDIA CUDA repository..."

if [[ "$ARCH_TYPE" == "sbsa" ]]; then
    # ARM64/SBSA repository
    CUDA_REPO="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${UBUNTU_VERSION}/${UBUNTU_ARCH}/cuda-keyring_1.1-1_all.deb"
else
    # x86_64 repository
    CUDA_REPO="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${UBUNTU_VERSION}/x86_64/cuda-keyring_1.1-1_all.deb"
fi

echo "Repository: $CUDA_REPO"
cd /tmp
wget -q --show-progress "$CUDA_REPO" -O cuda-keyring.deb || {
    echo "✗ Failed to download CUDA repository package"
    echo "  URL: $CUDA_REPO"
    exit 1
}

sudo dpkg -i cuda-keyring.deb
sudo apt update

echo ""
echo "Installing CUDA 12.6 toolkit (this may take several minutes)..."
echo ""

# Install CUDA 12.6 specifically (compatible with vLLM)
if sudo apt install -y cuda-toolkit-12-6; then
    echo "✓ CUDA 12.6 toolkit installed"
elif sudo apt install -y cuda-runtime-12-6; then
    echo "✓ CUDA 12.6 runtime installed"
elif sudo apt install -y cuda-12-6; then
    echo "✓ CUDA 12-6 package installed"
else
    echo "✗ Failed to install CUDA 12.6"
    echo ""
    echo "Available CUDA packages:"
    apt search cuda-toolkit 2>/dev/null | grep "cuda-toolkit-12"
    exit 1
fi

echo ""
echo "Configuring library paths..."

# Add CUDA 12 library paths
if [[ -d "/usr/local/cuda-12.6/targets/${UBUNTU_ARCH}/lib" ]]; then
    echo "/usr/local/cuda-12.6/targets/${UBUNTU_ARCH}/lib" | sudo tee /etc/ld.so.conf.d/cuda-12.conf
elif [[ -d "/usr/local/cuda-12.6/lib64" ]]; then
    echo "/usr/local/cuda-12.6/lib64" | sudo tee /etc/ld.so.conf.d/cuda-12.conf
elif [[ -d "/usr/local/cuda-12/targets/${UBUNTU_ARCH}/lib" ]]; then
    echo "/usr/local/cuda-12/targets/${UBUNTU_ARCH}/lib" | sudo tee /etc/ld.so.conf.d/cuda-12.conf
fi

# Update library cache
sudo ldconfig

echo ""
echo "======================================================================"
echo "Verification"
echo "======================================================================"
echo ""

# Check for libcudart.so.12
if ldconfig -p | grep -q "libcudart.so.12"; then
    echo "✓✓✓ SUCCESS! CUDA 12 runtime is available"
    echo ""
    ldconfig -p | grep libcudart.so.12
    echo ""
    echo "CUDA 12 installation complete!"
    echo ""
    echo "You can now run vLLM:"
    echo "  bash scripts/08-vllm-serve.sh"
else
    echo "✗ libcudart.so.12 still not found"
    echo ""
    echo "Searching for CUDA 12 libraries..."
    find /usr/local/cuda-12* -name "libcudart.so*" 2>/dev/null || true
    echo ""
    echo "Check installed CUDA versions:"
    ls -la /usr/local/ | grep cuda
fi

echo ""
echo "Note: CUDA 13 will remain installed alongside CUDA 12"
echo "vLLM will use CUDA 12 libraries"
echo ""

