#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/../venv"

echo "Installing system packages..."
sudo apt update
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
pip install -U ray[default] vllm

echo ""
echo "✓ Dependencies installed successfully"
echo "  Virtual environment: $VENV_DIR"
echo "  To activate manually: source $VENV_DIR/bin/activate"

