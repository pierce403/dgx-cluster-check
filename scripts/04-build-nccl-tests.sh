#!/usr/bin/env bash
set -euo pipefail
cd "$HOME"
if [[ ! -d nccl-tests ]]; then
  git clone https://github.com/NVIDIA/nccl-tests.git
fi
cd nccl-tests && make -j

