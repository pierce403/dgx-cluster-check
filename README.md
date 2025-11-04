# dgx-cluster-check

Turn two **NVIDIA DGX Spark** boxes from factory-fresh into a working **two-node LLM cluster** that serves an **OpenAI-compatible API** for **Open WebUI**. 

🚀 **One-command automated setup** or manual step-by-step—your choice. Scripts are idempotent and can be run individually or all at once.

> Target OS: **DGX OS 7 / Ubuntu 24.04** (stock DGX Spark image)
>
> Interconnect: **direct-attached ConnectX‑7** (no switch) using a DAC/optical QSFP-class cable
>
> Topology: **Spark 1 (rank 0 / head)** + **Spark 2 (rank 1 / worker)**

---

## What this repo does
- Detects your **ConnectX‑7** interface
- Brings up a **/30 point-to-point** link with **MTU 9000**
- Installs **iperf3, MPI, NCCL tests, Ray, vLLM** (and Docker option for Open WebUI)
- Verifies fabric with **iperf3** and **nccl-tests**
- Boots a tiny **Ray** cluster (head+worker) and launches **vLLM** in **tensor-parallel across both nodes**
- Exposes **`http://<head>:8000/v1`** (OpenAI-compatible) and guides **Open WebUI** to connect

---

## Repo layout
```
.
├─ README.md  ← this file
├─ env.example
├─ setup.sh   ← interactive configuration wizard
├─ scripts/
│  ├─ 00-detect-ifaces.sh
│  ├─ 01-configure-link.sh
│  ├─ 02-install-deps.sh
│  ├─ 03-test-link.sh
│  ├─ 04-build-nccl-tests.sh
│  ├─ 05-nccl-allreduce.sh
│  ├─ 06-ray-head.sh
│  ├─ 07-ray-worker.sh
│  ├─ 08-vllm-serve.sh
│  ├─ 09-openwebui-docker.sh
│  └─ utils.sh
├─ systemd/
│  ├─ ray-head.service
│  ├─ ray-worker.service
│  └─ vllm.service
└─ openwebui/
   └─ docker-compose.yml
```

> Copy `scripts/*` to both Sparks. Run steps in order on each box. You can also enable the optional **systemd** units once you like the setup.

---

## Quickstart (TL;DR)
**On both Sparks**
```bash
sudo apt update && sudo apt install -y git
cd ~ && git clone https://github.com/pierce403/dgx-cluster-check.git
cd dgx-cluster-check
```

**Option A: Automated setup (recommended) - One command to running demo!**
```bash
bash setup.sh
# Interactive prompts → Full installation → Running LLM cluster!
# Takes 10-30 minutes depending on model size
```

**Option B: Manual step-by-step**
```bash
cp env.example .env
```

Edit **.env** on each host:
```ini
# On Spark 1 (head)
ROLE=head
IFACE=cx70              # put the detected CX‑7 iface here
IP=192.168.40.1
PEER_IP=192.168.40.2
MASTER_ADDR=192.168.40.1
MASTER_PORT=6379
VLLM_PORT=8000
MODEL=Qwen/Qwen2.5-72B-Instruct  # change to your model
TP_SIZE=2

# On Spark 2 (worker)
ROLE=worker
IFACE=cx70
IP=192.168.40.2
PEER_IP=192.168.40.1
MASTER_ADDR=192.168.40.1
MASTER_PORT=6379
VLLM_PORT=8000
MODEL=Qwen/Qwen2.5-72B-Instruct
TP_SIZE=2
```

