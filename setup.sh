#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_step() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "  $1"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║        DGX Cluster Setup - Interactive Configuration          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check if .env already exists
if [[ -f "$ENV_FILE" ]]; then
    print_warning ".env file already exists at $ENV_FILE"
    read -p "Do you want to overwrite it? (yes/no) [no]: " OVERWRITE
    OVERWRITE=${OVERWRITE:-no}
    if [[ "$OVERWRITE" != "yes" ]]; then
        print_info "Setup cancelled. Keeping existing .env file."
        exit 0
    fi
    print_step "Backing up existing .env to .env.backup"
    cp "$ENV_FILE" "$ENV_FILE.backup"
    print_success "Backup created"
fi

echo ""
print_step "Step 1: Detecting network interfaces"
print_info "Looking for Mellanox/NVIDIA ConnectX interfaces..."
echo ""

# Try to detect ConnectX interfaces
DETECTED_IFACES=$(ip -br link | grep -E 'mlx|eth|enp' | awk '{print $1}' || true)

if [[ -z "$DETECTED_IFACES" ]]; then
    print_warning "Could not auto-detect ConnectX interfaces"
    print_info "Available interfaces:"
    ip -br link | awk '{print "  - " $1, "(" $2 ")"}'
else
    print_success "Found potential interfaces:"
    echo "$DETECTED_IFACES" | while read iface; do
        STATUS=$(ip -br link show "$iface" | awk '{print $2}')
        echo "  - $iface ($STATUS)"
    done
fi

# Try to detect using lspci
print_info ""
print_info "Checking for Mellanox/ConnectX devices via lspci..."
if command -v lspci &> /dev/null; then
    MELLANOX_DEVICES=$(lspci | grep -i 'mellanox\|connectx' || true)
    if [[ -n "$MELLANOX_DEVICES" ]]; then
        print_success "Found Mellanox/ConnectX devices:"
        echo "$MELLANOX_DEVICES" | sed 's/^/  /'
    else
        print_warning "No Mellanox/ConnectX devices found via lspci"
    fi
else
    print_warning "lspci not available"
fi

echo ""
print_step "Step 2: Node role selection"
print_info "A two-node cluster requires one HEAD node and one WORKER node."
print_info "  - HEAD: Runs Ray head + vLLM API server"
print_info "  - WORKER: Runs Ray worker"
echo ""

while true; do
    read -p "Is this the HEAD or WORKER node? (head/worker): " ROLE
    ROLE=$(echo "$ROLE" | tr '[:upper:]' '[:lower:]')
    if [[ "$ROLE" == "head" ]] || [[ "$ROLE" == "worker" ]]; then
        break
    fi
    print_error "Invalid input. Please enter 'head' or 'worker'"
done

print_success "Configured as: $ROLE"

echo ""
print_step "Step 3: Network interface configuration"

# Suggest interface
if [[ -n "$DETECTED_IFACES" ]]; then
    FIRST_IFACE=$(echo "$DETECTED_IFACES" | head -n1)
    read -p "Enter the ConnectX interface name [$FIRST_IFACE]: " IFACE
    IFACE=${IFACE:-$FIRST_IFACE}
else
    read -p "Enter the ConnectX interface name: " IFACE
fi

# Validate interface exists
if ! ip link show "$IFACE" &> /dev/null; then
    print_error "Interface '$IFACE' not found!"
    print_info "Available interfaces:"
    ip -br link | awk '{print "  - " $1}'
    exit 1
fi

print_success "Using interface: $IFACE"

# Check interface status
IFACE_STATUS=$(ip -br link show "$IFACE" | awk '{print $2}')
if [[ "$IFACE_STATUS" == "DOWN" ]]; then
    print_warning "Interface $IFACE is currently DOWN"
    print_info "It will be brought up during link configuration (01-configure-link.sh)"
fi

echo ""
print_step "Step 4: IP address configuration"
print_info "Point-to-point /30 network configuration"
print_info "Standard setup: Head=192.168.40.1, Worker=192.168.40.2"
echo ""

if [[ "$ROLE" == "head" ]]; then
    DEFAULT_IP="192.168.40.1"
    DEFAULT_PEER_IP="192.168.40.2"
else
    DEFAULT_IP="192.168.40.2"
    DEFAULT_PEER_IP="192.168.40.1"
fi

read -p "Enter this node's IP address [$DEFAULT_IP]: " IP
IP=${IP:-$DEFAULT_IP}

read -p "Enter the peer node's IP address [$DEFAULT_PEER_IP]: " PEER_IP
PEER_IP=${PEER_IP:-$DEFAULT_PEER_IP}

print_success "This node: $IP"
print_success "Peer node: $PEER_IP"

echo ""
print_step "Step 5: Ray cluster configuration"

DEFAULT_MASTER_ADDR="192.168.40.1"
DEFAULT_MASTER_PORT="6379"

read -p "Enter Ray head address [$DEFAULT_MASTER_ADDR]: " MASTER_ADDR
MASTER_ADDR=${MASTER_ADDR:-$DEFAULT_MASTER_ADDR}

read -p "Enter Ray head port [$DEFAULT_MASTER_PORT]: " MASTER_PORT
MASTER_PORT=${MASTER_PORT:-$DEFAULT_MASTER_PORT}

print_success "Ray head: $MASTER_ADDR:$MASTER_PORT"

echo ""
print_step "Step 6: vLLM configuration"

DEFAULT_VLLM_PORT="8000"
DEFAULT_MODEL="Qwen/Qwen2.5-72B-Instruct"
DEFAULT_TP_SIZE="2"

read -p "Enter vLLM API port [$DEFAULT_VLLM_PORT]: " VLLM_PORT
VLLM_PORT=${VLLM_PORT:-$DEFAULT_VLLM_PORT}

