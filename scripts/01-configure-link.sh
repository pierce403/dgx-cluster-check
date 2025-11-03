#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../scripts/utils.sh"

: "${IFACE:?set IFACE in .env}"
: "${IP:?set IP in .env}"
: "${PEER_IP:?set PEER_IP in .env}"

sudo ip link set "$IFACE" up || true
sudo ip link set "$IFACE" mtu 9000 || true
sudo ip addr flush dev "$IFACE" || true
sudo ip addr add "$IP/30" dev "$IFACE"

# simple reachability check (will fail harmlessly if peer isn't up yet)
ping -c 2 -W 1 "$PEER_IP" || true
ip -br addr show dev "$IFACE"

