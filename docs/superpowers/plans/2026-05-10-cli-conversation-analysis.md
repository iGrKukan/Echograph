# CLI Conversation Analysis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the personal-use CLI conversation-analysis pipeline described in `docs/superpowers/specs/2026-05-10-cli-conversation-analysis-design.md` — iPhone Share Sheet → iCloud Drive → launchd watcher on Mac → `claude -p` → four-section Markdown analysis next to the source.

**Architecture:** Two halves connected only through the iCloud Drive folder `~/Library/Mobile Documents/com~apple~CloudDocs/Voicekeep/`. iOS adds a `Transferable` wrapper + `ShareLink` to `RecordingDetailView`. Mac adds a bash-based `cli/` directory: prompt template, watcher script, launchd plist, idempotent installer.

**Tech Stack:** Swift 6 / SwiftUI (`Transferable`, `ShareLink`), bash, `claude` CLI, `jq`, launchd `WatchPaths`.

---

## File structure

**New files:**
- `Echograph/Echograph/Core/Models/AnalysisExport.swift` — Transferable wrapper that emits the v1 JSON schema.
- `cli/voicekeep_analyze.sh` — watcher worker.
- `cli/prompts/analyze.md` — Russian prompt with the four-section structure.
- `cli/launchd/com.voicekeep.analyzer.plist.template` — launchd plist with placeholders.
- `cli/setup.sh` — idempotent installer (creates folders, renders plist, bootstraps launch agent).
- `cli/README.md` — user-facing setup + usage docs.
- `cli/test/sample.voicekeep.json` — realistic Russian fixture for smoke tests.
- `cli/test/expected_schema.json` — minimal example documenting every field; used by both the bash smoke test and as the spec for the iOS encoder.
- `cli/.gitignore` — excludes `*.local.*` configs and any local working files.

**Modified files:**
- `Echograph/Echograph/UI/RecordingDetailView.swift` — adds the "Анализ AI" `ShareLink` near the existing Export menu.
- `Echograph/Echograph/Resources/Localizable.xcstrings` — adds string `recording.detail.analyze.menu.label` for at least `en` and `ru`.

**Phasing:**
- **Phase 1** (Tasks 1–9) is CLI-only and fully testable on the dev Mac without Xcode.
- **Phase 2** (Tasks 10–12) is iOS code; it gets pushed to git and built on the other Mac (the one with Xcode). No automated tests added — the iOS unit-test target doesn't currently exist and adding one is out of scope for the prototype.
- **Phase 3** (Task 13) is a manual end-to-end smoke test with a real iPhone recording.

Why this order: Phase 1 gives us a working CLI we can validate against synthetic fixtures and iterate the prompt on. Phase 2 is then a thin iOS wrapper that hands a known-good JSON shape into the validated pipeline.

---

## Phase 1 — CLI prototype

### Task 1: Skeleton + sample fixture

**Files:**
- Create: `cli/.gitignore`
- Create: `cli/test/sample.voicekeep.json`

- [ ] **Step 1: Create `cli/` skeleton directories**

```bash
cd ~/Echograph
mkdir -p cli/prompts cli/launchd cli/test
```

- [ ] **Step 2: Write `cli/.gitignore`**

```gitignore
# Local working files
*.local.*
*.swp
.DS_Store

# Logs (if user redirects launchd output here)
*.log
```

- [ ] **Step 3: Write `cli/test/sample.voicekeep.json`**

```json
{
  "version": 1,
  "id": "F2A3B4C5-D6E7-4890-A1B2-C3D4E5F6A7B8",
  "title": "Звонок с поставщиком о доске",
  "createdAt": "2026-05-10T14:23:11Z",
  "duration": 142.7,
  "language": "ru",
  "speakerCount": 2,
  "tags": ["поставщики", "доска"],
  "transcript": {
    "fullText": "Здравствуйте, Иван. По доске сорок-сто-шесть тысяч могу дать сто восемьдесят за куб с доставкой во вторник. Давайте сто семьдесят пять и я беру десять кубов сразу. Хорошо, на ста семидесяти семи договоримся, оплата по факту прихода. Договорились, жду счёт до конца дня.",
    "segments": [
      {
        "startTime": 0.0,
        "endTime": 12.4,
        "text": "Здравствуйте, Иван. По доске сорок-сто-шесть тысяч могу дать сто восемьдесят за куб с доставкой во вторник.",
        "speaker": "Поставщик"
      },
      {
        "startTime": 12.4,
        "endTime": 28.9,
        "text": "Давайте сто семьдесят пять и я беру десять кубов сразу.",
        "speaker": "Иван",
        "highlighted": true
      },
      {
        "startTime": 28.9,
        "endTime": 48.3,
        "text": "Хорошо, на ста семидесяти семи договоримся, оплата по факту прихода.",
        "speaker": "Поставщик"
      },
      {
        "startTime": 48.3,
        "endTime": 60.0,
        "text": "Договорились, жду счёт до конца дня.",
        "speaker": "Иван",
        "highlighted": true
      }
    ]
  }
}
```

