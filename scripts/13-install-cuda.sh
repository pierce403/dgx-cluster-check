#!/usr/bin/env bash
set -euo pipefail

echo "======================================================================"
echo "CUDA Installation Script"
echo "======================================================================"
echo ""

# Check if CUDA is already available
if ldconfig -p | grep -q "libcudart.so.12"; then
    echo "✓ CUDA 12 runtime already available!"
    ldconfig -p | grep libcudart.so.12
    echo ""
    echo "Nothing to do."
    exit 0
fi

echo "CUDA 12 runtime not found. Installing..."
echo ""

# Update package list
sudo apt update

# Try different package names (varies by Ubuntu version)
echo "Attempting to install CUDA toolkit..."
echo ""

# Option 1: Try nvidia-cuda-toolkit (meta-package)
if sudo apt install -y nvidia-cuda-toolkit; then
    echo "✓ Installed nvidia-cuda-toolkit"
elif sudo apt install -y cuda-toolkit-12-6; then
    echo "✓ Installed cuda-toolkit-12-6"
elif sudo apt install -y cuda-runtime-12-6; then
    echo "✓ Installed cuda-runtime-12-6"  
elif sudo apt install -y cuda-drivers; then
    echo "✓ Installed cuda-drivers"
else
    echo "⚠ Could not install CUDA via apt"
    echo ""
    echo "Manual installation required:"
    echo ""
    echo "1. Install from NVIDIA repository:"
    echo "   wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb"
    echo "   sudo dpkg -i cuda-keyring_1.1-1_all.deb"
    echo "   sudo apt update"
    echo "   sudo apt install cuda-toolkit-12-6"
    echo ""
    echo "2. Or download from: https://developer.nvidia.com/cuda-downloads"
    echo ""
    exit 1
fi

# Update library cache
echo ""
echo "Updating library cache..."
sudo ldconfig

# Verify installation
echo ""
echo "Verifying CUDA installation..."
if ldconfig -p | grep -q "libcudart.so.12"; then
    echo "✓ SUCCESS! CUDA 12 runtime is now available"
    ldconfig -p | grep libcudart.so.12
    echo ""
    echo "You can now run vLLM:"
    echo "  bash scripts/08-vllm-serve.sh"
else
    echo "✗ Installation completed but libcudart.so.12 still not found"
    echo ""
    echo "Checking what was installed..."
    find /usr/local/cuda* /usr/lib* /opt -name "libcudart.so*" 2>/dev/null | head -10
    echo ""
    echo "You may need to manually add CUDA to library path:"
    echo "  echo '/usr/local/cuda/lib64' | sudo tee /etc/ld.so.conf.d/cuda.conf"
    echo "  sudo ldconfig"
fi

