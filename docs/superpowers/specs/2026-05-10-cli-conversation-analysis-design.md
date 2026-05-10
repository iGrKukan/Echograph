# CLI Conversation Analysis (personal prototype)

**Status:** Approved design, ready for implementation plan
**Date:** 2026-05-10
**Author:** Claude (brainstorming with @iGrKukan)
**Scope:** Personal prototype only. NOT for App Store / Pro+ subscribers.

## Goal

Add a Plaud-style AI analysis pipeline to Voicekeep for the author's own use:
**iPhone records and transcribes → user taps Analyze → Mac picks it up via
iCloud Drive and writes a four-section Markdown analysis next to the source.**

The prototype validates prompts, UX flow, and analysis quality on real
recordings before committing to a server-backed Pro+ feature.

## Non-goals (explicitly out of scope)

- Any backend or Anthropic API integration. Uses local `claude` CLI only.
- Distribution to other users. The pipeline assumes the author's machines and
  Apple ID.
- Multiple analysis presets. Single fixed prompt for v1.
- Writing analysis back into the iOS app. Result lives only as Markdown on disk.
- Multi-recording memory / cross-conversation context.
- Custom follow-up Q&A on a transcript.
- iCloud entitlement / app-private CloudKit container. Uses user-visible
  iCloud Drive folder.
- Real-time / streaming output. Batch run after Share Sheet trigger.
- Anything on watchOS, Live Activity, or Action Button.

## Use cases (user picked all four)

1. Business calls and negotiations with suppliers/clients.
2. Internal meetings with employees.
3. Voice memos and brainstorms (mono-speaker).
4. Interviews / one-on-ones.

The single fixed prompt must produce useful output for all four. Specialised
prompts per scenario are deferred to a possible v2 (multi-preset, "approach B"
in brainstorm).

## Output sections (user picked all four)

The analysis Markdown contains exactly these four sections, in this order, in
**Russian**:

1. `## Резюме` — TL;DR (1–2 paragraphs) + 5–10 bullet key points.
2. `## Договорённости и обещания` — table `| Что | Кто | Срок | Цитата (mm:ss) |`.
3. `## Решения и открытые вопросы` — two sub-lists.
4. `## Темы` — Markdown-tree mind map.

## Architecture overview

```
┌──────────────────┐                    ┌──────────────────────┐
│   iPhone         │                    │   Mac (with Xcode    │
│                  │                    │    + claude CLI)     │
│  RecordingDetail │  Share Sheet       │                      │
│      View        │  → JSON file       │  launchd WatchPaths  │
│                  │   to iCloud Drive  │       │              │
│  ShareLink ──────┼────┐               │       ▼              │
│                  │    │               │  voicekeep_          │
└──────────────────┘    │               │   analyze.sh         │
                        │               │       │              │
                        ▼               │       ▼              │
        ┌────────────────────────────┐  │   claude -p          │
        │    iCloud Drive            │  │       │              │
        │  Voicekeep/                │  │       ▼              │
        │  ├── inbox/    ◄───────────┼──┘  .analysis.md ──┐    │
        │  ├── processed/ ◄───────────────────────────────┘    │
        │  └── failed/                                          │
        └────────────────────────────┘                          │
                  ▲                                             │
                  └─────────── visible in iOS Files app ────────┘
```

The shared iCloud Drive folder `~/Library/Mobile Documents/com~apple~CloudDocs/Voicekeep/`
is the only integration surface between iOS and Mac. Both ends operate
asynchronously through the filesystem.

## Repository layout

```
Echograph/
├── Echograph/
│   └── UI/
│       └── RecordingDetailView.swift      # MODIFIED — adds ShareLink
├── Echograph/Core/
│   └── Models/
│       └── AnalysisExport.swift           # NEW — Transferable wrapper
└── cli/                                   # NEW directory
    ├── voicekeep_analyze.sh
    ├── prompts/
    │   └── analyze.md
    ├── launchd/
    │   └── com.voicekeep.analyzer.plist.template
    ├── setup.sh
    └── README.md
```

`cli/` is versioned in the same repo as iOS code. Same git checkout works on
both Macs (the dev Mac with Xcode and any other Mac running the watcher).

## iOS side

### `AnalysisExport` (new)

A `Transferable` wrapper around `Recording` that produces a `.voicekeep.json`
file payload. Lives at `Echograph/Core/Models/AnalysisExport.swift`.

**Transferable representation:** `FileRepresentation(exportedContentType: .json)`
that writes a temporary file with the encoded payload.

