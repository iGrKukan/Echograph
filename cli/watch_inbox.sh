#!/usr/bin/env bash
# watch_inbox.sh — process every *.voicekeep.json in the iCloud inbox.
# Triggered by launchd WatchPaths; safe to run manually too.
set -euo pipefail

ROOT="${VOICEKEEP_ROOT:-$HOME/Library/Mobile Documents/iCloud~by~timberbid~echograph/Documents}"
INBOX="$ROOT/inbox"
PROCESSED="$ROOT/processed"
FAILED="$ROOT/failed"
LOCK_DIR="$HOME/Library/Caches/voicekeep-analyzer.lock"
LOG="$HOME/Library/Logs/voicekeep-analyzer.log"
ANALYZER="$(dirname "$0")/voicekeep_analyze.sh"

mkdir -p "$INBOX" "$PROCESSED" "$FAILED" "$(dirname "$LOG")"

log() { echo "[$(date -Iseconds)] $*" >> "$LOG"; }

# Single-instance lock (mkdir is atomic on POSIX; macOS lacks flock(1)).
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log "another instance running, exit"
  exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

shopt -s nullglob
processed_count=0
for f in "$INBOX"/*.voicekeep.json; do
  name="$(basename "$f" .voicekeep.json)"
  out_md="$PROCESSED/$name.analysis.md"

  # Idempotency: pre-existing analysis means we already did this one.
  if [ -f "$out_md" ]; then
    mv "$f" "$PROCESSED/" 2>/dev/null || rm -f "$f"
    log "skip (already analysed): $name"
    continue
  fi

  log "analyzing: $name"
  if "$ANALYZER" "$f" "$out_md" 2>"$FAILED/$name.error.txt"; then
    mv "$f" "$PROCESSED/"
    rm -f "$FAILED/$name.error.txt"
    processed_count=$((processed_count + 1))
    log "done: $name"
  else
    rc=$?
    mv "$f" "$FAILED/"
    log "FAILED ($rc): $name — see $FAILED/$name.error.txt"
  fi
done

if [ "$processed_count" -gt 0 ]; then
  log "batch complete: $processed_count file(s)"
fi