- [ ] **Step 4: Validate the fixture**

Run: `jq -e '.version == 1 and .transcript.fullText' cli/test/sample.voicekeep.json`
Expected: prints `true`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add cli/.gitignore cli/test/sample.voicekeep.json
git commit -m "feat(cli): scaffold + sample voicekeep.json fixture"
```

---

### Task 2: Schema documentation fixture

**Files:**
- Create: `cli/test/expected_schema.json`

This file is **not** consumed by any script; it's a reference for the iOS encoder (Task 10) and a quick lookup for humans editing prompts. Keeping it next to the bash smoke test prevents drift.

- [ ] **Step 1: Write `cli/test/expected_schema.json`**

```json
{
  "version": 1,
  "id": "<UUID-string>",
  "title": "<Recording.title>",
  "createdAt": "<ISO 8601 with Z>",
  "duration": 0.0,
  "language": "<2-letter code or empty string>",
  "speakerCount": 1,
  "tags": ["<tag>", "..."],
  "transcript": {
    "fullText": "<concatenated segment.text joined by space>",
    "segments": [
      {
        "startTime": 0.0,
        "endTime": 0.0,
        "text": "<segment text>",
        "speaker": "<label string, omit field if no speaker>",
        "highlighted": true
      }
    ]
  }
}
```

Comments above the schema (header) explain the omit-when-default rules:
- `speaker` field absent if `Segment.speaker == nil`.
- `highlighted` field absent if `Segment.isHighlighted == false`.
- `tags` is `[]` when the recording has no tags.
- `id` is `Recording.id.uuidString` (UUIDs are uppercased on iOS).

- [ ] **Step 2: Add a header comment via `_comment` (jq-friendly)**

Edit the file to start with:

```json
{
  "_comment": "v1 export schema for AnalysisExport. omit-when-default: speaker (nil), highlighted (false). Mirror in Echograph/Core/Models/AnalysisExport.swift.",
  "version": 1,
  ...
}
```

(Keep the existing fields after the comment.)

- [ ] **Step 3: Validate JSON**

Run: `jq -e .version cli/test/expected_schema.json`
Expected: prints `1`.

- [ ] **Step 4: Commit**

```bash
git add cli/test/expected_schema.json
git commit -m "docs(cli): document v1 export schema as reference fixture"
```

---

### Task 3: Analysis prompt

**Files:**
- Create: `cli/prompts/analyze.md`

- [ ] **Step 1: Write the prompt**

```markdown
Ты — аналитический помощник. Получаешь на вход JSON одного разговора и
возвращаешь Markdown-отчёт **строго на русском языке**.

## Структура входа

```
{
  "version": 1,
  "title": "<заголовок записи>",
  "createdAt": "<ISO 8601>",
  "duration": <секунды>,
  "language": "<ru|en|...>",
  "speakerCount": <int>,
  "tags": [<пользовательские ярлыки>],
  "transcript": {
    "fullText": "<непрерывный текст>",
    "segments": [
      {
        "startTime": <сек>,
        "endTime": <сек>,
        "text": "<реплика>",
        "speaker": "<имя или роль, может отсутствовать>",
        "highlighted": <true, может отсутствовать>
      }
    ]
  }
}
```

## Что нужно вернуть

Markdown-документ из ровно четырёх секций второго уровня (`##`) в этом
порядке:

