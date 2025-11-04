#!/usr/bin/env bash
set -euo pipefail

echo "======================================================================"
echo "PyTorch Installation for ARM64/SBSA with CUDA"
echo "======================================================================"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/../venv"

if [[ ! -d "$VENV_DIR" ]]; then
    echo "✗ Virtual environment not found"
    exit 1
fi

source "$VENV_DIR/bin/activate"

# Check architecture
ARCH=$(uname -m)
if [[ "$ARCH" != "aarch64" ]] && [[ "$ARCH" != "arm64" ]]; then
    echo "This script is for ARM64 systems only"
    echo "For x86_64, use: bash scripts/16-fix-pytorch.sh"
    exit 1
fi

echo "ARM64 architecture detected"
echo ""
echo "PyTorch CUDA wheels are not available for ARM64 via standard pip."
echo ""
echo "⚠ IMPORTANT: For DGX Spark/GraceHopper systems, NVIDIA recommends using"
echo "   their NGC containers which have pre-built PyTorch with CUDA support."
echo "   See: https://catalog.ngc.nvidia.com/orgs/nvidia/containers/pytorch"
echo ""
echo "However, for this venv-based setup, we have these options:"
echo ""
echo "1. Install latest available PyTorch (quick, likely works)"
echo "2. Build PyTorch from source with CUDA (30-60 min, guaranteed)"  
echo "3. Upgrade to newer vLLM that works with latest PyTorch"
echo "4. Exit and use NGC containers instead (recommended)"
echo ""

read -p "Choose option (1/2/3/4) [1]: " OPTION
OPTION=${OPTION:-1}

if [[ "$OPTION" == "4" ]]; then
    echo ""
    echo "======================================================================"
    echo "Using NGC Containers (Recommended for DGX Systems)"
    echo "======================================================================"
    echo ""
    echo "NVIDIA provides optimized containers for DGX ARM systems:"
    echo ""
    echo "1. Install NVIDIA Container Toolkit:"
    echo "   sudo apt install -y nvidia-container-toolkit"
    echo ""
    echo "2. Pull PyTorch container:"
    echo "   docker pull nvcr.io/nvidia/pytorch:24.10-py3"
    echo ""
    echo "3. Run vLLM in container:"
    echo "   docker run --gpus all --network host \\"
    echo "     -v \$HOME/.cache/huggingface:/root/.cache/huggingface \\"
    echo "     nvcr.io/nvidia/pytorch:24.10-py3 \\"
    echo "     bash -c 'pip install vllm && python -m vllm.entrypoints.api_server ...'"
    echo ""
    echo "See README for container-based setup instructions."
    echo ""
    exit 0
fi

if [[ "$OPTION" == "1" ]]; then
    echo ""
    echo "======================================================================"
    echo "Option 1: Installing PyTorch CPU version"
    echo "======================================================================"
    echo ""
    echo "This installs PyTorch without CUDA wheels, but vLLM will attempt"
    echo "to use system CUDA libraries. This often works on DGX systems."
    echo ""
    
    # Uninstall existing
    pip uninstall -y torch torchvision torchaudio 2>/dev/null || true
    
    # Install CPU version (which actually can use CUDA if libraries are present)
    # For ARM64, use default PyPI (no CUDA wheels available)
    pip install torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1 || \
    pip install torch torchvision torchaudio
    
    echo ""
    echo "Testing CUDA availability..."
    python -c "import torch; print(f'PyTorch {torch.__version__}'); print(f'CUDA available: {torch.cuda.is_available()}'); print(f'CUDA devices: {torch.cuda.device_count() if torch.cuda.is_available() else 0}')"
    
elif [[ "$OPTION" == "2" ]]; then
    echo ""
    echo "======================================================================"
    echo "Option 2: Building PyTorch from Source"
    echo "======================================================================"
    echo ""
    echo "⚠ This will take 30-60 minutes!"
    echo ""
    read -p "Continue? (yes/no) [no]: " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        echo "Cancelled"
        exit 0
    fi
    
    # Install build dependencies
    echo "Installing build dependencies..."
    sudo apt install -y python3-dev build-essential cmake ninja-build
    
    # Uninstall existing
    pip uninstall -y torch torchvision torchaudio 2>/dev/null || true
    
    # Build from source
    pip install numpy
    pip install pyyaml mkl mkl-include setuptools cmake cffi typing_extensions future six requests dataclasses
    
    echo ""
    echo "Cloning PyTorch 2.8.0..."
    cd /tmp
    if [[ -d pytorch ]]; then
        rm -rf pytorch
    fi
    git clone --recursive --branch v2.8.0 https://github.com/pytorch/pytorch
    cd pytorch
    
    echo ""
    echo "Building PyTorch with CUDA support..."
    echo "This will take 30-60 minutes..."
    export USE_CUDA=1
    export CMAKE_PREFIX_PATH="$VENV_DIR"
    python setup.py install
    
    cd "$SCRIPT_DIR/.."
    
elif [[ "$OPTION" == "3" ]]; then
    echo ""
    echo "======================================================================"
    echo "Option 3: Install Compatible vLLM Version"
    echo "======================================================================"
    echo ""
    
    # Uninstall vLLM
    pip uninstall -y vllm
    
    # Install latest PyTorch (CPU for now)
    pip uninstall -y torch torchvision torchaudio 2>/dev/null || true
    pip install torch torchvision torchaudio
    
    echo ""
    echo "Installing latest vLLM (will match PyTorch version)..."
    pip install vllm
    
    echo ""
    echo "Note: This may install a different vLLM version"
    pip show vllm | grep Version
    
else
    echo "Invalid option"
    exit 1
fi

echo ""
echo "======================================================================"
echo "Verification"
echo "======================================================================"
echo ""

python -c "
import torch
print(f'PyTorch: {torch.__version__}')
print(f'CUDA available: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'CUDA version: {torch.version.cuda}')
    print(f'Number of GPUs: {torch.cuda.device_count()}')
    for i in range(torch.cuda.device_count()):
        print(f'  GPU {i}: {torch.cuda.get_device_name(i)}')
else:
    print('⚠ CUDA not available - vLLM will not work')
"

echo ""
echo "Checking vLLM import..."
python -c "import vllm; print(f'vLLM version: {vllm.__version__}')" || {
    echo "✗ vLLM import failed"
    echo "  You may need to reinstall vLLM: pip install vllm"
}

echo ""
echo "======================================================================"
echo "Summary"
echo "======================================================================"
echo ""

if [[ "$OPTION" == "1" ]]; then
    echo "Installed PyTorch CPU version"
    echo "vLLM will attempt to use system CUDA libraries"
    echo ""
    echo "If vLLM still fails with CUDA errors, try Option 2 (build from source)"
elif [[ "$OPTION" == "2" ]]; then
    echo "Built PyTorch from source with CUDA support"
    echo "This should work with vLLM"
elif [[ "$OPTION" == "3" ]]; then
    echo "Installed latest compatible versions"
    echo "vLLM and PyTorch versions should now match"
fi

echo ""
echo "Try running vLLM:"
echo "  bash scripts/08-vllm-serve.sh"
echo ""

