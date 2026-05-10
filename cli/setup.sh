#!/usr/bin/env bash
# setup.sh — install the Voicekeep analyzer launch agent on this Mac.
# Idempotent: re-running upgrades the plist and reloads the agent.
set -euo pipefail

ROOT="$HOME/Library/Mobile Documents/iCloud~by~timberbid~echograph/Documents"
INBOX="$ROOT/inbox"
PROCESSED="$ROOT/processed"
FAILED="$ROOT/failed"
LOG="$HOME/Library/Logs/voicekeep-analyzer.log"
LAUNCHD_LOG="$HOME/Library/Logs/voicekeep-analyzer.launchd.log"

CLI_DIR="$(cd "$(dirname "$0")" && pwd)"
WATCHER="$CLI_DIR/watch_inbox.sh"
TEMPLATE="$CLI_DIR/launchd/com.voicekeep.analyzer.plist.template"
PLIST_DEST="$HOME/Library/LaunchAgents/com.voicekeep.analyzer.plist"

# 1. Prereq checks
echo "→ Checking prerequisites..."
for cmd in claude jq plutil launchctl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "  ✗ '$cmd' not found in PATH" >&2
    [ "$cmd" = "claude" ] && echo "    install: https://docs.anthropic.com/cli (or your local equivalent)" >&2
    [ "$cmd" = "jq" ] && echo "    install: brew install jq" >&2
    exit 1
  fi
done
echo "  ✓ claude, jq, plutil, launchctl present"

# 2. Create iCloud Drive folders
echo "→ Creating iCloud Drive folders..."
mkdir -p "$INBOX" "$PROCESSED" "$FAILED" "$(dirname "$LOG")"
echo "  ✓ $ROOT/{inbox,processed,failed}"

# 3. Render the plist from the template
echo "→ Rendering launch agent plist..."
mkdir -p "$(dirname "$PLIST_DEST")"
sed \
    -e "s|__SCRIPT_PATH__|$WATCHER|g" \
    -e "s|__INBOX__|$INBOX|g" \
    -e "s|__LAUNCHD_LOG__|$LAUNCHD_LOG|g" \
    "$TEMPLATE" > "$PLIST_DEST"
plutil -lint "$PLIST_DEST" >/dev/null
echo "  ✓ $PLIST_DEST"

# 4. Bootstrap (or re-bootstrap) the launch agent
echo "→ Loading launch agent..."
DOMAIN="gui/$(id -u)"
LABEL="com.voicekeep.analyzer"
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$PLIST_DEST"
launchctl enable "$DOMAIN/$LABEL"
echo "  ✓ agent $LABEL loaded"

# 5. Sanity check — the watcher itself must be executable
chmod +x "$WATCHER" "$CLI_DIR/voicekeep_analyze.sh"

cat <<EOF

✓ Voicekeep analyzer installed.

  Inbox folder:    $INBOX
  Logs:            $LOG
  launchd logs:    $LAUNCHD_LOG

Drop a *.voicekeep.json into inbox/ (or share one from iPhone) and the
agent will analyse it within ~5 seconds. Result Markdown lands in
processed/ next to the source.

To uninstall:
  launchctl bootout $DOMAIN/$LABEL
  rm $PLIST_DEST
EOF
