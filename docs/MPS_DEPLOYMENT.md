# MPS Server Deployment Guide

## Architecture

```
GPU Server (192.168.0.40)
  └─ Train model (Cycle N)
  └─ Export to TorchScript (MPS-optimized)
  └─ Transfer to M1 Mac
       ↓
M1 MacBook Air (192.168.0.59)
  └─ Receive TorchScript model
  └─ Build & Deploy MPS server
  └─ Serve on Port 8893
```

## Performance

| Implementation | Inference Time | Device | Improvement |
|----------------|----------------|--------|-------------|
| Pure C++ (CPU) | 216ms | CPU | Baseline |
| LibTorch (MPS) | **6-8ms** | M1 GPU | **35x faster** |

## Manual Deployment

### On GPU Server (After Training)

```bash
cd ~/mycnn
bash /path/to/scripts/mps/deploy_from_gpu.sh 13
```

### On M1 Mac (Manual)

```bash
cd ~/projects/litecnn-pure-cpp

# Build
make -f Makefile.mps

# Run
./build/litecnn_server_mps
```

## Automatic Deployment

### Setup (One-time)

1. **GPU Server**: Add to training script
```python
import subprocess
subprocess.run([
    "bash", "/path/to/scripts/mps/deploy_from_gpu.sh", 
    str(cycle_number)
], check=True)
```

2. **M1 Mac**: Enable auto-restart on model update
```bash
# Add to crontab
*/5 * * * * /Users/young/projects/litecnn-pure-cpp/scripts/mps/check_and_restart.sh
```

## Server Management

### Start
```bash
cd ~/projects/litecnn-pure-cpp
nohup ./build/litecnn_server_mps > /tmp/mps_server.log 2>&1 &
```

### Stop
```bash
pkill -9 litecnn_server_mps
```

### Status
```bash
curl http://localhost:8893/health | jq
```

### Logs
```bash
tail -f /tmp/mps_server.log
```

## API Usage

### Health Check
```bash
curl http://192.168.0.59:8893/health
```

### Predict (Multipart Upload)
```bash
curl -X POST http://192.168.0.59:8893/predict \
  -F "image=@/path/to/dog.jpg" | jq
```

### Response Format
```json
{
  "predictions": [
    {
      "rank": 1,
      "class_id": 12,
      "breed_en": "Border collie",
      "breed_ko": "보더 콜리",
      "confidence": 57.08
    }
  ],
  "timing": {
    "total_ms": 11.103,
    "preprocess_ms": 6.997,
    "inference_ms": 7.486,
    "transfer_ms": 3.509
  }
}
```

## Troubleshooting

### Server won't start
```bash
# Check if port is already in use
lsof -i :8893

# Check model file
ls -lh weights/cycle13_mps_traced.pt

# Check logs
tail -50 /tmp/mps_server.log
```

### MPS not available
- Requires macOS 12.3+ and M1/M2 Mac
- Check: `python3 -c "import torch; print(torch.backends.mps.is_available())"`

### Model not found
```bash
# Re-download from GPU server
scp love-lee@192.168.0.40:~/mycnn/checkpoints_cycle13/cycle13_mps_traced.pt \
    weights/
```

## Model Updates

When a new Cycle completes on GPU server:

1. **Automatic**: Script runs `deploy_from_gpu.sh`
2. Model is converted to TorchScript
3. Transferred to M1 Mac
4. Server auto-restarts
5. Discord notification sent

## Port Configuration

- **8891**: AS-IS (Pure C++ production)
- **8892**: TO-BE (Pure C++ experimental)
- **8893**: MPS (LibTorch GPU-accelerated) ← **Main**
