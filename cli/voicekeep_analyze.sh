#!/usr/bin/env bash
# voicekeep_analyze.sh — read one .voicekeep.json from $1, write Markdown to $2.
# This is the inner core; the watcher in watch_inbox.sh wraps it for inbox/processed flow.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <input.voicekeep.json> <output.analysis.md>" >&2
  exit 64
fi

IN="$1"
OUT="$2"
PROMPT_FILE="$(dirname "$0")/prompts/analyze.md"

if [ ! -f "$IN" ]; then
  echo "Input not found: $IN" >&2
  exit 66
fi
if [ ! -f "$PROMPT_FILE" ]; then
  echo "Prompt not found: $PROMPT_FILE" >&2
  exit 70
fi

if ! jq -e '.version == 1 and .transcript.fullText' "$IN" >/dev/null 2>&1; then
  echo "Invalid JSON or unsupported version: $IN" >&2
  exit 65
fi

# Build the user message: the prompt template + the transcript JSON.
{
  cat "$PROMPT_FILE"
  echo
  echo "## Транскрипт"
  echo
  echo '```json'
  cat "$IN"
  echo '```'
} | claude -p --model sonnet > "$OUT.tmp"

mv "$OUT.tmp" "$OUT"
