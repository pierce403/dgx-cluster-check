#!/usr/bin/env bash
set -euo pipefail

# Lists Mellanox/NVIDIA ConnectX interfaces and best-guess IFACE
ip -d link | awk '/mlx|mellanox|connectx|mlx5/{print prev "\n" $0}{prev=$0}' || true
echo "\nDetected NICs:"
ip -br link | awk '{print $1, $2, $3}'

echo "\nIf your ConnectX-7 iface is unknown, try:"
echo "  sudo lspci | egrep -i 'mellanox|connectx'"
echo "  ls -l /sys/class/net"