```
## Резюме

<TL;DR одним абзацем (2–4 предложения).>

<Маркированный список 5–10 главных тезисов разговора.>

## Договорённости и обещания

| Что | Кто | Срок | Цитата (mm:ss) |
|---|---|---|---|
| ... | ... | ... | "...." (12:34) |

## Решения и открытые вопросы

**Решено:**
- ...

**Открыто:**
- ...

## Темы

- Главная тема 1
  - подтема
    - конкретика
- Главная тема 2
  - ...
```

## Правила

- **Никогда не выдумывай факты.** Если в транскрипте нет — не пиши.
- Цитируй дословно, без перефразирования.
- Время в цитатах — `mm:ss`, считается из `startTime` сегмента
  (округление вниз до секунды).
- В колонке «Кто» используй `speaker` сегмента. Если speaker отсутствует —
  оставь пустым (`—`).
- Сегменты с `"highlighted": true` важны автору записи. Учитывай их в
  «Резюме» и «Решениях».
- `speakerCount = 1` означает монолог. В таком случае «Договорённости» и
  «Решения» могут быть пустыми (`_нет_`) — это нормально, не выдумывай.
- `tags` — мягкий контекстный сигнал темы разговора, не используй как факты.
- Если разговор пустой, шум, или это вообще не разговор — верни ровно одну
  строку:

  ```
  Анализ невозможен: <одна короткая фраза с причиной>
  ```

## Формат вывода

Только Markdown отчёта. Без вступления вроде «Вот ваш отчёт:», без
кодоблоков-обёрток вокруг всего ответа, без подписи в конце.
```

- [ ] **Step 2: Verify file is valid Markdown**

Run: `head -20 cli/prompts/analyze.md`
Expected: shows the opening lines starting with "Ты — аналитический помощник."

- [ ] **Step 3: Commit**

```bash
git add cli/prompts/analyze.md
git commit -m "feat(cli): analysis prompt with four-section RU output"
```

---

### Task 4: Minimal `voicekeep_analyze.sh` (one-shot, no folders yet)

This is an iterative milestone. Goal: prove the prompt works against `claude -p` before we add the launchd/folder plumbing.

**Files:**
- Create: `cli/voicekeep_analyze.sh`

- [ ] **Step 1: Write the minimal script**

```bash
#!/usr/bin/env bash
# voicekeep_analyze.sh — read one .voicekeep.json from $1, write Markdown to $2.
# This is the inner core; the watcher in Task 5 wraps it for inbox/processed flow.
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
# `claude -p` takes the prompt as the user message; we pipe nothing to stdin.
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
```

- [ ] **Step 2: Make executable**

```bash
chmod +x cli/voicekeep_analyze.sh
```

- [ ] **Step 3: Smoke test against the fixture**

```bash
cd ~/Echograph
./cli/voicekeep_analyze.sh cli/test/sample.voicekeep.json /tmp/sample.analysis.md
```

Expected: command finishes (may take 10–30 s while Claude runs); `/tmp/sample.analysis.md` exists.

- [ ] **Step 4: Verify the output structure**

Run:
```bash
grep -c '^## Резюме$\|^## Договорённости и обещания$\|^## Решения и открытые вопросы$\|^## Темы$' /tmp/sample.analysis.md
```
Expected: prints `4` (all four required headers present).

Visually inspect:
```bash
cat /tmp/sample.analysis.md
```
Verify:
- The "Резюме" mentions the negotiation about price 175 → 177 BYN/m³.
- "Договорённости" table includes the deal at 177, 10 m³, payment on delivery, invoice by EOD.
- Russian throughout.
- No fabricated names beyond "Иван" and "Поставщик" (which are in the fixture).

If quality is poor, iterate `cli/prompts/analyze.md` and rerun. Commit only after the output is satisfactory.

- [ ] **Step 5: Commit**

```bash
git add cli/voicekeep_analyze.sh
git commit -m "feat(cli): inner analyzer — claude -p over JSON, four-section Markdown out"
```

---

### Task 5: Watcher script with inbox / processed / failed routing

**Files:**
- Create: `cli/watch_inbox.sh`

We split the watcher loop from the inner analyzer (Task 4) so each script has one job. `watch_inbox.sh` is what launchd invokes.

- [ ] **Step 1: Write `cli/watch_inbox.sh`**

```bash
#!/usr/bin/env bash
# watch_inbox.sh — process every *.voicekeep.json in the iCloud inbox.
# Triggered by launchd WatchPaths; safe to run manually too.
set -euo pipefail

