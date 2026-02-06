#!/bin/bash
# MPS Auto-Deploy Watcher
# Monitors GPU server for new training cycles and auto-deploys to M1 Mac

set -e

PROJECT_DIR="/Users/young/projects/litecnn-pure-cpp"
LOG_FILE="/tmp/mps-autodeploy.log"
STATE_FILE="/tmp/mps-autodeploy-state.txt"

GPU_SERVER="love-lee@192.168.0.40"
GPU_CHECKPOINT_BASE="/home/love-lee/mycnn"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Get last deployed cycle
if [ -f "$STATE_FILE" ]; then
    LAST_CYCLE=$(cat "$STATE_FILE")
else
    LAST_CYCLE=0
fi

log "========================================="
log "MPS Auto-Deploy Watcher"
log "Last deployed cycle: $LAST_CYCLE"
log "========================================="

# Check for new cycles on GPU server
LATEST_CYCLE=$(sshpass -p '1' ssh -o StrictHostKeyChecking=no $GPU_SERVER \
    "ls -d ${GPU_CHECKPOINT_BASE}/checkpoints_cycle* 2>/dev/null | \
     sed 's/.*cycle//' | sort -n | tail -1" || echo "0")

log "Latest cycle on GPU server: $LATEST_CYCLE"

if [ "$LATEST_CYCLE" -le "$LAST_CYCLE" ]; then
    log "No new cycle to deploy. Exiting."
    exit 0
fi

log "🆕 New cycle detected: $LATEST_CYCLE (previous: $LAST_CYCLE)"

# Check if training is complete (best_model.pth exists and is stable)
CHECKPOINT_PATH="${GPU_CHECKPOINT_BASE}/checkpoints_cycle${LATEST_CYCLE}/best_model.pth"
MODEL_EXISTS=$(sshpass -p '1' ssh -o StrictHostKeyChecking=no $GPU_SERVER \
    "[ -f $CHECKPOINT_PATH ] && echo 'yes' || echo 'no'")

if [ "$MODEL_EXISTS" != "yes" ]; then
    log "⏳ Cycle $LATEST_CYCLE training not complete yet. Waiting..."
    exit 0
fi

log "✅ Cycle $LATEST_CYCLE training complete. Starting deployment..."

# 1. Export to TorchScript on GPU server
log "🔄 Converting to TorchScript on GPU server..."
EXPORT_SCRIPT=$(cat << 'EOFPY'
import torch
import sys
sys.path.append('/home/love-lee/mycnn/src')
from models.LiteCNNPro import LiteCNNPro

cycle = int(sys.argv[1])
checkpoint_path = f'/home/love-lee/mycnn/checkpoints_cycle{cycle}/best_model.pth'
output_path = f'/home/love-lee/mycnn/checkpoints_cycle{cycle}/cycle{cycle}_mps_traced.pt'

checkpoint = torch.load(checkpoint_path, map_location='cpu', weights_only=False)
print(f"Loaded: Epoch {checkpoint['epoch']}, Val Acc {checkpoint['val_acc']:.2f}%")

model = LiteCNNPro(num_classes=130, dropout=0.5)
model.load_state_dict(checkpoint['model_state_dict'])
model.eval()

dummy_input = torch.randn(1, 3, 224, 224)
traced = torch.jit.trace(model, dummy_input)
traced = torch.jit.optimize_for_inference(traced)

torch.jit.save(traced, output_path)
print(f"Exported: {output_path}")
EOFPY
)

sshpass -p '1' ssh -o StrictHostKeyChecking=no $GPU_SERVER \
    "~/jupyter-env/bin/python3 << 'EOFPY'
$EXPORT_SCRIPT
EOFPY
" $LATEST_CYCLE

# 2. Download TorchScript model
log "📥 Downloading TorchScript model..."
REMOTE_PT="${GPU_CHECKPOINT_BASE}/checkpoints_cycle${LATEST_CYCLE}/cycle${LATEST_CYCLE}_mps_traced.pt"
LOCAL_PT="$PROJECT_DIR/weights/cycle${LATEST_CYCLE}_mps_traced.pt"

sshpass -p '1' scp -o StrictHostKeyChecking=no \
    "${GPU_SERVER}:${REMOTE_PT}" \
    "$LOCAL_PT"

# 3. Update symlink
cd "$PROJECT_DIR/weights"
ln -sf "cycle${LATEST_CYCLE}_mps_traced.pt" "cycle13_mps_traced.pt"
log "✅ Model symlink updated"

# 4. Deploy MPS server
log "🚀 Deploying MPS server..."
bash "$PROJECT_DIR/scripts/mps/deploy_mps_server.sh"

# 5. Update state
echo "$LATEST_CYCLE" > "$STATE_FILE"
log "✅ State updated: $LATEST_CYCLE"

# 6. Notify
log "📢 Sending notification..."
if [ -x "$PROJECT_DIR/scripts/notify_discord.sh" ]; then
    "$PROJECT_DIR/scripts/notify_discord.sh" \
        "🚀 MPS Auto-Deploy Complete" \
        "Cycle $LATEST_CYCLE deployed to Port 8893" \
        "success" || true
fi

log "========================================="
log "Deployment Complete: Cycle $LATEST_CYCLE"
log "========================================="
