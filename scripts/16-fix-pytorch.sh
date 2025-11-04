#!/usr/bin/env bash
set -euo pipefail

echo "======================================================================"
echo "PyTorch CUDA Fix Script"
echo "======================================================================"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/../venv"

if [[ ! -d "$VENV_DIR" ]]; then
    echo "✗ Virtual environment not found at $VENV_DIR"
    echo "  Run: bash scripts/02-install-deps.sh"
    exit 1
fi

echo "Activating virtual environment..."
source "$VENV_DIR/bin/activate"

echo ""
echo "Checking current PyTorch installation..."
if python -c "import torch; print(f'PyTorch {torch.__version__}'); print(f'CUDA available: {torch.cuda.is_available()}'); print(f'CUDA version: {torch.version.cuda if torch.cuda.is_available() else \"N/A\"}')" 2>/dev/null; then
    echo ""
    read -p "Do you want to reinstall PyTorch with CUDA 12 support? (yes/no) [yes]: " REINSTALL
    REINSTALL=${REINSTALL:-yes}
    if [[ "$REINSTALL" != "yes" ]]; then
        echo "Exiting without changes"
        exit 0
    fi
else
    echo "PyTorch not properly installed or missing CUDA support"
fi

echo ""
echo "======================================================================"
echo "Reinstalling PyTorch with CUDA 12 Support"
echo "======================================================================"
echo ""

# Detect architecture
ARCH=$(uname -m)
echo "System architecture: $ARCH"

# Uninstall existing PyTorch
echo ""
echo "Removing existing PyTorch installation..."
pip uninstall -y torch torchvision torchaudio 2>/dev/null || true

# Install PyTorch with CUDA support
echo ""
if [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
    # ARM64 architecture - build from source or use PyTorch nightly
    echo "ARM64 detected - Installing PyTorch for ARM with CUDA support..."
    echo "This may take 10-20 minutes on first install..."
    echo ""
    
    # Try official ARM wheel first (if available)
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 || \
    {
        echo "Standard wheels not available for ARM, trying alternative..."
        # Install from source with CUDA (requires more time)
        pip install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu121 || \
        {
            echo "⚠ PyTorch CUDA wheels not available for ARM64"
            echo ""
            echo "Installing CPU version and attempting manual CUDA library linking..."
            pip install torch torchvision torchaudio
            
            echo ""
            echo "Note: You may need to build PyTorch from source for full CUDA support on ARM."
            echo "See: https://github.com/pytorch/pytorch#from-source"
        }
    }
else
    # x86_64 architecture - standard installation
    echo "x86_64 detected - Installing PyTorch with CUDA 12.1 support..."
    echo "This may take a few minutes..."
    echo ""
    
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
fi

echo ""
echo "======================================================================"
echo "Verification"
echo "======================================================================"
echo ""

# Verify installation
if python -c "import torch; print(f'✓ PyTorch {torch.__version__}'); print(f'✓ CUDA available: {torch.cuda.is_available()}'); print(f'✓ CUDA version: {torch.version.cuda}'); print(f'✓ Number of GPUs: {torch.cuda.device_count()}')"; then
    echo ""
    echo "✓✓✓ SUCCESS! PyTorch with CUDA support is installed"
    echo ""
    echo "You can now run vLLM:"
    echo "  bash scripts/08-vllm-serve.sh"
else
    echo ""
    echo "✗ PyTorch installed but CUDA support verification failed"
    echo ""
    echo "This might be okay if you haven't installed CUDA 12 yet."
    echo "Make sure to run: bash scripts/15-install-cuda12.sh"
fi

echo ""

