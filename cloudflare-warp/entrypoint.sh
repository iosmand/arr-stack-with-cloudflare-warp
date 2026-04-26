#!/bin/bash
set -euo pipefail

WARP_MODE=${WARP_MODE:-"warp"}
WARP_LISTEN_PORT=${WARP_LISTEN_PORT:-40000}
MAX_CONSECUTIVE_FAILURES=5

WARP_PID=""
CONSECUTIVE_FAILURES=0

echo "Starting Cloudflare WARP..."

cleanup() {
    echo "Shutting down warp-svc..."
    if [ -n "$WARP_PID" ] && kill -0 "$WARP_PID" 2>/dev/null; then
        kill "$WARP_PID" 2>/dev/null || true
        for i in $(seq 1 10); do
            kill -0 "$WARP_PID" 2>/dev/null || break
            sleep 1
        done
        kill -0 "$WARP_PID" 2>/dev/null && kill -9 "$WARP_PID" 2>/dev/null || true
        wait "$WARP_PID" 2>/dev/null || true
    fi
    exit 0
}
trap cleanup SIGTERM SIGINT

init_dbus() {
    if [ ! -d /run/dbus ]; then
        mkdir -p /run/dbus
    fi
    rm -f /run/dbus/pid
    if ! dbus-daemon --system --fork; then
        echo "FATAL: Failed to start dbus-daemon"
        exit 1
    fi
}

wait_for_daemon() {
    local retries=0
    local max_retries=30
    while ! warp-cli --accept-tos status &>/dev/null; do
        retries=$((retries + 1))
        if [ "$retries" -ge "$max_retries" ]; then
            echo "ERROR: WARP daemon failed to become ready after $max_retries attempts"
            return 1
        fi
        if ! kill -0 "$WARP_PID" 2>/dev/null; then
            echo "ERROR: warp-svc process died while waiting"
            return 1
        fi
        echo "Waiting for WARP daemon... (attempt $retries/$max_retries)"
        sleep 2
    done
    return 0
}

register_if_needed() {
    if ! warp-cli --accept-tos registration show &>/dev/null; then
        echo "Registering as non-registered (free) user..."
        warp-cli --accept-tos registration new
    else
        echo "Already registered"
    fi
}

configure_and_connect() {
    echo "Setting WARP mode to: $WARP_MODE"
    if ! warp-cli --accept-tos mode "$WARP_MODE"; then
        echo "ERROR: Failed to set WARP mode"
        return 1
    fi

    if [ "$WARP_MODE" = "proxy" ]; then
        echo "Setting proxy listen port to: $WARP_LISTEN_PORT"
        if ! warp-cli --accept-tos proxy port "$WARP_LISTEN_PORT"; then
            echo "ERROR: Failed to set proxy port"
            return 1
        fi
    fi

    echo "Connecting to Cloudflare WARP..."
    warp-cli --accept-tos connect || true

    echo "=== WARP Status ==="
    warp-cli --accept-tos status
    echo "==================="

    return 0
}

start_warp_svc() {
    warp-svc &
    WARP_PID=$!
    echo "warp-svc started with PID $WARP_PID"
}

full_startup() {
    start_warp_svc

    if ! wait_for_daemon; then
        return 1
    fi

    register_if_needed

    if ! configure_and_connect; then
        return 1
    fi

    CONSECUTIVE_FAILURES=0
    return 0
}

init_dbus

if ! full_startup; then
    echo "FATAL: Initial WARP startup failed"
    exit 1
fi

echo "WARP is running. Monitoring connection..."

while true; do
    if ! kill -0 "$WARP_PID" 2>/dev/null; then
        echo "WARNING: warp-svc process (PID $WARP_PID) has died. Restarting daemon..."
        if ! full_startup; then
            echo "FATAL: Failed to restart warp-svc. Exiting."
            exit 1
        fi
        continue
    fi

    STATUS=$(warp-cli --accept-tos status 2>&1 || true)
    if echo "$STATUS" | grep -q "Connected"; then
        CONSECUTIVE_FAILURES=0
    else
        CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
        echo "Connection check failed ($CONSECUTIVE_FAILURES/$MAX_CONSECUTIVE_FAILURES). Status: $STATUS"

        if echo "$STATUS" | grep -qE "Disconnected|Unable|Error|timeout"; then
            echo "Attempting to reconnect..."
            warp-cli --accept-tos connect 2>&1 || true
        fi

        if [ "$CONSECUTIVE_FAILURES" -ge "$MAX_CONSECUTIVE_FAILURES" ]; then
            echo "WARNING: WARP disconnected for too long. Restarting daemon..."
            if ! full_startup; then
                echo "FATAL: Failed to restart warp-svc. Exiting."
                exit 1
            fi
        fi
    fi

    sleep $((25 + RANDOM % 10))
done
