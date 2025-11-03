#!/usr/bin/env bash
set -euo pipefail

sudo apt update
sudo apt install -y iperf3 openmpi-bin libopenmpi-dev rdma-core perftest git build-essential \
                    python3-pip python3-venv libnccl2 libnccl-dev

python3 -m pip install -U pip wheel
python3 -m pip install -U ray[default] vllm