**JSON schema (v1):**

```json
{
  "version": 1,
  "id": "<UUID>",
  "title": "Звонок с поставщиком",
  "createdAt": "2026-05-10T14:23:11Z",
  "duration": 1247.3,
  "language": "ru",
  "speakerCount": 2,
  "tags": ["поставщики", "доска"],
  "transcript": {
    "fullText": "...",
    "segments": [
      {
        "startTime": 0.0,
        "endTime": 4.2,
        "text": "Здравствуйте, я по поводу...",
        "speaker": "Иван",
        "highlighted": true
      }
    ]
  }
}
```

- `version` — integer; the CLI rejects unknown versions with a clear error.
- `language` — copied from `Transcript.language` (existing field). Empty
  string is possible; the prompt treats empty as "auto-detect from text".
- `speakerCount` — copied from `Recording.speakerCount`; helps the prompt
  decide whether to expect dialog or monologue.
- `tags` — array of user-applied tags from `Recording.tags`. Empty array if
  none. Used as soft hint to the prompt.
- `speaker` (per segment) — **flattened to label string only**. The model's
  `Speaker` struct has `{id, label}`; `AnalysisExport`'s custom encoder
  drops the UUID and emits just the label. Field is omitted entirely when
  the segment has no speaker assigned.
- `highlighted` (per segment) — `true` only if user marked the segment as a
  highlight in the app. Field is omitted when `false`. The prompt is told
  to weight highlighted segments more heavily.
- Word-level timestamps (existing `segment.words`) and segment `id` are
  deliberately **not** included — too verbose, no analysis value at this
  stage. Can be added later if prompt needs them.
- `Recording.summary` (existing field, written by `SummaryService` from
  Apple Foundation Models) is **not** included — would bias the prompt
  toward the prior summary instead of an independent read.
- `Recording.filename` is **not** included — internal storage detail.

### Filename convention

The Transferable representation suggests filename:

```
<yyyy-MM-dd-HHmmss>-<safe-title>.voicekeep.json
```

- `safe-title` is `Recording.title` with non-alphanumerics replaced by `_`
  (reuses the sanitiser in `TranscriptExporter`).
- The `.voicekeep.json` double extension is intentional: it's still valid JSON
  for any tool, but lets the watcher filter for our files specifically and
  avoids colliding with user files in iCloud Drive.

### `RecordingDetailView` change

A single SwiftUI `ShareLink` is added, near the existing Export menu. Label:
"Analyze with AI" (Russian: "Анализ AI"). Localised in `Localizable.xcstrings`.

The Share Sheet is fully system-driven. The user picks "Save to Files" once
and navigates to `iCloud Drive → Voicekeep → inbox`; iOS remembers the recent
location for next time. No iCloud entitlement is required because the user
chooses the destination through the system file picker.

The folder `Voicekeep/inbox` does NOT need to pre-exist on iOS — the user
creates it in the Files app once during setup (covered in `cli/README.md`).

## Mac side

### `cli/voicekeep_analyze.sh`

A bash script with no external dependencies beyond:

- `claude` (already installed)
- `jq` (only for input validation; `brew install jq` if missing — `setup.sh`
  checks)
