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

print_skip() {
    echo -e "${YELLOW}⊘${NC} $1 (skipped - already done)"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
STATE_FILE="$SCRIPT_DIR/.setup_state"

# Functions to check completion status
check_env_configured() {
    [[ -f "$ENV_FILE" ]] && source "$ENV_FILE" && [[ -n "${ROLE:-}" ]] && [[ -n "${IFACE:-}" ]]
}

check_link_configured() {
    [[ -n "${IFACE:-}" ]] && [[ -n "${IP:-}" ]] && ip addr show "$IFACE" 2>/dev/null | grep -q "$IP"
}

check_deps_installed() {
    command -v ray &>/dev/null && command -v iperf3 &>/dev/null && python3 -c "import vllm" 2>/dev/null
}

check_nccl_built() {
    [[ -f "$HOME/nccl-tests/build/all_reduce_perf" ]]
}

check_ray_running() {
    ray status &>/dev/null
}

check_vllm_running() {
    [[ -f "$SCRIPT_DIR/vllm.pid" ]] && kill -0 $(cat "$SCRIPT_DIR/vllm.pid" 2>/dev/null) 2>/dev/null
}

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║        DGX Cluster Setup - Interactive Configuration          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check if .env already exists and load it
EXISTING_CONFIG=false
RESUME_MODE=false

if [[ -f "$ENV_FILE" ]]; then
    EXISTING_CONFIG=true
    source "$ENV_FILE" 2>/dev/null || true
    
    echo ""
    print_success "Found existing configuration!"
    echo ""
    print_step "Current configuration:"
    echo "  Role:              ${ROLE:-not set}"
    echo "  Interface:         ${IFACE:-not set}"
    echo "  This node IP:      ${IP:-not set}"
    echo "  Peer node IP:      ${PEER_IP:-not set}"
    echo "  Ray head:          ${MASTER_ADDR:-not set}:${MASTER_PORT:-not set}"
    echo "  Model:             ${MODEL:-not set}"
    echo ""
    
    print_step "Checking installation status..."
    echo ""
    
    # Check each step
    if check_link_configured; then
        print_success "Network link configured"
    else
        print_warning "Network link not configured yet"
    fi
    
    if check_deps_installed; then
        print_success "Dependencies installed"
    else
        print_warning "Dependencies not installed yet"
    fi
    
    if check_nccl_built; then
        print_success "NCCL tests built"
    else
        print_warning "NCCL tests not built yet"
    fi
    
    if check_ray_running; then
        print_success "Ray is running"
    else
        print_warning "Ray is not running"
    fi
    
    if [[ "${ROLE:-}" == "head" ]] && check_vllm_running; then
        print_success "vLLM is running"
    elif [[ "${ROLE:-}" == "head" ]]; then
        print_warning "vLLM is not running"
    fi
    
    echo ""
    read -p "Continue with existing config and complete remaining steps? (yes/reconfigure/cancel) [yes]: " ACTION
    ACTION=${ACTION:-yes}
    
    if [[ "$ACTION" == "cancel" ]]; then
        print_info "Setup cancelled."
        exit 0
    elif [[ "$ACTION" == "reconfigure" ]]; then
        print_step "Backing up existing .env to .env.backup"
        cp "$ENV_FILE" "$ENV_FILE.backup"
        print_success "Backup created. Starting fresh configuration..."
        EXISTING_CONFIG=false
        RESUME_MODE=false
    else
        print_success "Resuming installation from existing configuration"
        RESUME_MODE=true
    fi
fi

# Only do configuration if not resuming
if [[ "$RESUME_MODE" == "false" ]]; then
    echo ""
    print_step "Step 1: Detecting network interfaces"
    print_info "Looking for Mellanox/NVIDIA ConnectX interfaces..."
    echo ""

# Try to detect ConnectX interfaces (exclude veth/lo/docker interfaces)
DETECTED_IFACES=$(ip -br link | grep -E 'mlx|eth|enp' | grep -v -E 'veth|docker|lo' | awk '{print $1}' || true)

if [[ -z "$DETECTED_IFACES" ]]; then
    print_warning "Could not auto-detect ConnectX interfaces"
    print_info "Available interfaces:"
    ip -br link | grep -v -E 'veth|docker|lo' | awk '{print "  - " $1, "(" $2 ")"}'
else
    print_success "Found potential interfaces:"
    echo "$DETECTED_IFACES" | while read iface; do
        if [[ -n "$iface" ]]; then
            STATUS=$(ip -br link show "$iface" 2>/dev/null | awk '{print $2}' || echo "UNKNOWN")
            echo "  - $iface ($STATUS)"
        fi
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
    print_info "Available interfaces (excluding virtual/docker):"
    ip -br link | grep -v -E 'veth|docker|lo' | awk '{print "  - " $1, "(" $2 ")"}'
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
else
    # Resume mode - load existing config
    source "$ENV_FILE"
    print_step "Using existing configuration from $ENV_FILE"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                 Starting Automated Installation                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

print_warning "This will now automatically:"
if [[ "$ROLE" == "head" ]]; then
    echo "  • Configure network link"
    echo "  • Install all dependencies (may require sudo)"
    echo "  • Build NCCL tests"
    echo "  • Start Ray head node"
    echo "  • Launch vLLM API server"
else
    echo "  • Configure network link"
    echo "  • Install all dependencies (may require sudo)"
    echo "  • Build NCCL tests"
    echo "  • Start iperf3 server for testing"
    echo "  • Wait for head node to be ready"
    echo "  • Connect to Ray cluster"
fi
echo ""

read -p "Continue with automated installation? (yes/no) [yes]: " CONTINUE
CONTINUE=${CONTINUE:-yes}
if [[ "$CONTINUE" != "yes" ]]; then
    echo ""
    print_info "Installation cancelled. You can run the scripts manually:"
    print_info "Configuration saved to: $ENV_FILE"
    print_info "See README.md for manual setup steps."
    echo ""
    exit 0
fi

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
print_success "Pre-flight checks complete!"

# ============================================================================
# AUTOMATED INSTALLATION
# ============================================================================

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              Running Installation Scripts                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Track if any step fails
INSTALL_FAILED=0

# Step 1: Configure network link
echo ""
if check_link_configured; then
    print_skip "Network link already configured"
else
    print_step "Running: 01-configure-link.sh"
    if bash "$SCRIPT_DIR/scripts/01-configure-link.sh"; then
        print_success "Network link configured"
    else
        print_error "Failed to configure network link"
        INSTALL_FAILED=1
    fi
fi

# Step 2: Install dependencies
if [[ $INSTALL_FAILED -eq 0 ]]; then
    echo ""
    if check_deps_installed; then
        print_skip "Dependencies already installed"
    else
        print_step "Running: 02-install-deps.sh (this may take several minutes)"
        print_info "Installing iperf3, MPI, NCCL, Ray, vLLM..."
        if bash "$SCRIPT_DIR/scripts/02-install-deps.sh"; then
            print_success "Dependencies installed"
        else
            print_error "Failed to install dependencies"
            INSTALL_FAILED=1
        fi
    fi
fi

# Step 3: Build NCCL tests
if [[ $INSTALL_FAILED -eq 0 ]]; then
    echo ""
    if check_nccl_built; then
        print_skip "NCCL tests already built"
    else
        print_step "Running: 04-build-nccl-tests.sh (this may take a few minutes)"
        if bash "$SCRIPT_DIR/scripts/04-build-nccl-tests.sh"; then
            print_success "NCCL tests built"
        else
            print_warning "NCCL tests build failed (non-critical)"
        fi
    fi
fi

# Role-specific steps
if [[ $INSTALL_FAILED -eq 0 ]]; then
    if [[ "$ROLE" == "head" ]]; then
        # HEAD NODE: Start Ray head and vLLM
        echo ""
        
        # Check if Ray is already running
        if check_ray_running; then
            print_skip "Ray head already running"
        else
            print_step "Running: 06-ray-head.sh"
            if bash "$SCRIPT_DIR/scripts/06-ray-head.sh"; then
                print_success "Ray head node started"
                echo ""
                print_step "Waiting 5 seconds for Ray to stabilize..."
                sleep 5
            else
                print_error "Failed to start Ray head"
                INSTALL_FAILED=1
            fi
        fi
        
        # Check if vLLM is already running
        if [[ $INSTALL_FAILED -eq 0 ]]; then
            echo ""
            if check_vllm_running; then
                print_skip "vLLM already running"
                print_info "PID: $(cat $SCRIPT_DIR/vllm.pid)"
                print_info "Logs: $SCRIPT_DIR/vllm.log"
                
                # Still check if API is responding
                if curl -s "http://${IP}:${VLLM_PORT}/v1/models" > /dev/null 2>&1; then
                    print_success "vLLM API is responding"
                else
                    print_warning "vLLM process running but API not responding"
                    print_info "Check logs: tail -f $SCRIPT_DIR/vllm.log"
                fi
            else
                print_step "Running: 08-vllm-serve.sh"
                print_info "Starting vLLM API server (this will run in background)"
                print_info "Model: $MODEL"
                print_warning "Note: First model load may take time to download from HuggingFace"
                
                # Run vLLM in background
                nohup bash "$SCRIPT_DIR/scripts/08-vllm-serve.sh" > "$SCRIPT_DIR/vllm.log" 2>&1 &
                VLLM_PID=$!
                echo $VLLM_PID > "$SCRIPT_DIR/vllm.pid"
                
                print_success "vLLM server starting in background (PID: $VLLM_PID)"
                print_info "Logs: $SCRIPT_DIR/vllm.log"
                print_info "To stop: kill \$(cat $SCRIPT_DIR/vllm.pid)"
                
                echo ""
                print_step "Waiting for vLLM API to be ready..."
                print_info "This may take several minutes for first-time model download..."
                
                # Wait for API to respond (with timeout)
                MAX_WAIT=600  # 10 minutes
                WAITED=0
                API_READY=0
                while [[ $WAITED -lt $MAX_WAIT ]]; do
                    if curl -s "http://${IP}:${VLLM_PORT}/v1/models" > /dev/null 2>&1; then
                        API_READY=1
                        break
                    fi
                    sleep 10
                    WAITED=$((WAITED + 10))
                    if [[ $((WAITED % 60)) -eq 0 ]]; then
                        print_info "Still waiting... (${WAITED}s elapsed)"
                    fi
                done
                
                if [[ $API_READY -eq 1 ]]; then
                    print_success "vLLM API is ready!"
                else
                    print_warning "API not responding yet. Check logs: tail -f $SCRIPT_DIR/vllm.log"
                fi
            fi
        fi
        
    else
        # WORKER NODE: Start iperf3 and connect to Ray
        echo ""
        
        # iperf3 server (check if already running)
        if pgrep -f "iperf3 -s" > /dev/null; then
            print_skip "iperf3 server already running"
        else
            print_step "Running: 03-test-link.sh (starting iperf3 server)"
            if bash "$SCRIPT_DIR/scripts/03-test-link.sh"; then
                print_success "iperf3 server started"
            else
                print_warning "iperf3 server failed to start (non-critical)"
            fi
        fi
        
        echo ""
        
        # Check if Ray worker is already connected
        if check_ray_running; then
            print_skip "Ray worker already connected to cluster"
        else
            print_warning "Worker node needs the HEAD node to be ready before connecting to Ray"
            read -p "Is the HEAD node Ray cluster ready? (yes/no/skip) [no]: " HEAD_READY
            HEAD_READY=${HEAD_READY:-no}
            
            if [[ "$HEAD_READY" == "yes" ]]; then
                echo ""
                print_step "Running: 07-ray-worker.sh"
                if bash "$SCRIPT_DIR/scripts/07-ray-worker.sh"; then
                    print_success "Ray worker connected to cluster"
                else
                    print_error "Failed to connect to Ray cluster"
                    print_info "Make sure HEAD node is running: $MASTER_ADDR:$MASTER_PORT"
                    INSTALL_FAILED=1
                fi
            else
                print_info "Skipping Ray worker connection"
                print_info "Run manually when head is ready: bash scripts/07-ray-worker.sh"
            fi
        fi
    fi
fi

# ============================================================================
# FINAL STATUS
# ============================================================================

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    Installation Complete                       ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [[ $INSTALL_FAILED -eq 0 ]]; then
    print_success "All installation steps completed successfully!"
    echo ""
    
    if [[ "$ROLE" == "head" ]]; then
        echo "╔════════════════════════════════════════════════════════════════╗"
        echo "║                    HEAD NODE - DEMO READY                      ║"
        echo "╚════════════════════════════════════════════════════════════════╝"
        echo ""
        print_success "Your DGX cluster is now serving LLMs!"
        echo ""
        print_info "API Endpoint:"
        echo "  http://${IP}:${VLLM_PORT}/v1"
        echo ""
        print_info "Test the API:"
        echo "  curl http://${IP}:${VLLM_PORT}/v1/models"
        echo ""
        echo "  curl http://${IP}:${VLLM_PORT}/v1/chat/completions \\"
        echo "    -H 'Content-Type: application/json' \\"
        echo "    -d '{"
        echo "      \"model\": \"${MODEL}\","
        echo "      \"messages\": [{\"role\":\"user\",\"content\":\"Hello!\"}]"
        echo "    }'"
        echo ""
        print_info "Monitor logs:"
        echo "  tail -f $SCRIPT_DIR/vllm.log"
        echo ""
        print_info "Ray dashboard (if enabled):"
        echo "  http://${IP}:8265"
        echo ""
        print_info "To setup Open WebUI:"
        echo "  cd openwebui"
        echo "  MASTER_ADDR=${IP} VLLM_PORT=${VLLM_PORT} docker compose up -d"
        echo "  Browse to http://${IP}:3000"
        echo ""
        
    else
        echo "╔════════════════════════════════════════════════════════════════╗"
        echo "║                   WORKER NODE - READY                          ║"
        echo "╚════════════════════════════════════════════════════════════════╝"
        echo ""
        print_success "Worker node is configured and ready!"
        echo ""
        print_info "Status:"
        echo "  • Network link: $IFACE at $IP"
        echo "  • iperf3 server: running"
        echo "  • Ray worker: $(systemctl --user is-active ray-worker 2>/dev/null || echo 'not running yet')"
        echo ""
        print_info "Test network from HEAD node:"
        echo "  iperf3 -c $IP -P 8 -t 10 -M 9000"
        echo ""
        print_info "Check Ray connection:"
        echo "  ray status"
        echo ""
    fi
    
    print_info "Documentation: $SCRIPT_DIR/README.md"
    print_info "Configuration: $ENV_FILE"
    
else
    print_error "Installation encountered errors"
    print_info "Check the output above for details"
    print_info "You can run individual scripts manually:"
    print_info "  bash scripts/01-configure-link.sh"
    print_info "  bash scripts/02-install-deps.sh"
    print_info "  etc."
fi

echo ""

