#!/bin/bash
# Deploy latest cycle to Port 8892 (experimental)

set -e

CYCLE=$1
if [ -z "$CYCLE" ]; then
    echo "Usage: $0 <cycle_number>"
    exit 1
fi

PROJECT_DIR="/Users/young/projects/litecnn-pure-cpp"

echo "🚀 Deploying Cycle $CYCLE to Port 8892..."

# 1. Convert to TorchScript (if not exists)
if [ ! -f "$PROJECT_DIR/weights/cycle${CYCLE}_mps_traced.pt" ]; then
    echo "📤 Converting Cycle $CYCLE to TorchScript..."
    # Download and convert (similar to previous script)
fi

# 2. Restart Port 8892
echo "🔄 Restarting Port 8892..."
pkill -f "server_mps_config --port 8892" || true
sleep 2

nohup "$PROJECT_DIR/build/litecnn_server_mps_config" \
    --port 8892 \
    --model "$PROJECT_DIR/weights/cycle${CYCLE}_mps_traced.pt" \
    --name "Cycle $CYCLE" \
    > /tmp/mps_8892.log 2>&1 &

sleep 3

# 3. Health check
HEALTH=$(curl -s http://localhost:8892/health | jq -r '.status')
if [ "$HEALTH" == "ok" ]; then
    echo "✅ Port 8892 (Cycle $CYCLE) deployed successfully"
else
    echo "❌ Deployment failed"
    exit 1
fi
