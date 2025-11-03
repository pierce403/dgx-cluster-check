#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../scripts/utils.sh"

if [[ "${ROLE}" == "worker" ]]; then
  echo "[worker] Starting iperf3 server bound to ${IP}"
  pkill -f "iperf3 -s" || true
  nohup iperf3 -s -B "$IP" >/tmp/iperf3.log 2>&1 &
  echo "Worker iperf3 server running. Check /tmp/iperf3.log"
else
  echo "[head] Running iperf3 client toward ${PEER_IP}"
  iperf3 -c "$PEER_IP" -P 8 -t 10 -M 9000
fi