read -p "Enter model name [$DEFAULT_MODEL]: " MODEL
MODEL=${MODEL:-$DEFAULT_MODEL}

read -p "Enter tensor parallel size [$DEFAULT_TP_SIZE]: " TP_SIZE
TP_SIZE=${TP_SIZE:-$DEFAULT_TP_SIZE}

print_success "Model: $MODEL"
print_success "Tensor parallel size: $TP_SIZE"
print_success "API port: $VLLM_PORT"

echo ""
print_step "Step 7: Writing configuration file"

cat > "$ENV_FILE" << EOF
# DGX Cluster Configuration
# Generated by setup.sh on $(date)

# Node role: head or worker
ROLE=$ROLE

# ConnectX-7 interface name
IFACE=$IFACE

# Point-to-point IP addresses (/30 network)
IP=$IP
PEER_IP=$PEER_IP

# Ray cluster coordination
MASTER_ADDR=$MASTER_ADDR
MASTER_PORT=$MASTER_PORT

# vLLM API server
VLLM_PORT=$VLLM_PORT

# Model to serve
MODEL=$MODEL

# Tensor parallel size (number of GPUs across cluster)
TP_SIZE=$TP_SIZE

# NCCL configuration (optional overrides)
NCCL_DEBUG=INFO
NCCL_IB_DISABLE=0
NCCL_IB_HCA=mlx5

# HuggingFace cache directories (optional)
# HF_HOME=\$HOME/.cache/huggingface
# TRANSFORMERS_CACHE=\$HF_HOME
EOF

if [[ -f "$ENV_FILE" ]]; then
    print_success "Configuration written to $ENV_FILE"
else
    print_error "Failed to write configuration file!"
    exit 1
fi

echo ""
print_step "Step 8: Verifying configuration"

print_info "Configuration summary:"
echo ""
echo "  Role:              $ROLE"
echo "  Interface:         $IFACE"
echo "  This node IP:      $IP"
echo "  Peer node IP:      $PEER_IP"
echo "  Ray head:          $MASTER_ADDR:$MASTER_PORT"
echo "  vLLM port:         $VLLM_PORT"
echo "  Model:             $MODEL"
echo "  Tensor parallel:   $TP_SIZE"
echo ""

print_success "Configuration complete!"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                      Next Steps                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [[ "$ROLE" == "head" ]]; then
    print_info "On this HEAD node, run:"
    echo ""
    echo "  1. bash scripts/00-detect-ifaces.sh     # Verify interface detection"
    echo "  2. bash scripts/01-configure-link.sh    # Configure network link"
    echo "  3. bash scripts/02-install-deps.sh      # Install dependencies"
    echo "  4. bash scripts/03-test-link.sh         # Test network (run after worker setup)"
    echo "  5. bash scripts/04-build-nccl-tests.sh  # Build NCCL tests"
    echo "  6. bash scripts/06-ray-head.sh          # Start Ray head"
    echo "  7. bash scripts/08-vllm-serve.sh        # Start vLLM (after step 6)"
    echo ""
    print_warning "Make sure to set up the WORKER node before testing the link!"
else
    print_info "On this WORKER node, run:"
    echo ""
    echo "  1. bash scripts/00-detect-ifaces.sh     # Verify interface detection"
    echo "  2. bash scripts/01-configure-link.sh    # Configure network link"
    echo "  3. bash scripts/02-install-deps.sh      # Install dependencies"
    echo "  4. bash scripts/03-test-link.sh         # Start iperf3 server"
    echo "  5. bash scripts/04-build-nccl-tests.sh  # Build NCCL tests"
    echo "  6. bash scripts/07-ray-worker.sh        # Connect to Ray head"
    echo ""
    print_warning "Make sure the HEAD node is set up and Ray head is running before step 6!"
fi

echo ""
print_info "For detailed information, see README.md"
print_info "Configuration file: $ENV_FILE"
echo ""

# Final checks
print_step "Step 9: Pre-flight checks"

# Check if scripts directory exists
if [[ -d "$SCRIPT_DIR/scripts" ]]; then
    print_success "Scripts directory found"
    
    # Check if scripts are executable
    NON_EXEC=$(find "$SCRIPT_DIR/scripts" -name "*.sh" ! -perm -u+x | wc -l)
    if [[ $NON_EXEC -gt 0 ]]; then
        print_warning "Some scripts are not executable"
        print_info "Making scripts executable..."
        chmod +x "$SCRIPT_DIR/scripts"/*.sh
        print_success "Scripts are now executable"
    else
        print_success "All scripts are executable"
    fi
else
    print_error "Scripts directory not found!"
    exit 1
fi

# Check for common issues
print_info ""
print_info "Checking for potential issues..."

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_warning "You are running as root"
    print_info "Some steps may require non-root user (e.g., Ray, vLLM)"
fi

# Check if interface has any existing IP
EXISTING_IPS=$(ip addr show "$IFACE" 2>/dev/null | grep "inet " | awk '{print $2}' || true)
if [[ -n "$EXISTING_IPS" ]]; then
    print_warning "Interface $IFACE already has IP address(es):"
    echo "$EXISTING_IPS" | sed 's/^/    /'
    print_info "These will be flushed when you run 01-configure-link.sh"
fi

# Check for Docker (optional, for Open WebUI)
if command -v docker &> /dev/null; then
    print_success "Docker is installed (for Open WebUI)"
else
    print_warning "Docker not found (optional, needed only for Open WebUI)"
fi

# Check for Python
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
    print_success "Python $PYTHON_VERSION found"
else
    print_error "Python 3 not found (required for Ray and vLLM)"
fi

echo ""
print_success "Setup complete! Ready to proceed with installation."
echo ""