**Run the steps**
```bash
# BOTH NODES
bash scripts/00-detect-ifaces.sh
bash scripts/01-configure-link.sh
bash scripts/02-install-deps.sh
bash scripts/03-test-link.sh        # iperf3 sanity check
bash scripts/04-build-nccl-tests.sh # builds nccl-tests

# OPTIONAL: run cross-node NCCL perf test from Spark 1
bash scripts/05-nccl-allreduce.sh spark1 spark2

# CLUSTER: start Ray
# Spark 1
bash scripts/06-ray-head.sh
# Spark 2
bash scripts/07-ray-worker.sh

# SERVE: start vLLM on Spark 1
bash scripts/08-vllm-serve.sh
# test
curl http://$MASTER_ADDR:$VLLM_PORT/v1/models
```

**Open WebUI** (option A: use your existing Open WebUI):
- In Open WebUI → Admin → Settings → **Connections** → **Add OpenAI-compatible**
- Base URL: `http://$MASTER_ADDR:$VLLM_PORT/v1`
- API key: any placeholder
- Test → Save → Pick the model

**Open WebUI (option B: launch locally via Docker Compose)**
```bash
cd openwebui
MASTER_ADDR=192.168.40.1 VLLM_PORT=8000 docker compose up -d
# then browse to http://<spark1>:3000 and add provider pointing to http://<spark1>:8000/v1
```

---

## Step-by-step scripts
All scripts source `utils.sh` and `.env`. They are safe to re-run.

### `scripts/utils.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
source "$ROOT/.env"

# Activate Python virtual environment if it exists
VENV_DIR="$ROOT/venv"
if [[ -d "$VENV_DIR" ]]; then
    source "$VENV_DIR/bin/activate"
fi

export NCCL_SOCKET_IFNAME=${IFACE}
export NCCL_DEBUG=${NCCL_DEBUG:-INFO}
export NCCL_IB_DISABLE=${NCCL_IB_DISABLE:-0}
export NCCL_IB_HCA=${NCCL_IB_HCA:-mlx5}
export HF_HOME=${HF_HOME:-$HOME/.cache/huggingface}
export TRANSFORMERS_CACHE=${TRANSFORMERS_CACHE:-$HF_HOME}
```

### `scripts/00-detect-ifaces.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail

# Lists Mellanox/NVIDIA ConnectX interfaces and best-guess IFACE
ip -d link | awk '/mlx|mellanox|connectx|mlx5/{print prev "\n" $0}{prev=$0}' || true
echo "\nDetected NICs:"
ip -br link | awk '{print $1, $2, $3}'

echo "\nIf your ConnectX-7 iface is unknown, try:"
echo "  sudo lspci | egrep -i 'mellanox|connectx'"
echo "  ls -l /sys/class/net"
```

### `scripts/01-configure-link.sh`
```bash
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

# simple reachability check (will fail harmlessly if peer isn’t up yet)
ping -c 2 -W 1 "$PEER_IP" || true
ip -br addr show dev "$IFACE"
```

### `scripts/02-install-deps.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail

# Installs system packages via apt
sudo apt update
sudo apt install -y iperf3 openmpi-bin libopenmpi-dev rdma-core perftest git build-essential \
                    python3-pip python3-venv python3-full libnccl2 libnccl-dev

# Creates a Python virtual environment at ./venv
# Installs Ray and vLLM in the venv (avoids system-wide install issues)
python3 -m venv venv
source venv/bin/activate
pip install -U pip wheel
pip install -U ray[default] vllm
```

> **Note:** All Python packages are installed in a virtual environment (`./venv`) to comply with PEP 668 on Ubuntu 24.04+. The `utils.sh` script automatically activates this venv.

### `scripts/03-test-link.sh`
```bash
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
```

### `scripts/04-build-nccl-tests.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$HOME"
if [[ ! -d nccl-tests ]]; then
  git clone https://github.com/NVIDIA/nccl-tests.git
fi
cd nccl-tests && make -j
```

### `scripts/05-nccl-allreduce.sh`
```bash
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
```

### `scripts/06-ray-head.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../scripts/utils.sh"

ray stop || true
ray start --head --node-ip-address="$IP" --port="$MASTER_PORT"
```

### `scripts/07-ray-worker.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../scripts/utils.sh"

