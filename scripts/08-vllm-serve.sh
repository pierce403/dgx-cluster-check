#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../scripts/utils.sh"

if [[ "${ROLE}" != "head" ]]; then
  echo "Run vLLM only on the head node."; exit 1
fi

# ============================================================================
# CUDA Library Path Setup - Critical for vLLM
# ============================================================================

echo "Checking CUDA availability..."

# Find and add CUDA libraries to LD_LIBRARY_PATH
CUDA_FOUND=false

# Check common CUDA paths
for CUDA_PATH in /usr/local/cuda /usr/local/cuda-12 /usr/local/cuda-12.* /usr/lib/cuda /opt/cuda; do
    if [[ -d "$CUDA_PATH/lib64" ]]; then
        echo "✓ Found CUDA at: $CUDA_PATH"
        export LD_LIBRARY_PATH="${CUDA_PATH}/lib64:${LD_LIBRARY_PATH:-}"
        export PATH="${CUDA_PATH}/bin:${PATH:-}"
        CUDA_FOUND=true
        break
    fi
done

# Also add system library paths
export LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
export LD_LIBRARY_PATH="/usr/lib:${LD_LIBRARY_PATH:-}"

# Try to update the library cache
sudo ldconfig 2>/dev/null || true

# Verify libcudart.so.12 is available
echo "Verifying CUDA runtime library..."
if ldconfig -p | grep -q "libcudart.so.12"; then
    echo "✓ libcudart.so.12 found in library cache"
elif find /usr/local/cuda* /usr/lib* /opt/cuda -name "libcudart.so.12*" 2>/dev/null | head -1; then
    echo "✓ libcudart.so.12 found on filesystem"
    # Found the file, update library cache
    echo "  Updating library cache..."
    sudo ldconfig
else
    echo "✗ ERROR: libcudart.so.12 NOT FOUND"
    echo ""
    echo "vLLM requires CUDA 12 runtime libraries."
    echo ""
    echo "To fix this, run:"
    echo "  sudo apt update"
    echo "  sudo apt install -y nvidia-cuda-toolkit"
    echo ""
    echo "Or if CUDA is already installed, add it to the library path:"
    echo "  echo '/usr/local/cuda/lib64' | sudo tee /etc/ld.so.conf.d/cuda.conf"
    echo "  sudo ldconfig"
    echo ""
    exit 1
fi

# Show final library path for debugging
echo "LD_LIBRARY_PATH: ${LD_LIBRARY_PATH}"

# Optional: pre-auth with HuggingFace if needed
# huggingface-cli login --token YOUR_TOKEN

echo ""
echo "Starting vLLM API server..."
echo "  Model: ${MODEL}"
echo "  Host: 0.0.0.0"
echo "  Port: ${VLLM_PORT}"
echo "  Ray: ${MASTER_ADDR}:${MASTER_PORT}"
echo "  Tensor Parallel: ${TP_SIZE:-2}"
echo ""

# Launch vLLM distributed using Ray
exec python3 -m vllm.entrypoints.api_server ${MODEL:+--model $MODEL} \
  --host 0.0.0.0 --port "${VLLM_PORT}" \
  --distributed-executor-backend ray \
  --ray-address "${MASTER_ADDR}:${MASTER_PORT}" \
  --tensor-parallel-size "${TP_SIZE:-2}"