ROOT="${VOICEKEEP_ROOT:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/Voicekeep}"
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

[ "$processed_count" -gt 0 ] && log "batch complete: $processed_count file(s)"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x cli/watch_inbox.sh
```

- [ ] **Step 3: Set up a temp inbox to test routing**

```bash
export VOICEKEEP_ROOT="/tmp/voicekeep-test"
rm -rf "$VOICEKEEP_ROOT"
mkdir -p "$VOICEKEEP_ROOT/inbox"
cp cli/test/sample.voicekeep.json "$VOICEKEEP_ROOT/inbox/test1.voicekeep.json"
cp cli/test/sample.voicekeep.json "$VOICEKEEP_ROOT/inbox/test2.voicekeep.json"
ls "$VOICEKEEP_ROOT/inbox"
```

- [ ] **Step 4: Run the watcher**

```bash
./cli/watch_inbox.sh
```

Expected: takes ~30–60 s (two Claude runs); produces:
- `$VOICEKEEP_ROOT/processed/test1.voicekeep.json`
- `$VOICEKEEP_ROOT/processed/test1.analysis.md`
- `$VOICEKEEP_ROOT/processed/test2.voicekeep.json`
- `$VOICEKEEP_ROOT/processed/test2.analysis.md`
- empty `$VOICEKEEP_ROOT/inbox/`
- log lines in `~/Library/Logs/voicekeep-analyzer.log`

- [ ] **Step 5: Verify routing and idempotency**

```bash
ls "$VOICEKEEP_ROOT/inbox" "$VOICEKEEP_ROOT/processed" "$VOICEKEEP_ROOT/failed"
```
Expected: inbox empty, processed has 4 files (2 json + 2 md), failed empty.

Run watcher again with the same processed/ — should be a no-op:
```bash
cp cli/test/sample.voicekeep.json "$VOICEKEEP_ROOT/inbox/test1.voicekeep.json"
./cli/watch_inbox.sh
ls "$VOICEKEEP_ROOT/inbox" "$VOICEKEEP_ROOT/processed"
```
Expected: inbox empty again; processed unchanged (idempotency triggered, source moved out of inbox without re-running Claude). Log shows `skip (already analysed)`.

- [ ] **Step 6: Test failure path**

```bash
echo '{"version": 99}' > "$VOICEKEEP_ROOT/inbox/bad.voicekeep.json"
./cli/watch_inbox.sh
ls "$VOICEKEEP_ROOT/failed"
cat "$VOICEKEEP_ROOT/failed/bad.error.txt"
```
Expected: `bad.voicekeep.json` and `bad.error.txt` in `failed/`, error mentions invalid JSON/version.

- [ ] **Step 7: Cleanup test root**

```bash
rm -rf /tmp/voicekeep-test
unset VOICEKEEP_ROOT
```

- [ ] **Step 8: Commit**

```bash
git add cli/watch_inbox.sh
git commit -m "feat(cli): inbox/processed/failed watcher with lock + idempotency"
```

---

### Task 6: launchd plist template

**Files:**
- Create: `cli/launchd/com.voicekeep.analyzer.plist.template`

- [ ] **Step 1: Write the plist template**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.voicekeep.analyzer</string>

    <key>ProgramArguments</key>
    <array>
        <string>__SCRIPT_PATH__</string>
    </array>

    <key>WatchPaths</key>
    <array>
        <string>__INBOX__</string>
    </array>

    <key>RunAtLoad</key>
    <false/>

    <key>StandardOutPath</key>
    <string>__LAUNCHD_LOG__</string>

    <key>StandardErrorPath</key>
    <string>__LAUNCHD_LOG__</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
```

The `EnvironmentVariables/PATH` is needed because launchd ignores the user's shell profile, so without it `claude` and `jq` (often in `/opt/homebrew/bin` on Apple Silicon) wouldn't be found.

- [ ] **Step 2: Validate plist syntax**

```bash
plutil -lint cli/launchd/com.voicekeep.analyzer.plist.template
```
Expected: prints `cli/launchd/com.voicekeep.analyzer.plist.template: OK`.

(`plutil` is happy with placeholders that look like strings.)

- [ ] **Step 3: Commit**

```bash
git add cli/launchd/com.voicekeep.analyzer.plist.template
git commit -m "feat(cli): launchd plist template with WatchPaths + Homebrew PATH"
```

