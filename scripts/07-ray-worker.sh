#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../scripts/utils.sh"

ray stop || true
ray start --address="${MASTER_ADDR}:${MASTER_PORT}"

