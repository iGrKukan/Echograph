#!/usr/bin/env bash
# setup.sh — install the Voicekeep analyzer HTTP server on this Mac.
# Idempotent: re-running re-renders the plist and reloads the agent.
set -euo pipefail

CLI_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER="$CLI_DIR/server.py"
ANALYZER="$CLI_DIR/voicekeep_analyze.sh"
TEMPLATE="$CLI_DIR/launchd/com.voicekeep.analyzer.plist.template"
PLIST_DEST="$HOME/Library/LaunchAgents/com.voicekeep.analyzer.plist"
LAUNCHD_LOG="$HOME/Library/Logs/voicekeep-analyzer.launchd.log"
TOKEN_FILE="$HOME/.voicekeep-token"
PORT="${VOICEKEEP_PORT:-19847}"

# 1. Prereq checks
echo "→ Checking prerequisites..."
for cmd in claude jq python3 plutil launchctl openssl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "  ✗ '$cmd' not found in PATH" >&2
    [ "$cmd" = "claude" ] && echo "    install: see https://docs.anthropic.com/cli" >&2
    [ "$cmd" = "jq" ]     && echo "    install: brew install jq" >&2
    exit 1
  fi
done
echo "  ✓ claude, jq, python3, plutil, launchctl, openssl present"

# 2. Generate (or reuse) bearer token
if [ ! -f "$TOKEN_FILE" ]; then
  echo "→ Generating bearer token..."
  openssl rand -hex 32 > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
  echo "  ✓ $TOKEN_FILE"
else
  echo "→ Reusing existing token at $TOKEN_FILE"
fi
TOKEN="$(cat "$TOKEN_FILE")"

# 3. Make scripts executable
chmod +x "$SERVER" "$ANALYZER"

# 4. Render the plist
echo "→ Rendering launch agent plist..."
mkdir -p "$(dirname "$PLIST_DEST")" "$(dirname "$LAUNCHD_LOG")"
sed \
    -e "s|__SERVER_PATH__|$SERVER|g" \
    -e "s|__LAUNCHD_LOG__|$LAUNCHD_LOG|g" \
    -e "s|__TOKEN__|$TOKEN|g" \
    -e "s|__PORT__|$PORT|g" \
    "$TEMPLATE" > "$PLIST_DEST"
plutil -lint "$PLIST_DEST" >/dev/null
echo "  ✓ $PLIST_DEST"

# 5. Bootstrap (or re-bootstrap) the launch agent
echo "→ Loading launch agent..."
DOMAIN="gui/$(id -u)"
LABEL="com.voicekeep.analyzer"
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$PLIST_DEST"
launchctl enable "$DOMAIN/$LABEL"
echo "  ✓ agent $LABEL loaded"

# 6. Wait briefly then health-check
sleep 1
if curl -sSf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  echo "  ✓ health check passed"
else
  echo "  ⚠ health check failed — see $LAUNCHD_LOG"
fi

# 7. Discover the URL the iPhone should use
ts_ip=""
if command -v tailscale >/dev/null 2>&1; then
  ts_ip="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
fi
hostname_short="$(hostname -s 2>/dev/null || hostname)"

cat <<EOF

✓ Voicekeep analyzer installed.

  Local health:    http://127.0.0.1:$PORT/health
  Logs:            $LAUNCHD_LOG

EOF
if [ -n "$ts_ip" ]; then
  cat <<EOF
  Tailscale URL:   http://$ts_ip:$PORT
EOF
else
  cat <<EOF
  Tailscale not detected. Install + log in: brew install tailscale
                                            sudo tailscale up
EOF
fi
cat <<EOF
  LAN URL:         http://${hostname_short}.local:$PORT
  Bearer token:    $TOKEN

In the iPhone app: Settings → AI Analyzer → paste the URL and token.

To uninstall:
  launchctl bootout $DOMAIN/$LABEL
  rm $PLIST_DEST
EOF
