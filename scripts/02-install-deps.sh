#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/../venv"

echo "Installing system packages..."
sudo apt update

# Install CUDA runtime and toolkit if not present
echo "Checking for CUDA installation..."
if ! ldconfig -p | grep -q libcudart.so.12; then
    echo "CUDA 12 runtime not found. Installing CUDA toolkit..."
    # Try to install CUDA toolkit
    sudo apt install -y nvidia-cuda-toolkit cuda-toolkit-12-* || \
    sudo apt install -y nvidia-cudnn cuda-runtime-12-* || \
    sudo apt install -y cuda-drivers cuda-runtime-12-6 || \
    echo "Note: Could not install CUDA via apt. It may already be installed in /usr/local/cuda"
else
    echo "✓ CUDA runtime found"
fi

# Install other dependencies
sudo apt install -y iperf3 openmpi-bin libopenmpi-dev rdma-core perftest git build-essential \
                    python3-pip python3-venv python3-full libnccl2 libnccl-dev

# Create virtual environment if it doesn't exist
if [[ ! -d "$VENV_DIR" ]]; then
    echo "Creating Python virtual environment at $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
    echo "Virtual environment created successfully"
else
    echo "Virtual environment already exists at $VENV_DIR"
fi

# Activate venv and install packages
echo "Installing Python packages in virtual environment..."
source "$VENV_DIR/bin/activate"

pip install -U pip wheel

# Detect architecture for PyTorch installation
ARCH=$(uname -m)
echo "Detected architecture: $ARCH"

# Install PyTorch with CUDA 12 support FIRST (critical for vLLM)
echo ""
echo "Installing PyTorch with CUDA 12 support..."
if [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
    echo "ARM64 system detected - Installing PyTorch for ARM..."
    # Try official CUDA wheel first, fall back to nightly if needed
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 || \
    pip install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu121 || \
    {
        echo "⚠ Pre-built PyTorch CUDA wheels unavailable for ARM"
        echo "  Installing CPU version - vLLM may need additional configuration"
        pip install torch torchvision torchaudio
    }
else
    # x86_64 - standard CUDA installation
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
fi

# Verify PyTorch installation
echo ""
echo "Verifying PyTorch installation..."
python -c "import torch; print(f'PyTorch {torch.__version__}'); print(f'CUDA available: {torch.cuda.is_available()}')"

# Now install Ray and vLLM (which will use the PyTorch we just installed)
echo ""
echo "Installing Ray and vLLM..."
pip install -U ray[default] vllm

echo ""
echo "✓ Dependencies installed successfully"
echo "  Virtual environment: $VENV_DIR"
echo "  To activate manually: source $VENV_DIR/bin/activate"