---

### Task 7: `setup.sh` installer

**Files:**
- Create: `cli/setup.sh`

- [ ] **Step 1: Write `cli/setup.sh`**

```bash
#!/usr/bin/env bash
# setup.sh — install the Voicekeep analyzer launch agent on this Mac.
# Idempotent: re-running upgrades the plist and reloads the agent.
set -euo pipefail

ROOT="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Voicekeep"
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
```

- [ ] **Step 2: Make executable**

```bash
chmod +x cli/setup.sh
```

- [ ] **Step 3: Run on this Mac**

```bash
./cli/setup.sh
```

Expected: walks through five steps, all `✓`, prints the final summary block.

If `claude` is missing, you'll see a clear error — that's a positive validation of the prereq check.

- [ ] **Step 4: Verify the agent is loaded**

```bash
launchctl print "gui/$(id -u)/com.voicekeep.analyzer" | head -20
```
Expected: shows label, state = `not running`, watch paths includes the inbox.

- [ ] **Step 5: Commit**

```bash
git add cli/setup.sh
git commit -m "feat(cli): idempotent setup.sh — folders, plist, launchctl bootstrap"
```

---

### Task 8: End-to-end CLI smoke test

This task has no new files — it validates the whole CLI half before we touch iOS.

- [ ] **Step 1: Drop the fixture into the real iCloud inbox**

```bash
cp cli/test/sample.voicekeep.json \
   "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Voicekeep/inbox/$(date +%Y-%m-%d-%H%M%S)-smoketest.voicekeep.json"
```

- [ ] **Step 2: Wait for launchd to fire and process**

Wait ~30–60 s, then check logs:
```bash
tail -10 ~/Library/Logs/voicekeep-analyzer.log
```
Expected: lines `analyzing: <name>` then `done: <name>`.

- [ ] **Step 3: Verify output**

```bash
ls "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Voicekeep/processed/" | tail -2
cat "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Voicekeep/processed/"*-smoketest.analysis.md
```
Expected: the .analysis.md exists, has all four `## ...` headers, content in Russian.

- [ ] **Step 4: If smoke test fails, diagnose**

If nothing happened in 60 s:
```bash
launchctl print "gui/$(id -u)/com.voicekeep.analyzer"
cat ~/Library/Logs/voicekeep-analyzer.launchd.log
```
Common causes:
- `claude` not in PATH → fix `EnvironmentVariables` in the plist template.
- Inbox path mismatch → verify the path inside the plist matches the actual iCloud path.
- iCloud Drive disabled or "Optimize Mac Storage" evicted the file → toggle it.

- [ ] **Step 5: Cleanup the smoke-test artifact**

```bash
rm "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Voicekeep/processed/"*-smoketest.*
```

- [ ] **Step 6: No commit needed (smoke test only)**

---

### Task 9: User-facing README

**Files:**
- Create: `cli/README.md`

- [ ] **Step 1: Write `cli/README.md`**

````markdown
# Voicekeep CLI Analyzer

Personal tool. Watches an iCloud Drive folder for transcripts exported from
the Voicekeep iOS app and writes a Markdown analysis next to each one
using `claude -p`.

## Pipeline

```
iPhone                       iCloud Drive                       Mac
──────                       ────────────                       ───
RecordingDetailView          Voicekeep/inbox/  ◄─────────  cli/watch_inbox.sh
  → ShareLink                                                  │ (launchd)
                                                               ▼
                             Voicekeep/processed/  ──── claude -p
                             ├── <name>.voicekeep.json (source)
                             └── <name>.analysis.md   (result)
```

## Prerequisites

- macOS with iCloud Drive signed in to the same Apple ID as the iPhone.
- `claude` CLI in `$PATH`.
- `jq` in `$PATH` (`brew install jq`).

## One-time install (per Mac)

```bash
cd ~/Echograph
./cli/setup.sh
```

This:
- creates `~/Library/Mobile Documents/com~apple~CloudDocs/Voicekeep/{inbox,processed,failed}`,
- renders and installs `~/Library/LaunchAgents/com.voicekeep.analyzer.plist`,
- bootstraps the launch agent (re-runs the bootstrap on upgrades).

## One-time setup on iPhone