- `flock` (built-in on macOS via `/usr/bin/flock` — actually, macOS lacks
  `flock`; we use `mkdir` as a poor man's lock instead)

**Pseudocode:**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Voicekeep"
INBOX="$ROOT/inbox"
PROCESSED="$ROOT/processed"
FAILED="$ROOT/failed"
LOCK_DIR="$HOME/Library/Caches/voicekeep-analyzer.lock"
LOG="$HOME/Library/Logs/voicekeep-analyzer.log"
PROMPT="$(dirname "$0")/prompts/analyze.md"

# Lock (mkdir is atomic on POSIX)
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "[$(date -Iseconds)] another instance running, exit" >> "$LOG"
  exit 0
fi
trap 'rmdir "$LOCK_DIR"' EXIT

mkdir -p "$INBOX" "$PROCESSED" "$FAILED"

shopt -s nullglob
for f in "$INBOX"/*.voicekeep.json; do
  name="$(basename "$f" .voicekeep.json)"
  out="$PROCESSED/$name.analysis.md"

  # Idempotency: if analysis already exists, just clean inbox
  if [ -f "$out" ]; then
    mv "$f" "$PROCESSED/"
    echo "[$(date -Iseconds)] skip (already analysed): $name" >> "$LOG"
    continue
  fi

  # Validate JSON
  if ! jq -e '.version == 1 and .transcript.fullText' "$f" >/dev/null 2>&1; then
    mv "$f" "$FAILED/"
    echo "invalid JSON or unsupported version" > "$FAILED/$name.error.txt"
    echo "[$(date -Iseconds)] invalid: $name" >> "$LOG"
    continue
  fi

  # Run analysis
  echo "[$(date -Iseconds)] analyzing: $name" >> "$LOG"
  if claude -p "$(cat "$PROMPT")" --model sonnet < "$f" > "$out.tmp" 2> "$out.err"; then
    mv "$out.tmp" "$out"
    mv "$f" "$PROCESSED/"
    rm -f "$out.err"
    echo "[$(date -Iseconds)] done: $name" >> "$LOG"
  else
    rc=$?
    mv "$f" "$FAILED/"
    mv "$out.err" "$FAILED/$name.error.txt"
    rm -f "$out.tmp"
    echo "[$(date -Iseconds)] FAILED ($rc): $name" >> "$LOG"
  fi
done
```

**Why bash:** zero install steps for the user, no virtualenv, no Python deps.
The script is ~80 lines including comments.

**Why `mkdir` lock instead of `flock`:** macOS lacks `flock(1)` by default and
we don't want a Homebrew dependency. `mkdir` is atomic enough for a watcher
that's debounced by launchd.

### `cli/prompts/analyze.md`

The prompt is committed in the repo and read at runtime. Structure:

```markdown
Ты помощник для разбора аудиозаписей разговоров. На вход получаешь
JSON со структурой:

  {
    "title": "...",
    "createdAt": "ISO 8601",
    "duration": <seconds>,
    "language": "ru" | "en" | ... | "",
    "speakerCount": <int>,
    "tags": [<string>...],
    "transcript": {
      "fullText": "...",
      "segments": [
        {
          "startTime": <sec>,
          "endTime": <sec>,
          "text": "...",
          "speaker": "<label>" | absent,
          "highlighted": true | absent
        }
      ]
    }
  }

Верни Markdown-отчёт строго на русском, с заголовками первого
уровня (`##`) в этом порядке:

## Резюме
TL;DR в 1-2 абзацах + 5-10 буллетов ключевых тезисов.

## Договорённости и обещания
Markdown-таблица:
| Что | Кто | Срок | Цитата (mm:ss) |
Если в транскрипте нет имён/спикеров — оставь "Кто" пустым.
Цитаты — дословные, mm:ss считается из startTime сегмента.

## Решения и открытые вопросы
Два подсписка:
**Решено:** ...
**Открыто:** ...

## Темы
Markdown-дерево вложенных списков. Корни — главные темы, листья — конкретика.

ПРАВИЛА:
- Никогда не выдумывай факты. Если в транскрипте нет — не пиши.
- Не приписывай реплики спикерам, если speaker отсутствует.
- Цитируй дословно, без перефразирования.
- Сегменты с "highlighted": true важны автору — учитывай их в Резюме.
- speakerCount = 1 значит монолог: Action items могут отсутствовать,
  Договорённости — тоже. Это ок, не выдумывай.
- tags — это пользовательские ярлыки, могут служить мягким контекстом
  для темы разговора, но не более.
- Если разговор пустой / шум / не разговор — верни одну строку:
  "Анализ невозможен: <причина>".
```

The exact prompt text is finalised during implementation but the structure
above is binding.

### launchd plist

`com.voicekeep.analyzer.plist.template`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.voicekeep.analyzer</string>
  <key>ProgramArguments</key>
  <array>
    <string>__SCRIPT_PATH__</string>
  </array>
  <key>WatchPaths</key>
  <array>
    <string>__INBOX__</string>
  </array>
  <key>StandardOutPath</key>
  <string>__LOG__</string>
  <key>StandardErrorPath</key>
  <string>__LOG__</string>
  <key>RunAtLoad</key><false/>
</dict>
</plist>
```

`setup.sh` substitutes the three placeholders and writes the result to
`~/Library/LaunchAgents/com.voicekeep.analyzer.plist`.

`WatchPaths` fires on any change inside `inbox/` — including new `.voicekeep.json`
files arriving from iCloud sync. The script itself moves files OUT of inbox
to avoid an infinite loop.

### `cli/setup.sh`

Idempotent installer. Executes:

1. Verify prerequisites: `claude --version`, `jq --version`. Stop with clear
   message if missing.
2. `mkdir -p` for `inbox/`, `processed/`, `failed/` in iCloud Drive.
3. Render `launchd/com.voicekeep.analyzer.plist.template` to
   `~/Library/LaunchAgents/com.voicekeep.analyzer.plist`.
4. `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.voicekeep.analyzer.plist`
   (modern replacement for `launchctl load`).
5. Touch a marker file in `inbox/` to verify watcher fires once, then remove it.
6. Print success message with paths to logs and folders.

Re-running is safe: bootstrap fails silently if already loaded, mkdirs are
no-ops, plist render is overwrite.

## Error handling

| Scenario | Behaviour |
|---|---|
| `claude` returns non-zero | Move source to `failed/`, write `<name>.error.txt` with stderr, log line. |
| `claude` not in `$PATH` | Log fatal error, exit; nothing moves so file retries on next run. |
| Network unreachable | Same as `claude` failure: source → `failed/`, error txt has the cause. User reruns by moving back to `inbox/`. |
| Source JSON invalid (wrong version, missing transcript) | Source → `failed/`, error txt explains. |
| iCloud Drive not yet synced (file appears empty) | `jq -e` validation catches; same as invalid JSON. The full file arrives when iCloud syncs and the user can move it back to `inbox/` for retry. |
| Two files arrive at once | First run handles both in the `for` loop. Second `WatchPaths` fire is blocked by `mkdir` lock, exits silently. |
| Pre-existing `.analysis.md` (manual rerun) | Idempotency check skips, source is just moved to `processed/`. To force re-analysis, delete the `.analysis.md` first. |
| User manually edits a file in `processed/` | Watcher doesn't see it (only `inbox/` is watched). |

Logs always go to `~/Library/Logs/voicekeep-analyzer.log` — one timestamped
line per file processed. No log rotation in v1; the file stays small enough
that the user can `> "$LOG"` manually if needed.

## Testing

Manual verification (no automated tests for the CLI in v1):

1. **Smoke test on Mac without iPhone:**
   - Hand-write a sample `.voicekeep.json` with a 2-minute mock transcript.
   - Drop it in `inbox/`.
   - Verify `.analysis.md` appears in `processed/` within 30 seconds with the
     four required sections.

2. **End-to-end with iPhone:**
   - Record a 1-minute test memo on iPhone.
   - Tap "Analyze with AI" → save to iCloud → wait for sync (~10–30 s).
   - Verify the analysis lands in `processed/` and renders correctly when
     opened in any Markdown viewer.

3. **Failure modes:**
   - Drop a malformed `*.voicekeep.json` (e.g. `{"version": 99}`) and confirm
     it ends up in `failed/` with a useful `.error.txt`.
   - Disable Wi-Fi, drop a valid file, confirm it lands in `failed/` with
     network error in stderr.

4. **iOS side:**
   - Existing `EchographUITests/SnapshotTests` regenerate App Store
     screenshots — verify they still pass after adding the ShareLink (no UI
     regression on `RecordingDetailView`).

5. **Localisation:**
   - The new "Анализ AI" / "Analyze with AI" string is present in
     `Localizable.xcstrings` for at least `en`, `ru`. Other locales can fall
     back to English in v1.

## Risks and open questions

- **Prompt quality on long recordings (>30 minutes).** Sonnet handles 200k
  tokens but the analysis quality on dense multi-hour conversations is
  unknown. v1 ships with a single hard cap (warning if input >150k chars,
  proceed anyway); revisit after first real recordings.
- **iCloud Drive sync latency.** Anecdotally 5–60 seconds; if unacceptable
  the future Pro+ version will use a direct upload to a backend.
- **Apple Foundation Models overlap.** The existing `SummaryService` already
  produces a summary on iPhone 15 Pro+ devices. The CLI prototype is
  intentionally separate (different data path, different audience: author
  himself on a Mac). They coexist without code overlap.
- **Cost.** A 30-minute Russian recording transcribes to ~10–15 k input tokens
  + ~2 k output. At Sonnet pricing (~$3/$15 per million) that's ~$0.04 per
  recording. Acceptable for personal use; meaningful at scale.

## Implementation milestones (rough)

To be expanded in the implementation plan (next step):

1. iOS: `AnalysisExport.swift` + ShareLink in `RecordingDetailView`. Local
   smoke test — file appears in iCloud Drive.
2. Mac: `voicekeep_analyze.sh` + `prompts/analyze.md`. Manual run on a sample
   JSON, verify output quality on 2-3 real transcripts.
3. Mac: `setup.sh` + launchd plist. End-to-end test with iPhone.
4. Iterate on prompt with 5–10 real recordings spanning the four use cases.
5. Document in `cli/README.md` and commit.
