#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../scripts/utils.sh"

HOST1=${1:-spark1}
HOST2=${2:-spark2}

# ensure hostname resolution exists (or replace with IPs directly)
# echo "$IP $(hostname)" | sudo tee -a /etc/hosts

mpirun -np 2 -H ${HOST1},${HOST2} -bind-to none -map-by slot \
  -x NCCL_SOCKET_IFNAME -x NCCL_DEBUG \
  $HOME/nccl-tests/build/all_reduce_perf -b 8 -e 8G -f 2 -g 1

