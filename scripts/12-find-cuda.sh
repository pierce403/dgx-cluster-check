#!/usr/bin/env bash

echo "======================================================================"
echo "CUDA Installation Finder"
echo "======================================================================"
echo ""

# Check nvidia-smi
echo "Checking nvidia-smi..."
if command -v nvidia-smi &>/dev/null; then
    nvidia-smi --version
    echo ""
    nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
else
    echo "✗ nvidia-smi not found"
fi

echo ""
echo "======================================================================"
echo "Searching for CUDA installations..."
echo "======================================================================"
echo ""

# Common CUDA paths
CUDA_PATHS=(
    "/usr/local/cuda"
    "/usr/local/cuda-12"
    "/usr/local/cuda-12.0"
    "/usr/local/cuda-12.1"
    "/usr/local/cuda-12.2"
    "/usr/local/cuda-12.3"
    "/usr/local/cuda-12.4"
    "/usr/local/cuda-11"
    "/usr/lib/cuda"
    "/opt/cuda"
)

FOUND_CUDA=false

for path in "${CUDA_PATHS[@]}"; do
    if [[ -d "$path" ]]; then
        echo "✓ Found CUDA at: $path"
        if [[ -f "$path/version.json" ]]; then
            echo "  Version info:"
            cat "$path/version.json" 2>/dev/null | head -10
        elif [[ -f "$path/version.txt" ]]; then
            echo "  Version: $(cat "$path/version.txt")"
        fi
        
        if [[ -d "$path/lib64" ]]; then
            echo "  Libraries: $path/lib64"
            ls -la "$path/lib64/libcudart.so"* 2>/dev/null | head -3
        fi
        
        if [[ -d "$path/bin" ]]; then
            echo "  Binaries: $path/bin"
        fi
        
        FOUND_CUDA=true
        echo ""
    fi
done

if [[ "$FOUND_CUDA" == "false" ]]; then
    echo "✗ No CUDA installation found in common locations"
fi

echo ""
echo "======================================================================"
echo "Searching for CUDA libraries in system paths..."
echo "======================================================================"
echo ""

# Find libcudart
echo "Looking for libcudart.so.12..."
find /usr /opt -name "libcudart.so.12*" 2>/dev/null | head -10 || echo "  Not found in /usr or /opt"

echo ""
echo "Current LD_LIBRARY_PATH:"
echo "${LD_LIBRARY_PATH:-not set}"

echo ""
echo "======================================================================"
echo "Recommendation"
echo "======================================================================"
echo ""

if [[ "$FOUND_CUDA" == "true" ]]; then
    echo "✓ CUDA is installed. The scripts have been updated to find it automatically."
    echo ""
    echo "To test vLLM now:"
    echo "  cd ~/dgx-cluster-check"
    echo "  pkill -f vllm"
    echo "  bash scripts/08-vllm-serve.sh"
else
    echo "⚠ CUDA not found. You may need to install it:"
    echo ""
    echo "For DGX OS / Ubuntu:"
    echo "  sudo apt update"
    echo "  sudo apt install nvidia-cuda-toolkit"
    echo ""
    echo "Or install from NVIDIA:"
    echo "  wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb"
    echo "  sudo dpkg -i cuda-keyring_1.1-1_all.deb"
    echo "  sudo apt update"
    echo "  sudo apt install cuda-toolkit-12-6"
fi

echo ""

