#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
source "$ROOT/.env"

# Activate Python virtual environment if it exists
VENV_DIR="$ROOT/venv"
if [[ -d "$VENV_DIR" ]]; then
    source "$VENV_DIR/bin/activate"
fi

# Add CUDA to library path (common locations)
# Check multiple common CUDA installation paths
for CUDA_PATH in /usr/local/cuda /usr/local/cuda-12 /usr/local/cuda-12.* /usr/lib/cuda /opt/cuda; do
    if [[ -d "$CUDA_PATH/lib64" ]]; then
        export LD_LIBRARY_PATH="${CUDA_PATH}/lib64:${LD_LIBRARY_PATH:-}"
        export PATH="${CUDA_PATH}/bin:${PATH:-}"
        break
    fi
done

# Also check system CUDA libraries
if [[ -d "/usr/lib/x86_64-linux-gnu" ]]; then
    export LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
fi

export NCCL_SOCKET_IFNAME=${IFACE}
export NCCL_DEBUG=${NCCL_DEBUG:-INFO}
export NCCL_IB_DISABLE=${NCCL_IB_DISABLE:-0}
export NCCL_IB_HCA=${NCCL_IB_HCA:-mlx5}
export HF_HOME=${HF_HOME:-$HOME/.cache/huggingface}
export TRANSFORMERS_CACHE=${TRANSFORMERS_CACHE:-$HF_HOME}

