# Open WebUI Integration Guide

This guide shows how to connect Open WebUI to your DGX vLLM cluster.

## Key Differences: Ollama vs vLLM

| Feature | Ollama | vLLM on DGX Cluster |
|---------|--------|---------------------|
| Model Format | GGUF (quantized) | HuggingFace Transformers |
| Storage | `/root/.ollama` | `~/.cache/huggingface` |
| API | Ollama-specific | OpenAI-compatible |
| GPU Support | Single GPU | Multi-GPU, Multi-node |
| Best For | Local inference, quantized models | Large models, distributed inference |

**You can use BOTH simultaneously!** They serve different purposes and model types.

---

## Option 1: Reconfigure Existing Container

If you're already running `open-webui:ollama`, keep it and add vLLM as an additional provider:

### Via Web UI (Easiest)

1. Open your Open WebUI at `http://your-ip:8080`
2. Click your profile → **Admin Panel**
3. Go to **Settings** → **Connections**
4. Click **"+"** to add a new connection
5. Fill in:
   - **Type**: OpenAI
   - **Name**: DGX vLLM Cluster
   - **Base URL**: `http://192.168.40.1:8000/v1`
   - **API Key**: `sk-dummy` (any value, vLLM doesn't require auth)
6. Click **Test** → **Save**

Now you'll see both Ollama and vLLM models in your model selector!

### Via Docker Environment Variables

```bash
# Stop current container
docker stop open-webui
docker rm open-webui

# Restart with vLLM connection
docker run -d -p 8080:8080 \
  --gpus=all \
  -v open-webui:/app/backend/data \
  -v open-webui-ollama:/root/.ollama \
  -e OPENAI_API_BASE_URLS="http://192.168.40.1:8000/v1" \
  -e OPENAI_API_KEYS="sk-dummy" \
  --add-host host.docker.internal:host-gateway \
  --name open-webui \
  ghcr.io/open-webui/open-webui:ollama
```

---

## Option 2: Use Provided Docker Compose

The repo includes a pre-configured `docker-compose.yml`:

```bash
cd dgx-cluster-check/openwebui

# Load environment variables from main .env
source ../.env

# Start Open WebUI
docker compose up -d

# View logs
docker compose logs -f

# Access at http://192.168.40.1:3000
```

The compose file automatically connects to your vLLM cluster using the IPs from `.env`.

### Configure Both Ollama and vLLM

Edit `openwebui/docker-compose.yml` and uncomment the Ollama line:

```yaml
environment:
  - OPENAI_API_BASE_URLS=http://192.168.40.1:8000/v1
  - OPENAI_API_KEYS=sk-dummy
  - OLLAMA_BASE_URL=http://host.docker.internal:11434  # Uncomment this
```

Then restart:
```bash
docker compose down && docker compose up -d
```

---

## Sharing Model Storage

### Different Model Formats = Different Storage

**Ollama models** (GGUF): Can't be used by vLLM directly  
**HuggingFace models** (vLLM): Can't be used by Ollama directly

**They're complementary!** Use:
- **Ollama** for quantized models (4-bit, 5-bit) - great for smaller GPUs
- **vLLM** for full models with tensor parallelism - great for large models across GPUs

### Share HuggingFace Cache Between Head/Worker

To avoid downloading models twice:

```bash
# On both nodes, run:
bash scripts/11-setup-shared-cache.sh
```

This sets up a shared HuggingFace cache location.

#### For NFS Setup (Recommended for Production)

**On HEAD node:**
```bash
# Install NFS server
sudo apt install nfs-kernel-server

# Create shared directory
sudo mkdir -p /shared/huggingface-cache
sudo chown $USER:$USER /shared/huggingface-cache

# Export it
echo '/shared/huggingface-cache 192.168.40.2(rw,sync,no_subtree_check)' | sudo tee -a /etc/exports

# Apply
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
```

**On WORKER node:**
```bash
# Install NFS client
sudo apt install nfs-common

# Create mount point
sudo mkdir -p /shared/huggingface-cache

# Mount
sudo mount 192.168.40.1:/shared/huggingface-cache /shared/huggingface-cache

# Make permanent (add to /etc/fstab)
echo '192.168.40.1:/shared/huggingface-cache /shared/huggingface-cache nfs defaults 0 0' | sudo tee -a /etc/fstab
```

**Then on both nodes:**
```bash
# Update .env to use shared cache
echo "HF_HOME=/shared/huggingface-cache" >> .env
echo "TRANSFORMERS_CACHE=/shared/huggingface-cache" >> .env

# Restart vLLM
pkill -f vllm
bash scripts/08-vllm-serve.sh
```

---

## Testing Your Setup

### Test vLLM Endpoint

```bash
# List available models
curl http://192.168.40.1:8000/v1/models

# Test chat completion
curl http://192.168.40.1:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-72B-Instruct",
    "messages": [{"role":"user","content":"Hello!"}]
  }'
```

### Access Open WebUI

1. Open browser to `http://192.168.40.1:3000` (or port 8080 for existing container)
2. Create account (first user becomes admin)
3. Select model from dropdown
4. Start chatting!

---

## Recommended Setup: Best of Both Worlds

Run Ollama on the **same machine** as Open WebUI for quick quantized inference, and connect to the **DGX cluster** for heavy-duty large model inference:

```bash
# On your workstation/laptop:
docker run -d -p 8080:8080 \
  --gpus=all \
  -v open-webui:/app/backend/data \
  -v open-webui-ollama:/root/.ollama \
  -e OPENAI_API_BASE_URLS="http://192.168.40.1:8000/v1" \
  -e OPENAI_API_KEYS="sk-dummy" \
  -e OLLAMA_BASE_URL="http://host.docker.internal:11434" \
  --add-host host.docker.internal:host-gateway \
  --name open-webui \
  ghcr.io/open-webui/open-webui:ollama
```

Now you can:
- Use **Ollama** for fast responses with quantized models (llama3.2:3b, phi3, etc.)
- Use **vLLM cluster** for full-precision large models (Qwen2.5-72B, etc.)

---

## Troubleshooting

### Can't connect to vLLM

```bash
# On head node, check vLLM is running:
curl http://192.168.40.1:8000/v1/models

# Check logs:
tail -f dgx-cluster-check/vllm.log

# Restart if needed:
pkill -f vllm
bash dgx-cluster-check/scripts/08-vllm-serve.sh
```

### Open WebUI can't reach cluster

```bash
# From Open WebUI container:
docker exec -it open-webui curl http://192.168.40.1:8000/v1/models

# Check Docker network:
docker network inspect bridge
```

### Models not showing up

Check that vLLM has successfully loaded the model:
```bash
grep -i "loaded" dgx-cluster-check/vllm.log
```

---

## Performance Tips

1. **Use vLLM for**: Large models (70B+), multi-GPU inference, high throughput
2. **Use Ollama for**: Quick responses, smaller models, development/testing
3. **Share cache**: Use NFS to avoid duplicate downloads
4. **Monitor**: Check Ray dashboard at `http://192.168.40.1:8265`

---

## Summary

| Setup | When to Use |
|-------|-------------|
| **Existing Ollama + vLLM endpoint** | Keep both, best of both worlds |
| **New docker-compose** | Clean setup just for DGX cluster |
| **Shared HuggingFace cache** | Multi-node setups, save bandwidth |
| **NFS mount** | Production deployments |

The models are **different formats** - Ollama and vLLM serve different use cases. Use both!

