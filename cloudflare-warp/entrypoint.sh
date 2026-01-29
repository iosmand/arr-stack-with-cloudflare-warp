#!/bin/bash
set -e

# Configuration via environment variables
WARP_MODE=${WARP_MODE:-"warp"}  # Options: warp, doh, warp+doh, dot, warp+dot, proxy
WARP_LISTEN_PORT=${WARP_LISTEN_PORT:-40000}

echo "Starting Cloudflare WARP..."

# Start dbus (required for warp-svc)
if [ ! -d /run/dbus ]; then
    mkdir -p /run/dbus
fi
rm -f /run/dbus/pid
dbus-daemon --system --fork

# Start WARP daemon in background
warp-svc &

# Wait for daemon to be ready
echo "Waiting for WARP daemon to start..."
sleep 5

# Wait for warp-cli to be able to connect to the daemon
MAX_RETRIES=30
RETRY_COUNT=0
while ! warp-cli --accept-tos status &>/dev/null; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "ERROR: WARP daemon failed to start after $MAX_RETRIES attempts"
        exit 1
    fi
    echo "Waiting for WARP daemon... (attempt $RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done

echo "WARP daemon is ready"

# Check if already registered
if ! warp-cli --accept-tos registration show &>/dev/null; then
    echo "Registering as non-registered (free) user..."
    warp-cli --accept-tos registration new
else
    echo "Already registered"
fi

# Set WARP mode
echo "Setting WARP mode to: $WARP_MODE"
warp-cli --accept-tos mode "$WARP_MODE"

# If proxy mode, set the listen port
if [ "$WARP_MODE" = "proxy" ]; then
    echo "Setting proxy listen port to: $WARP_LISTEN_PORT"
    warp-cli --accept-tos proxy port "$WARP_LISTEN_PORT"
fi

# Connect to WARP
echo "Connecting to Cloudflare WARP..."
warp-cli --accept-tos connect

# Wait for connection
sleep 3

# Show status
echo "=== WARP Status ==="
warp-cli --accept-tos status
echo "==================="

# Keep container running and monitor connection
echo "WARP is running. Monitoring connection..."
while true; do
    if ! warp-cli --accept-tos status | grep -q "Connected"; then
        echo "Connection lost, attempting to reconnect..."
        warp-cli --accept-tos connect
    fi
    sleep 30
done