1. Open the Files app.
2. Navigate to **iCloud Drive → Voicekeep → inbox**.
3. (Optional) tap the folder and **Add to Favorites** for one-tap access from
   the share sheet later.

## Daily use

1. In Voicekeep, open a recording you want analysed.
2. Tap **Анализ AI** (or **Analyze with AI**).
3. In the share sheet → **Save to Files** → **iCloud Drive / Voicekeep / inbox**.
4. Within ~30 s the analysis Markdown lands in `Voicekeep/processed/`.
   Open it from Files (iOS) or any Markdown viewer (Mac).

## Folders

| Folder | Contents |
|---|---|
| `inbox/` | New `*.voicekeep.json` waiting to be analysed. Empty in steady state. |
| `processed/` | Successful runs: source `.voicekeep.json` + result `.analysis.md`. |
| `failed/` | Failed runs: source + a sibling `*.error.txt` with the cause. Move back to `inbox/` to retry. |

## Logs

- Watcher run-by-run log: `~/Library/Logs/voicekeep-analyzer.log`
- Raw launchd stdout/stderr: `~/Library/Logs/voicekeep-analyzer.launchd.log`

## Force re-analysis of one file

```bash
PROC="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Voicekeep/processed"
rm "$PROC/<name>.analysis.md"
mv "$PROC/<name>.voicekeep.json" "${PROC%/processed}/inbox/"
```

## Uninstall

```bash
launchctl bootout "gui/$(id -u)/com.voicekeep.analyzer"
rm "$HOME/Library/LaunchAgents/com.voicekeep.analyzer.plist"
# iCloud folders kept by default — delete manually if you want them gone.
```

## Cost note

Roughly $0.04 per 30-minute Russian recording at Sonnet pricing
(~12k input + ~2k output tokens). Bash and prompt tweaks are free —
edit `cli/prompts/analyze.md`, drop a JSON in inbox/ to validate.
````

- [ ] **Step 2: Commit**

```bash
git add cli/README.md
git commit -m "docs(cli): user-facing README — install, daily use, folders, logs"
```

---

### Task 10: Push Phase 1 to git

- [ ] **Step 1: Confirm clean tree**

```bash
git status
```
Expected: `nothing to commit, working tree clean`.

- [ ] **Step 2: Push**

```bash
git push
```

Expected: commits flow to origin/main.

- [ ] **Step 3: No further action**

Phase 1 ends here. The pipeline is functional end-to-end on this Mac.

---

## Phase 2 — iOS hookup (built on the Mac with Xcode)

We can't compile here, so each iOS task is "write the code carefully + push". The other Mac builds and reports back.

### Task 11: `AnalysisExport` Transferable

**Files:**
- Create: `Echograph/Echograph/Core/Models/AnalysisExport.swift`

- [ ] **Step 1: Write `AnalysisExport.swift`**

```swift
import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// Wraps a `Recording` for export via Share Sheet to the Voicekeep CLI
/// analyzer (see `cli/README.md` and the v1 schema in
/// `cli/test/expected_schema.json`).
struct AnalysisExport {
    let recording: Recording
}

extension AnalysisExport: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { export in
            let url = try export.writeTemporaryFile()
            return SentTransferredFile(url)
        }
        .suggestedFileName { export in export.suggestedFileName }
    }

    var suggestedFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        let stamp = formatter.string(from: recording.createdAt)
        let safe = sanitize(recording.title)
        return "\(stamp)-\(safe).voicekeep.json"
    }

    fileprivate func writeTemporaryFile() throws -> URL {
        let payload = Payload(recording: recording)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(suggestedFileName)
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url, options: [.atomic])
        return url
    }

    private func sanitize(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics
            .union(.init(charactersIn: " -_"))
        let cleaned = s.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "_" }
            .map(String.init)
            .joined()
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Recording" : cleaned
    }
}

// MARK: - v1 export schema (mirror of cli/test/expected_schema.json)

private extension AnalysisExport {
    struct Payload: Encodable {
        let version: Int
        let id: String
        let title: String
        let createdAt: Date
        let duration: TimeInterval
        let language: String
        let speakerCount: Int
        let tags: [String]
        let transcript: TranscriptPayload?

        init(recording: Recording) {
            self.version = 1
            self.id = recording.id.uuidString
            self.title = recording.title
            self.createdAt = recording.createdAt
            self.duration = recording.duration
            self.language = recording.transcript?.language ?? ""
            self.speakerCount = recording.speakerCount
            self.tags = recording.tags
            self.transcript = recording.transcript.map(TranscriptPayload.init(from:))
        }
    }

    struct TranscriptPayload: Encodable {
        let fullText: String
        let segments: [SegmentPayload]

        init(from t: Transcript) {
            self.fullText = t.fullText
            self.segments = t.segments.map(SegmentPayload.init(from:))
        }
    }

    struct SegmentPayload: Encodable {
        let startTime: TimeInterval
        let endTime: TimeInterval
        let text: String
        let speaker: String?
        let highlighted: Bool?

        init(from s: Transcript.Segment) {
            self.startTime = s.startTime
            self.endTime = s.endTime
            self.text = s.text
            self.speaker = s.speaker?.label
            // Encode `highlighted` only when true; otherwise omit from JSON.
            self.highlighted = s.isHighlighted ? true : nil
        }

        // `speaker` and `highlighted` are nil-omitted by JSONEncoder.
    }
}
```

