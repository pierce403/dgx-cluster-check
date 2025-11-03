#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../scripts/utils.sh"

ray stop || true
ray start --head --node-ip-address="$IP" --port="$MASTER_PORT"

