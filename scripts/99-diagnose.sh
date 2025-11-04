#!/usr/bin/env bash
set -euo pipefail

echo "======================================================================"
echo "DGX Cluster Diagnostics"
echo "======================================================================"
echo ""

# Load config
if [[ -f "$(dirname "$0")/../.env" ]]; then
    source "$(dirname "$0")/../.env"
    echo "✓ Configuration loaded"
    echo "  ROLE: $ROLE"
    echo "  IFACE: $IFACE"
    echo "  IP: $IP"
    echo "  MASTER_ADDR: $MASTER_ADDR"
    echo "  MASTER_PORT: $MASTER_PORT"
else
    echo "✗ No .env file found"
    exit 1
fi

echo ""
echo "======================================================================"
echo "Network Configuration"
echo "======================================================================"
echo ""

# Check interface
if ip addr show "$IFACE" &>/dev/null; then
    echo "✓ Interface $IFACE exists"
    ip addr show "$IFACE" | grep "inet "
else
    echo "✗ Interface $IFACE not found"
fi

# Check connectivity to peer
echo ""
echo "Testing connectivity to peer ($PEER_IP)..."
if ping -c 2 -W 2 "$PEER_IP" &>/dev/null; then
    echo "✓ Can reach peer at $PEER_IP"
else
    echo "✗ Cannot reach peer at $PEER_IP"
fi

echo ""
echo "======================================================================"
echo "Port Status"
echo "======================================================================"
echo ""

# Check if port 6379 is listening
echo "Checking port $MASTER_PORT..."
if netstat -tuln 2>/dev/null | grep ":$MASTER_PORT " || ss -tuln 2>/dev/null | grep ":$MASTER_PORT "; then
    echo "✓ Port $MASTER_PORT is listening"
else
    echo "✗ Port $MASTER_PORT is NOT listening"
fi

echo ""
echo "======================================================================"
echo "Ray Status"
echo "======================================================================"
echo ""

# Check if venv exists and has ray
VENV_DIR="$(dirname "$0")/../venv"
if [[ -f "$VENV_DIR/bin/ray" ]]; then
    echo "✓ Ray binary found in venv"
    source "$VENV_DIR/bin/activate"
    
    # Check Ray processes
    echo ""
    echo "Ray processes:"
    ps aux | grep -E "ray|gcs_server" | grep -v grep || echo "  No Ray processes found"
    
    echo ""
    echo "Ray status:"
    ray status 2>&1 || echo "  Ray cluster not accessible"
    
else
    echo "✗ Ray binary not found in venv"
fi

echo ""
echo "======================================================================"
echo "Firewall Status"
echo "======================================================================"
echo ""

# Check firewall
if command -v ufw &>/dev/null; then
    echo "UFW status:"
    sudo ufw status
elif command -v firewall-cmd &>/dev/null; then
    echo "Firewalld status:"
    sudo firewall-cmd --state 2>&1
else
    echo "  No firewall manager found (ufw/firewalld)"
fi

echo ""
echo "======================================================================"
echo "vLLM Status"
echo "======================================================================"
echo ""

if [[ -f "$(dirname "$0")/../vllm.pid" ]]; then
    VLLM_PID=$(cat "$(dirname "$0")/../vllm.pid")
    if kill -0 "$VLLM_PID" 2>/dev/null; then
        echo "✓ vLLM process running (PID: $VLLM_PID)"
    else
        echo "✗ vLLM PID file exists but process not running"
    fi
else
    echo "  No vLLM PID file found"
fi

echo ""
echo "Recent vLLM logs (last 20 lines):"
if [[ -f "$(dirname "$0")/../vllm.log" ]]; then
    tail -20 "$(dirname "$0")/../vllm.log"
else
    echo "  No vLLM log file found"
fi

echo ""
echo "======================================================================"
echo "Diagnostic complete"
echo "======================================================================"