ray stop || true
ray start --address="${MASTER_ADDR}:${MASTER_PORT}"
```

### `scripts/08-vllm-serve.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../scripts/utils.sh"

if [[ "${ROLE}" != "head" ]]; then
  echo "Run vLLM only on the head node."; exit 1
fi

# Optional: pre-auth with HuggingFace if needed
# huggingface-cli login --token YOUR_TOKEN

# Launch vLLM distributed using Ray
exec python3 -m vllm.entrypoints.api_server ${MODEL:+--model $MODEL} \
  --host 0.0.0.0 --port "${VLLM_PORT}" \
  --distributed-executor-backend ray \
  --ray-address "${MASTER_ADDR}:${MASTER_PORT}" \
  --tensor-parallel-size "${TP_SIZE:-2}"
```

### `scripts/09-openwebui-docker.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../openwebui"
MASTER_ADDR=${MASTER_ADDR:-192.168.40.1} VLLM_PORT=${VLLM_PORT:-8000} docker compose up -d
```

---

## systemd units (optional)
### `systemd/ray-head.service`
```ini
[Unit]
Description=Ray head node
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/home/%i/dgx-cluster-check/.env
ExecStart=/usr/bin/ray start --head --node-ip-address=%h --port=${MASTER_PORT}
ExecStop=/usr/bin/ray stop
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

### `systemd/ray-worker.service`
```ini
[Unit]
Description=Ray worker
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/home/%i/dgx-cluster-check/.env
ExecStart=/usr/bin/ray start --address=${MASTER_ADDR}:${MASTER_PORT}
ExecStop=/usr/bin/ray stop
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

### `systemd/vllm.service`
```ini
[Unit]
Description=vLLM API server
After=ray-head.service

[Service]
Type=simple
EnvironmentFile=/home/%i/dgx-cluster-check/.env
WorkingDirectory=/home/%i/dgx-cluster-check
ExecStart=/usr/bin/env bash scripts/08-vllm-serve.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

> Enable examples (as user services):
```bash
# on Spark 1
loginctl enable-linger $USER
systemctl --user daemon-reload
systemctl --user enable --now ray-head.service
systemctl --user enable --now vllm.service

# on Spark 2
loginctl enable-linger $USER
systemctl --user daemon-reload
systemctl --user enable --now ray-worker.service
```

---

## Open WebUI via Docker Compose
`openwebui/docker-compose.yml`
```yaml
version: "3.8"
services:
  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    ports:
      - "3000:8080"
    environment:
      - WEBUI_NAME=DGX Cluster UI
      - ENABLE_OPENAI_API=True
      - OPENAI_API_BASE_URL=http://${MASTER_ADDR}:${VLLM_PORT}/v1
      - OPENAI_API_KEY=local
    volumes:
      - openwebui_data:/app/backend/data
    restart: unless-stopped
volumes:
  openwebui_data: {}
```

---

## Troubleshooting
- **Wrong NIC used by NCCL** → ensure `NCCL_SOCKET_IFNAME=$IFACE` exported on **both** nodes.
- **iperf3 poor throughput** → verify you’re testing over the CX‑7 IPs; MTU set to 9000 on both; cable seated.
- **Ray worker fails to join** → check `MASTER_ADDR`, firewall, and that head is listening on the CX‑7 IP.
- **HF model auth** → set HF token and accept model licenses; large models may require manual EULA acceptance.
- **OOM / model too large** → use a smaller model or increase tensor parallel degree; confirm VRAM/GB memory needs.

---

## Roadmap
- Add **TensorRT-LLM** option with `trtllm-serve --openai-compatible`
- Add **Kubernetes** manifests for two-node bare-metal cluster
- Collect **prometheus/grafana** dashboards (CX‑7, NCCL, Ray, vLLM)

---

## License
MIT (you can change later)

## Contributing
PRs welcome. Keep each step script simple, POSIXy, and re-runnable.

