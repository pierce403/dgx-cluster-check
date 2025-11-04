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
echo "Reinstalling PyTorch with CUDA 12.1 Support"
echo "======================================================================"
echo ""

# Uninstall existing PyTorch
echo "Removing existing PyTorch installation..."
pip uninstall -y torch torchvision torchaudio 2>/dev/null || true

# Install PyTorch with CUDA 12.1 (compatible with CUDA 12.x)
echo ""
echo "Installing PyTorch with CUDA 12.1 support..."
echo "This may take a few minutes..."
echo ""

pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121

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

