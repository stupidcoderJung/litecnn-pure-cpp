# CI/CD Pipeline

## Overview

Automated deployment pipeline from GPU server to M1 Mac MPS server.

## Architecture

```
GPU Server (192.168.0.40)
  ├─ Train model (Cycle N)
  ├─ Save best_model.pth
  └─ Trigger export (manual or automatic)
       ↓
  ├─ Export to TorchScript (MPS-optimized)
  ├─ Transfer to M1 Mac
       ↓
M1 MacBook Air (192.168.0.59)
  ├─ Watch for new models (every 30 min)
  ├─ Download TorchScript model
  ├─ Build & Deploy MPS server
  └─ Notify Discord
```

## Components

### 1. GPU Server Export Script
**Location**: `scripts/mps/export_model.py`

Converts PyTorch checkpoint to TorchScript:
```bash
python3 scripts/mps/export_model.py
```

### 2. M1 Mac Watcher
**Location**: `scripts/mps/watch_and_deploy_mps.sh`

Monitors GPU server for new training cycles:
- Runs every 30 minutes (LaunchAgent)
- Checks for new `checkpoints_cycleN/` directories
- Downloads and deploys automatically

### 3. M1 Mac Deployer
**Location**: `scripts/mps/deploy_mps_server.sh`

Deploys MPS server locally:
```bash
bash scripts/mps/deploy_mps_server.sh
```

### 4. LaunchAgent
**Location**: `~/Library/LaunchAgents/com.litecnn.mps.autodeploy.plist`

Runs watcher every 30 minutes:
```bash
launchctl load ~/Library/LaunchAgents/com.litecnn.mps.autodeploy.plist
```

## Manual Deployment

### From GPU Server
```bash
# On GPU server
cd ~/mycnn
bash /path/to/scripts/mps/deploy_from_gpu.sh 13
```

### On M1 Mac
```bash
# Build and run
cd ~/projects/litecnn-pure-cpp
make -f Makefile.mps
./build/litecnn_server_mps
```

## Automatic Deployment

### Setup (One-time)

1. **Install LaunchAgent**:
```bash
cp scripts/mps/com.litecnn.mps.autodeploy.plist \
   ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.litecnn.mps.autodeploy.plist
```

2. **Verify**:
```bash
launchctl list | grep litecnn
tail -f /tmp/mps-autodeploy.log
```

### Workflow

1. **Train** new model on GPU server (Cycle N)
2. **Save** `checkpoints_cycleN/best_model.pth`
3. **Wait** up to 30 minutes (or trigger manually)
4. **Automatic**:
   - Watcher detects new cycle
   - Exports to TorchScript
   - Downloads to M1 Mac
   - Deploys MPS server
   - Sends Discord notification

## Monitoring

### Status
```bash
launchctl list | grep litecnn
```

### Logs
```bash
# Auto-deploy watcher
tail -f /tmp/mps-autodeploy.log

# Server
tail -f /tmp/mps_server.log
```

### Health Check
```bash
curl http://localhost:8893/health | jq
```

## Troubleshooting

### Watcher not running
```bash
launchctl unload ~/Library/LaunchAgents/com.litecnn.mps.autodeploy.plist
launchctl load ~/Library/LaunchAgents/com.litecnn.mps.autodeploy.plist
```

### Manual trigger
```bash
bash /Users/young/projects/litecnn-pure-cpp/scripts/mps/watch_and_deploy_mps.sh
```

### Check state
```bash
cat /tmp/mps-autodeploy-state.txt  # Last deployed cycle
```

## Port Configuration

- **8891**: AS-IS (Pure C++ production, legacy)
- **8892**: TO-BE (Pure C++ experimental, legacy)
- **8893**: MPS (LibTorch GPU-accelerated) ← **Main Production**

## Deployment History

State file: `/tmp/mps-autodeploy-state.txt`

View deployment log:
```bash
grep "Deployment Complete" /tmp/mps-autodeploy.log
```
