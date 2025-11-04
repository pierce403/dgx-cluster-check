#!/usr/bin/env bash
set -euo pipefail

echo "======================================================================"
echo "CUDA Library Fix Script"
echo "======================================================================"
echo ""

echo "Searching for libcudart libraries..."
echo ""

# Find all libcudart files
FOUND_LIBS=$(find /usr/local/cuda* /usr/lib* /opt/cuda -name "libcudart.so*" 2>/dev/null || true)

if [[ -z "$FOUND_LIBS" ]]; then
    echo "✗ No libcudart libraries found anywhere on system!"
    echo ""
    echo "CUDA directory exists but libraries are missing."
    echo "You need to install CUDA runtime:"
    echo ""
    echo "  bash scripts/13-install-cuda.sh"
    echo ""
    exit 1
fi

echo "Found CUDA libraries:"
echo "$FOUND_LIBS"
echo ""

# Check what version we have
if echo "$FOUND_LIBS" | grep -q "libcudart.so.12"; then
    echo "✓ libcudart.so.12 exists on filesystem"
    CUDA12_LIB=$(echo "$FOUND_LIBS" | grep "libcudart.so.12" | head -1)
    CUDA_LIB_DIR=$(dirname "$CUDA12_LIB")
    echo "  Location: $CUDA_LIB_DIR"
elif echo "$FOUND_LIBS" | grep -q "libcudart.so.11"; then
    echo "⚠ Only CUDA 11 found. vLLM requires CUDA 12."
    echo ""
    echo "Installing CUDA 12..."
    bash "$(dirname "$0")/13-install-cuda.sh"
    exit 0
else
    echo "⚠ Found CUDA but version unclear. Listing all:"
    echo "$FOUND_LIBS"
    CUDA_LIB_DIR=$(dirname $(echo "$FOUND_LIBS" | head -1))
fi

echo ""
echo "======================================================================"
echo "Adding CUDA library path to system configuration"
echo "======================================================================"
echo ""

# Add to ld.so.conf
if [[ -n "${CUDA_LIB_DIR:-}" ]]; then
    echo "Adding $CUDA_LIB_DIR to library search path..."
    echo "$CUDA_LIB_DIR" | sudo tee /etc/ld.so.conf.d/cuda.conf
    
    # Also add common paths
    if [[ -d "/usr/local/cuda/lib64" ]]; then
        echo "/usr/local/cuda/lib64" | sudo tee -a /etc/ld.so.conf.d/cuda.conf
    fi
    
    if [[ -d "/usr/local/cuda-12/lib64" ]]; then
        echo "/usr/local/cuda-12/lib64" | sudo tee -a /etc/ld.so.conf.d/cuda.conf
    fi
    
    echo "✓ Configuration file created: /etc/ld.so.conf.d/cuda.conf"
fi

echo ""
echo "Updating library cache..."
sudo ldconfig
echo "✓ Library cache updated"

echo ""
echo "======================================================================"
echo "Verification"
echo "======================================================================"
echo ""

# Test if it's now in the cache
if ldconfig -p | grep -q "libcudart.so.12"; then
    echo "✓✓✓ SUCCESS! libcudart.so.12 is now in library cache"
    echo ""
    ldconfig -p | grep libcudart.so.12
    echo ""
    echo "You can now run vLLM:"
    echo "  bash scripts/08-vllm-serve.sh"
else
    echo "✗ Still not found in library cache after ldconfig"
    echo ""
    echo "Manual debugging needed:"
    echo "  1. Check symlinks in CUDA directory:"
    echo "     ls -la /usr/local/cuda/lib64/libcudart*"
    echo ""
    echo "  2. Check if CUDA 12 is actually installed:"
    echo "     /usr/local/cuda/bin/nvcc --version"
    echo ""
    echo "  3. You may need to install CUDA 12 specifically:"
    echo "     bash scripts/13-install-cuda.sh"
fi

echo ""

