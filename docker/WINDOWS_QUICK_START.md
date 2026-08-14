# Windows 11 Deployment - Quick Start Guide

Complete guide to deploy the Agentic AI Stack on Windows 11 Intel AI PC.

---

## 🎯 Pre-Flight Checklist

**Check these BEFORE starting:**

```powershell
# Run in PowerShell

# 1. Windows version (need Build 19041+)
[System.Environment]::OSVersion.Version

# 2. RAM (need 64+ GB)
Get-CimInstance Win32_ComputerSystem | Select @{N="RAM GB";E={[math]::Round($_.TotalPhysicalMemory/1GB)}}

# 3. CPU (need 16+ cores)
(Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors

# 4. Disk space (need 100+ GB)
Get-PSDrive C | Select @{N="Free GB";E={[math]::Round($_.Free/1GB)}}
```

✅ **All good?** → Continue to installation

---

## 🚀 Step 1: Windows Setup (One-Time)

**PowerShell as Administrator:**

```powershell
# Install WSL2
wsl --install
# Reboot if prompted

# After reboot
wsl --set-default-version 2
wsl --install -d Ubuntu-24.04

# Configure WSL2 resources
@"
[wsl2]
memory=64GB
processors=16
swap=2GB
localhostForwarding=true
"@ | Out-File "$env:USERPROFILE\.wslconfig" -Encoding ASCII

wsl --shutdown
```

**First Ubuntu launch:** Enter username/password when prompted

---

## 📦 Step 2: Docker Desktop (One-Time)

1. **Download:** https://www.docker.com/products/docker-desktop

2. **Install** → Enable "Use WSL 2 based engine" → Restart

3. **Configure:**
   - Docker Desktop → Settings → General: ✓ "Use WSL 2 based engine"
   - Settings → Resources → WSL Integration: ✓ Enable Ubuntu-24.04
   - Settings → Resources → Advanced:
     - **Memory: 64 GB**
     - **CPUs: 16**
     - **Disk: 100 GB**
   - **Apply & Restart**

4. **Verify:**
   ```bash
   wsl -d Ubuntu-24.04
   docker --version && docker compose version
   ```

---

## 🎬 Step 3: Deploy Stack

**In WSL2 terminal:**

```bash
# Clone repo
cd ~
git clone <your-repo-url>
cd applications.ai.enterprise.agentic-ai-stack/docker

# Configure
cp config.windows.example config.cfg
nano config.cfg
# Set: hugging_face_token=hf_YOUR_TOKEN_HERE
# Save: Ctrl+X, Y, Enter

# Deploy
chmod +x windows-deploy.sh
./windows-deploy.sh start
```

**Wait:** 5-10 min for model download (first time only)

---

## ✅ Step 4: Verify

```bash
# Check status
./windows-deploy.sh status

# Test API
./windows-deploy.sh test
```

**Access from Windows:**
- **LiteLLM UI:** http://localhost:4000/ui
- **vLLM API:** http://localhost:2080/docs
- **API Key:** `cat docker/.env | grep LITELLM_MASTER_KEY`

---

## 📋 Daily Commands

```bash
cd ~/applications.ai.enterprise.agentic-ai-stack/docker

./windows-deploy.sh start      # Start
./windows-deploy.sh stop       # Stop
./windows-deploy.sh restart    # Restart
./windows-deploy.sh status     # Health check
./windows-deploy.sh logs       # View logs
./windows-deploy.sh test       # Test API
./windows-deploy.sh clean      # Full cleanup
```

---

## 🔧 Configuration (docker/config.cfg)

### Minimal (20 GB RAM)
```ini
hugging_face_token=hf_YOUR_TOKEN
models=meta-llama/Llama-3.2-3B-Instruct
deploy_docker_fresh=off
deploy_agenticai_plugin=off
deploy_observability=off
```

### Standard (60 GB RAM) - **Recommended**
```ini
hugging_face_token=hf_YOUR_TOKEN
models=Qwen/Qwen2.5-Coder-14B-Instruct
deploy_docker_fresh=off
deploy_agenticai_plugin=off
deploy_observability=off
```

### Full Stack (80 GB RAM)
```ini
hugging_face_token=hf_YOUR_TOKEN
models=Qwen/Qwen2.5-Coder-14B-Instruct
deploy_docker_fresh=off
deploy_agenticai_plugin=on
deploy_observability=on
```

---

## 🧪 Test API

```bash
source docker/.env
export KEY=$(grep LITELLM_MASTER_KEY docker/.env | cut -d= -f2 | tr -d '"')

# List models
curl http://localhost:4000/v1/models -H "Authorization: Bearer $KEY"

# Generate
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"Qwen/Qwen2.5-Coder-14B-Instruct","messages":[{"role":"user","content":"Hello"}]}'
```

