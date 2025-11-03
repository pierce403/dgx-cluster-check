#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../scripts/utils.sh"

if [[ "${ROLE}" != "head" ]]; then
  echo "Run vLLM only on the head node."; exit 1
fi

# Optional: pre-auth with HuggingFace if needed
# huggingface-cli login --token YOUR_TOKEN

# Launch vLLM distributed using Ray
exec python3 -m vllm.entrypoints.api_server ${MODEL:+--model $MODEL} \
  --host 0.0.0.0 --port "${VLLM_PORT}" \
  --distributed-executor-backend ray \
  --ray-address "${MASTER_ADDR}:${MASTER_PORT}" \
  --tensor-parallel-size "${TP_SIZE:-2}"

