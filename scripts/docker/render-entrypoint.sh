#!/bin/sh
# Render entrypoint: pre-seed config for non-loopback deployment, then start gateway.
set -e

OPENCLAW_BIN="node /app/openclaw.mjs"
PORT="${PORT:-8080}"

# Seed gateway.mode and bind so the gateway starts without --allow-unconfigured.
$OPENCLAW_BIN config set gateway.mode local
$OPENCLAW_BIN config set gateway.bind lan

# Allow Host-header origin fallback for Render's reverse proxy.
$OPENCLAW_BIN config set gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback true

# Disable device pairing requirement — token auth is sufficient on Render.
$OPENCLAW_BIN config set gateway.controlUi.dangerouslyDisableDeviceAuth true

exec $OPENCLAW_BIN gateway run --bind lan --port "$PORT"
