#!/usr/bin/env bash
set -euo pipefail

echo "======================================================================"
echo "Setup Shared HuggingFace Model Cache"
echo "======================================================================"
echo ""

source "$(dirname "$0")/../scripts/utils.sh"

# Default shared cache location
SHARED_CACHE=${SHARED_CACHE:-/shared/huggingface-cache}

echo "This script sets up a shared HuggingFace cache between nodes."
echo "Useful for NFS/shared storage to avoid duplicate downloads."
echo ""
echo "Default location: $SHARED_CACHE"
read -p "Use this location? (yes/custom): " RESPONSE

if [[ "$RESPONSE" == "custom" ]]; then
    read -p "Enter custom cache path: " SHARED_CACHE
fi

echo ""
echo "Setting up shared cache at: $SHARED_CACHE"

# Create directory if it doesn't exist
if [[ ! -d "$SHARED_CACHE" ]]; then
    echo "Creating directory..."
    sudo mkdir -p "$SHARED_CACHE"
    sudo chown -R $USER:$USER "$SHARED_CACHE"
    echo "✓ Directory created"
else
    echo "✓ Directory already exists"
fi

# Update .env file
echo ""
echo "Updating .env file..."
ENV_FILE="$(dirname "$0")/../.env"

# Remove old HF_HOME lines if they exist
sed -i '/^HF_HOME=/d' "$ENV_FILE" 2>/dev/null || true
sed -i '/^TRANSFORMERS_CACHE=/d' "$ENV_FILE" 2>/dev/null || true

# Add new cache location
echo "" >> "$ENV_FILE"
echo "# Shared HuggingFace cache (configured by 11-setup-shared-cache.sh)" >> "$ENV_FILE"
echo "HF_HOME=$SHARED_CACHE" >> "$ENV_FILE"
echo "TRANSFORMERS_CACHE=$SHARED_CACHE" >> "$ENV_FILE"

echo "✓ .env updated"

# Create symlink from default location to shared cache
echo ""
echo "Creating symlink from default cache location..."
DEFAULT_CACHE="$HOME/.cache/huggingface"
if [[ -L "$DEFAULT_CACHE" ]]; then
    echo "  Symlink already exists"
elif [[ -d "$DEFAULT_CACHE" ]]; then
    echo "  Moving existing cache to shared location..."
    rsync -av "$DEFAULT_CACHE/" "$SHARED_CACHE/" || true
    rm -rf "$DEFAULT_CACHE"
    ln -s "$SHARED_CACHE" "$DEFAULT_CACHE"
    echo "  ✓ Migrated and symlinked"
else
    mkdir -p "$(dirname "$DEFAULT_CACHE")"
    ln -s "$SHARED_CACHE" "$DEFAULT_CACHE"
    echo "  ✓ Symlink created"
fi

echo ""
echo "======================================================================"
echo "Shared cache setup complete!"
echo "======================================================================"
echo ""
echo "Cache location: $SHARED_CACHE"
echo ""
echo "Benefits:"
echo "  • Models downloaded once, used by both nodes"
echo "  • Saves bandwidth and storage"
echo "  • Faster startup on worker node"
echo ""
echo "For NFS setup:"
echo "  1. On head: sudo apt install nfs-kernel-server"
echo "  2. Export: echo '$SHARED_CACHE *(rw,sync,no_subtree_check)' | sudo tee -a /etc/exports"
echo "  3. Reload: sudo exportfs -ra"
echo "  4. On worker: sudo mount 192.168.40.1:$SHARED_CACHE $SHARED_CACHE"
echo ""

