#!/usr/bin/env bash
set -euo pipefail

echo "======================================================================"
echo "Ray Troubleshooting & Fix Script"
echo "======================================================================"
echo ""

source "$(dirname "$0")/../scripts/utils.sh"

echo "Current configuration:"
echo "  IP: $IP"
echo "  Port: $MASTER_PORT"
echo ""

# Stop all Ray processes
echo "Stopping all Ray processes..."
ray stop || true
sleep 2

# Kill any lingering processes
echo "Cleaning up lingering Ray processes..."
pkill -9 -f "ray::" || true
pkill -9 -f "gcs_server" || true
pkill -9 -f "raylet" || true
sleep 2

# Clean Ray temp directory
echo "Cleaning Ray temporary files..."
rm -rf /tmp/ray || true

# Check and configure firewall if needed
echo ""
echo "Checking firewall configuration..."
if command -v ufw &>/dev/null; then
    sudo ufw status | grep -q "Status: active"
    if [ $? -eq 0 ]; then
        echo "UFW is active. Opening required ports..."
        sudo ufw allow from "$PEER_IP" to any port "$MASTER_PORT" comment "Ray GCS"
        sudo ufw allow from "$PEER_IP" to any port 8265 comment "Ray Dashboard"
        echo "✓ Firewall rules added"
    else
        echo "  UFW not active"
    fi
elif command -v firewall-cmd &>/dev/null; then
    if sudo firewall-cmd --state 2>&1 | grep -q running; then
        echo "Firewalld is running. Opening required ports..."
        sudo firewall-cmd --permanent --add-port="$MASTER_PORT/tcp"
        sudo firewall-cmd --permanent --add-port=8265/tcp
        sudo firewall-cmd --reload
        echo "✓ Firewall rules added"
    else
        echo "  Firewalld not running"
    fi
else
    echo "  No firewall detected"
fi

# Check system limits
echo ""
echo "Checking system limits..."
NOFILE_LIMIT=$(ulimit -n)
if [ "$NOFILE_LIMIT" -lt 65536 ]; then
    echo "⚠ File descriptor limit is low: $NOFILE_LIMIT"
    echo "  Ray recommends at least 65536"
    echo "  Consider adding to /etc/security/limits.conf:"
    echo "    * soft nofile 65536"
    echo "    * hard nofile 65536"
else
    echo "✓ File descriptor limit OK: $NOFILE_LIMIT"
fi

# Try starting Ray with explicit Redis configuration
echo ""
echo "Starting Ray head with verbose output..."
echo ""

ray start \
  --head \
  --node-ip-address="$IP" \
  --port="$MASTER_PORT" \
  --include-dashboard=true \
  --dashboard-host="0.0.0.0" \
  --dashboard-port=8265 \
  --verbose

echo ""
echo "Waiting 5 seconds for Ray to fully initialize..."
sleep 5

echo ""
echo "======================================================================"
echo "Checking Ray Status"
echo "======================================================================"
echo ""

# Check if processes are running
echo "Ray processes:"
ps aux | grep -E "ray::|gcs_server|raylet" | grep -v grep

echo ""
echo "Ports listening:"
ss -tlnp | grep -E ":$MASTER_PORT |:8265 " || netstat -tlnp | grep -E ":$MASTER_PORT |:8265 "

echo ""
echo "Ray cluster status:"
if ray status; then
    echo ""
    echo "✓✓✓ Ray head is working correctly! ✓✓✓"
else
    echo ""
    echo "✗ Ray still having issues. Check logs:"
    echo "  tail -50 /tmp/ray/session_latest/logs/gcs_server.err"
    echo "  tail -50 /tmp/ray/session_latest/logs/raylet.err"
fi

echo ""
echo "======================================================================"

