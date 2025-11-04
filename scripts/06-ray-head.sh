#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../scripts/utils.sh"

echo "Stopping any existing Ray processes..."
ray stop || true
sleep 2

echo "Starting Ray head node..."
echo "  Node IP: $IP"
echo "  GCS Port: $MASTER_PORT"
echo ""

# Start Ray head with explicit binding
# --node-ip-address: IP to advertise to other nodes
# --port: GCS server port
# --include-dashboard: Enable Ray dashboard (optional)
# --dashboard-host: Allow external dashboard access
ray start \
  --head \
  --node-ip-address="$IP" \
  --port="$MASTER_PORT" \
  --include-dashboard=true \
  --dashboard-host="0.0.0.0" \
  --dashboard-port=8265

echo ""
echo "Waiting for Ray to initialize..."
sleep 3

echo ""
echo "Ray cluster status:"
ray status || echo "Warning: Could not get Ray status immediately after start"

echo ""
echo "✓ Ray head node started"
echo "  Dashboard: http://$IP:8265"
echo "  GCS: $IP:$MASTER_PORT"