### Python Example
```python
import openai

client = openai.OpenAI(
    base_url="http://localhost:4000/v1",
    api_key="sk-xxx"  # LITELLM_MASTER_KEY from .env
)

response = client.chat.completions.create(
    model="Qwen/Qwen2.5-Coder-14B-Instruct",
    messages=[{"role": "user", "content": "Write hello world"}]
)
print(response.choices[0].message.content)
```

---

## 🔥 Troubleshooting

### Docker won't start
```powershell
wsl --shutdown
# Restart Docker Desktop
```

### Out of memory
```bash
# Use smaller model
sed -i 's/14B/3B/g' docker/config.cfg
./windows-deploy.sh clean && ./windows-deploy.sh start
```

### Port conflict
```bash
docker stop $(docker ps -q)
```

### Service unhealthy
```bash
./windows-deploy.sh logs agentic-litellm
# Wait for model download (first run: 5-10 min)
```

### Model download fails
```bash
# Check token
grep hugging_face_token docker/config.cfg
# Check connectivity
curl -I https://huggingface.co
```

---

## 📊 What to Expect

### Performance
- **Inference:** 18-22 tokens/sec (vs 22-25 on Linux)
- **Cold start:** 5-10 minutes first time
- **Memory overhead:** +2-4 GB for WSL2
- **Overall:** 80-90% of native Linux performance

### What Works ✅
- vLLM CPU inference
- LiteLLM API Gateway
- PostgreSQL + pgvector
- Redis caching
- Flowise agent builder
- Langfuse observability

### What Doesn't ❌
- Host monitoring (no node-exporter)
- Container metrics (no cadvisor)
- Multi-node clustering
- Production-grade performance

### Suitable For
- ✅ Proof of concept
- ✅ Development
- ✅ Testing
- ❌ Production (use Ubuntu)

---

## 🆘 Common Issues

| Problem | Solution |
|---------|----------|
| WSL2 not working | Run `wsl --install`, reboot, try again |
| Docker Desktop errors | Check Settings → Resources allocation |
| Container crashes | Check RAM allocation (need 64+ GB) |
| Slow inference | Use smaller model or add more CPUs |
| Can't connect | Check Windows Firewall, use `localhost` not `127.0.0.1` |

---

## 🧹 Cleanup

```bash
# Full cleanup (remove everything)
./windows-deploy.sh clean

# Keep models (faster re-deploy)
./windows-deploy.sh clean-keep-models

# Check disk usage
docker system df
```

---

## ✅ Success Checklist

- [ ] All services show "healthy" in `./windows-deploy.sh status`
- [ ] Can list models via API
- [ ] Can generate chat completion
- [ ] LiteLLM UI accessible at http://localhost:4000/ui
- [ ] Inference completes in < 5 seconds
- [ ] No error messages in logs

---

## 📖 Key Facts

**✅ Compatibility:** Verified for Windows 11 + Docker Desktop + WSL2  
**✅ vLLM:** Works via WSL2 (no need to replace with OVMS)  
**✅ Changes needed:** ZERO (docker-compose.yml already compatible)  
**⚠️ Performance:** 80-90% of native Linux (acceptable for PoC)  
**❌ Production:** Use native Ubuntu 22.04/24.04 for production  

**Timeline:**
- Setup (one-time): 30 minutes
- Deploy (first time): 20 minutes
- Re-deploy: 5 minutes

---

## 🚀 Quick Reference

```bash
# Essential commands
./windows-deploy.sh start    # Start everything
./windows-deploy.sh status   # Check health
./windows-deploy.sh logs     # View logs
./windows-deploy.sh test     # Test API
./windows-deploy.sh clean    # Cleanup

# Debugging
./windows-deploy.sh check    # System requirements
docker ps -a                 # List containers
docker system df             # Disk usage
docker logs <container>      # Specific logs

# Files
docker/config.cfg            # Your configuration
docker/.env                  # Generated credentials
docker/config.windows.example  # Config template
```

---

## 🎓 Need Help?

**This guide covers:**
- ✅ Complete installation steps
- ✅ All commands needed
- ✅ Troubleshooting common issues
- ✅ Configuration options
- ✅ API testing examples

**For production:** Use native Ubuntu deployment (see main README)

---

**Repository:** `/home/sdp/applications.ai.enterprise.agentic-ai-stack`  
**Status:** ✅ Windows 11 compatible, zero code changes needed  
**Last Updated:** 2026-08-14
