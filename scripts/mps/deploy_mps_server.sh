#!/bin/bash
# MPS Server Auto-Deploy Script (M1 Mac)
# Triggered when new TorchScript model arrives from GPU server

set -e

PROJECT_DIR="/Users/young/projects/litecnn-pure-cpp"
WEIGHTS_DIR="$PROJECT_DIR/weights"
BUILD_DIR="$PROJECT_DIR/build"
LOG_FILE="/tmp/mps_deploy.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "========================================="
log "MPS Server Auto-Deploy Started"
log "========================================="

# 1. Check if new model exists
if [ ! -f "$WEIGHTS_DIR/cycle13_mps_traced.pt" ]; then
    log "❌ Error: Model file not found"
    exit 1
fi

MODEL_SIZE=$(ls -lh "$WEIGHTS_DIR/cycle13_mps_traced.pt" | awk '{print $5}')
log "📦 Model found: cycle13_mps_traced.pt ($MODEL_SIZE)"

# 2. Stop existing server
log "🛑 Stopping existing MPS server..."
pkill -9 litecnn_server_mps 2>/dev/null || true
pkill -9 litecnn_server_cycle13 2>/dev/null || true
sleep 2

# 3. Rebuild server
log "🔨 Building MPS server..."
cd "$PROJECT_DIR"
make -f Makefile.mps clean
make -f Makefile.mps

if [ ! -f "$BUILD_DIR/litecnn_server_mps" ]; then
    log "❌ Error: Build failed"
    exit 1
fi

log "✅ Build complete"

# 4. Start server
log "🚀 Starting MPS server on port 8893..."
nohup "$BUILD_DIR/litecnn_server_mps" > /tmp/mps_server.log 2>&1 &
SERVER_PID=$!

sleep 3

# 5. Health check
log "🏥 Health check..."
HEALTH=$(curl -s http://localhost:8893/health || echo "failed")

if [[ "$HEALTH" == *"ok"* ]]; then
    log "✅ MPS Server deployed successfully (PID: $SERVER_PID)"
    log "   Port: 8893"
    log "   Device: MPS"
    
    # Notify Discord
    if [ -x "$PROJECT_DIR/scripts/notify_discord.sh" ]; then
        "$PROJECT_DIR/scripts/notify_discord.sh" \
            "🚀 MPS Server Deployed" \
            "Port 8893 | Device: MPS | Model: Cycle 13" \
            "success" || true
    fi
else
    log "❌ Error: Health check failed"
    log "   Response: $HEALTH"
    exit 1
fi

log "========================================="
log "Deployment Complete"
log "========================================="