Notes for the engineer:
- `Recording.id`, `Recording.title`, `Recording.createdAt`, `Recording.duration`, `Recording.speakerCount`, `Recording.tags`, `Recording.transcript` are existing fields (see `Echograph/Core/Models/Recording.swift`).
- `Transcript.language`, `Transcript.segments`, `Transcript.fullText`, `Transcript.Segment.startTime/.endTime/.text/.speaker/.isHighlighted` are existing (see `Echograph/Core/Models/Transcript.swift`).
- `Speaker` has `{id: UUID, label: String}` — we deliberately drop the UUID and emit just the label.
- `JSONEncoder` omits keys whose value is `nil` for `Optional` types automatically when the type uses synthesised `Encodable`.

- [ ] **Step 2: Add to `project.yml` if needed**

`project.yml` already includes everything under `path: Echograph`, so no change is required. Verify:

```bash
grep -n "path: Echograph" project.yml
```
Expected: shows `path: Echograph` (no excludes for the Models directory).

- [ ] **Step 3: Commit**

```bash
git add Echograph/Echograph/Core/Models/AnalysisExport.swift
git commit -m "feat(ios): AnalysisExport — Transferable wrapping Recording → v1 JSON"
```

---

### Task 12: ShareLink in `RecordingDetailView`

**Files:**
- Modify: `Echograph/Echograph/UI/RecordingDetailView.swift`
- Modify: `Echograph/Echograph/Resources/Localizable.xcstrings`

- [ ] **Step 1: Read the existing Export-menu area in `RecordingDetailView.swift`**

Find the existing `ShareLink`/Export Menu by running:

```bash
grep -n "ShareLink\|ExportSheet\|toolbar" Echograph/Echograph/UI/RecordingDetailView.swift | head -30
```

Use the line numbers it prints to navigate. The new `ShareLink` for `AnalysisExport` should sit either:
- inside the same toolbar `Menu` that hosts the existing exports, or
- as a separate `ShareLink` button next to the export Menu — whichever matches the existing visual pattern.

- [ ] **Step 2: Add the `ShareLink`**

Insert into the toolbar (or relevant context menu) of `RecordingDetailView`:

```swift
ShareLink(
    item: AnalysisExport(recording: recording),
    preview: SharePreview(
        Text("recording.detail.analyze.share.preview", tableName: nil),
        image: Image(systemName: "sparkles")
    )
) {
    Label(
        String(localized: "recording.detail.analyze.menu.label"),
        systemImage: "sparkles"
    )
}
.disabled(recording.transcript == nil)
```

The `disabled` modifier prevents exporting when there's no transcript — sharing an empty analysis would just confuse the CLI.

- [ ] **Step 3: Add localised strings**

Open `Echograph/Echograph/Resources/Localizable.xcstrings` and add two keys (Xcode UI is the easiest path; raw JSON edits work too):

| Key | en | ru |
|---|---|---|
| `recording.detail.analyze.menu.label` | "Analyze with AI" | "Анализ AI" |
| `recording.detail.analyze.share.preview` | "Voicekeep AI Analysis" | "Voicekeep: анализ AI" |

If editing the JSON directly, the structure is:

```json
"recording.detail.analyze.menu.label" : {
  "extractionState" : "manual",
  "localizations" : {
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Analyze with AI" } },
    "ru" : { "stringUnit" : { "state" : "translated", "value" : "Анализ AI" } }
  }
}
```

