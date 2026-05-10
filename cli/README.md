# Voicekeep CLI Analyzer

Personal tool. Watches the Voicekeep iOS app's iCloud container for
transcripts and writes a Markdown analysis next to each one using
`claude -p`. The result is automatically read back by the iOS app and
displayed in `RecordingDetailView` (Phase B) — no manual file picking.

## Pipeline

```
iPhone                       iCloud (app container)             Mac
──────                       ──────────────────────             ───
RecordingDetailView          inbox/<id>.voicekeep.json  ◄─  cli/watch_inbox.sh
  → AI-анализ button                  │                          │ (launchd)
                                      │                          ▼
RecordingDetailView         processed/<id>.analysis.md  ──── claude -p
  → AnalysisSection (MarkdownUI) ◄────┘
```

In Files app on iPhone the container appears as **iCloud Drive → Voicekeep**.
On macOS the path is `~/Library/Mobile Documents/iCloud~by~timberbid~echograph/Documents/`.

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
- creates `~/Library/Mobile Documents/iCloud~by~timberbid~echograph/Documents/{inbox,processed,failed}`,
- renders and installs `~/Library/LaunchAgents/com.voicekeep.analyzer.plist`,
- bootstraps the launch agent (re-runs the bootstrap on upgrades).

## One-time setup on iPhone

After the app is installed and signed into iCloud, the Voicekeep folder
is created automatically in iCloud Drive. No manual step is required.

## Daily use

1. In Voicekeep, open a recording you want analysed.
2. Tap **AI-анализ…** (or **Analyze with AI…**) in the toolbar menu.
3. The JSON is written directly to the app's iCloud container (no Share Sheet).
4. Within ~30 s the analysis Markdown lands in the same container's
   `processed/` and the **AI Analysis** section appears in the recording
   detail view (rendered via `MarkdownUI`).

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
PROC="$HOME/Library/Mobile Documents/iCloud~by~timberbid~echograph/Documents/processed"
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
