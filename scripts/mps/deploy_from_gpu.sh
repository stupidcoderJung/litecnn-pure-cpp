#!/bin/bash
# GPU Server → M1 Mac MPS Deployment Script
# Run this on GPU server after training completes

set -e

# Configuration
CYCLE=$1
GPU_SERVER="192.168.0.40"
M1_MAC="192.168.0.59"
M1_USER="young"

if [ -z "$CYCLE" ]; then
    echo "Usage: $0 <cycle_number>"
    echo "Example: $0 13"
    exit 1
fi

CHECKPOINT_DIR="/home/love-lee/mycnn/checkpoints_cycle${CYCLE}"
BEST_MODEL="$CHECKPOINT_DIR/best_model.pth"
EXPORT_SCRIPT="/home/love-lee/mycnn/scripts/export_mps.py"
OUTPUT_PT="${CHECKPOINT_DIR}/cycle${CYCLE}_mps_traced.pt"

M1_PROJECT="/Users/young/projects/litecnn-pure-cpp"
M1_WEIGHTS="$M1_PROJECT/weights"

echo "========================================="
echo "MPS Model Deployment (GPU → M1 Mac)"
echo "Cycle: $CYCLE"
echo "========================================="

# 1. Check checkpoint exists
if [ ! -f "$BEST_MODEL" ]; then
    echo "❌ Error: Checkpoint not found: $BEST_MODEL"
    exit 1
fi

echo "✅ Checkpoint found: $BEST_MODEL"

# 2. Export to TorchScript (MPS-optimized)
echo "🔄 Converting to TorchScript (MPS)..."
python3 << EOFPY
import torch
import torch.nn as nn
import sys
sys.path.append('/home/love-lee/mycnn/src')
from models.LiteCNNPro import LiteCNNPro

# Load checkpoint
checkpoint = torch.load('$BEST_MODEL', map_location='cpu', weights_only=False)
print(f"Loaded: Epoch {checkpoint['epoch']}, Val Acc {checkpoint['val_acc']:.2f}%")

# Create model
model = LiteCNNPro(num_classes=130, dropout=0.5)
model.load_state_dict(checkpoint['model_state_dict'])
model.eval()

# Export to TorchScript
dummy_input = torch.randn(1, 3, 224, 224)
traced = torch.jit.trace(model, dummy_input)
traced = torch.jit.optimize_for_inference(traced)

torch.jit.save(traced, '$OUTPUT_PT')
print(f"✅ Exported: $OUTPUT_PT")
EOFPY

if [ ! -f "$OUTPUT_PT" ]; then
    echo "❌ Error: TorchScript export failed"
    exit 1
fi

echo "✅ TorchScript model created"

# 3. Transfer to M1 Mac
echo "📤 Transferring to M1 Mac..."
scp "$OUTPUT_PT" "${M1_USER}@${M1_MAC}:${M1_WEIGHTS}/cycle${CYCLE}_mps_traced.pt"

# Also update the main model link
ssh "${M1_USER}@${M1_MAC}" << EOFSSH
cd $M1_WEIGHTS
ln -sf cycle${CYCLE}_mps_traced.pt cycle13_mps_traced.pt
echo "✅ Model link updated"
EOFSSH

# 4. Deploy on M1 Mac
echo "🚀 Deploying MPS server on M1 Mac..."
ssh "${M1_USER}@${M1_MAC}" "cd $M1_PROJECT && bash scripts/mps/deploy_mps_server.sh"

echo ""
echo "========================================="
echo "✅ Deployment Complete!"
echo "   Model: Cycle $CYCLE"
echo "   Server: http://${M1_MAC}:8893"
echo "========================================="