- [ ] **Step 4: Verify the file is valid JSON**

```bash
jq -e '.strings."recording.detail.analyze.menu.label"' \
   Echograph/Echograph/Resources/Localizable.xcstrings
```
Expected: prints the localisation block.

- [ ] **Step 5: Commit**

```bash
git add Echograph/Echograph/UI/RecordingDetailView.swift \
        Echograph/Echograph/Resources/Localizable.xcstrings
git commit -m "feat(ios): ShareLink → AnalysisExport on RecordingDetailView"
```

---

### Task 13: Push Phase 2 + manual end-to-end test

This is the handoff to the Mac with Xcode.

- [ ] **Step 1: Push**

```bash
git push
```

- [ ] **Step 2: On the Xcode Mac, pull and build**

```bash
cd ~/Echograph
git pull
xcodegen generate
open Echograph.xcodeproj
```

In Xcode: select **iPhone 17 Pro** simulator → Cmd+R.

- [ ] **Step 3: Smoke test the iOS hook**

In the simulator (or on a real iPhone if signed in):

1. Record a 30-second test memo or use an existing recording with a completed transcript.
2. Open the recording → **Анализ AI** button.
3. From the system Share Sheet, **Save to Files → iCloud Drive → Voicekeep → inbox**.
4. (If the simulator is on the same Apple ID as the dev Mac running the watcher) within ~30 s the analysis lands in `Voicekeep/processed/<name>.analysis.md`.
5. Open the file in any Markdown viewer and verify the four sections.

For the simulator iCloud sync may not work — if so, copy the file from the simulator container manually to validate the JSON shape:

```bash
# On the dev Mac, find the simulator's tmp file by recent mtime:
find ~/Library/Developer/CoreSimulator -name "*.voicekeep.json" -mtime -1
```

Or simply test on a real iPhone signed into the same iCloud account.

- [ ] **Step 4: Verify JSON shape matches `cli/test/expected_schema.json`**

```bash
jq 'keys' "<the exported voicekeep.json from step 3>"
```
Expected keys: `["createdAt", "duration", "id", "language", "speakerCount", "tags", "title", "transcript", "version"]` (alphabetised because of `.sortedKeys`).

If a field is missing or shaped unexpectedly, fix `AnalysisExport.swift` and repeat.

- [ ] **Step 5: No commit (manual test only)**

---

## Self-review checklist

The plan author runs this once after writing:

1. **Spec coverage:** Every spec section has at least one task implementing it.
   - Architecture overview → Tasks 1, 5, 6, 7 (CLI half), Tasks 11–12 (iOS half).
   - Repository layout → Tasks 1, 11 (creates the listed files).
   - JSON schema v1 → Tasks 1, 2 (fixtures), Task 11 (encoder).
   - Filename convention → Task 11 (`suggestedFileName`).
   - Mac side scripts → Tasks 4, 5, 6, 7.
   - Prompt → Task 3.
   - Error-handling table → Task 5 (lock + idempotency + JSON validation + failed routing) and Task 8 (failure-path verification).
   - Testing → Tasks 5 (routing tests), 8 (e2e CLI smoke), 13 (e2e iOS smoke).
   - Risks/open questions → no implementation; documented in spec only.
   - Implementation milestones → this plan IS the expansion.

2. **Placeholder scan:** Searched for "TBD"/"TODO"/"implement later"/"add error handling"/"similar to" — none present. All steps have either commands, code blocks, or explicit verification expectations.

3. **Type consistency:**
   - `AnalysisExport` defined in Task 11 is referenced (only) in Task 12 — same name.
   - Schema field names (`speakerCount`, `tags`, `highlighted`, `language`) match between `cli/test/sample.voicekeep.json` (Task 1), `cli/test/expected_schema.json` (Task 2), `cli/prompts/analyze.md` (Task 3), and `AnalysisExport.swift` (Task 11). Verified by re-reading.
   - Path constants `INBOX/PROCESSED/FAILED` consistent between `watch_inbox.sh` (Task 5) and `setup.sh` (Task 7).
   - launchd label `com.voicekeep.analyzer` consistent between plist (Task 6), setup.sh (Task 7), and uninstall instructions (Task 9).
