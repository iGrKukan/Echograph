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
