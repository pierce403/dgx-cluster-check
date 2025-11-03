#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../openwebui"
MASTER_ADDR=${MASTER_ADDR:-192.168.40.1} VLLM_PORT=${VLLM_PORT:-8000} docker compose up -d

