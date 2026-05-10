# Voicekeep CLI Analyzer

Personal tool. A small HTTP server on the Mac receives transcripts from the
Voicekeep iOS app over Tailscale, runs `claude -p`, and returns Markdown.
The result is persisted in the recording and shown via `MarkdownUI`.

## Pipeline

```
iPhone (Voicekeep app)                Mac (in Tailscale tailnet)
──────────────────────                ──────────────────────────
RecordingDetailView                   cli/server.py
  → AI-анализ tap                     │ (launchd KeepAlive=true, port 19847)
  POST /analyze ───────────────────►  /analyze handler
       Bearer <token>                 │
       {recording JSON v1}            voicekeep_analyze.sh
                                      │
  ◄──────────── 200 OK ──────────── claude -p --model sonnet
       <four-section markdown>
  recording.analysis = body
  AnalysisSection (MarkdownUI) renders
```

## Prerequisites

- macOS with `claude`, `jq`, `python3` (3.10+) in `$PATH`.
- Tailscale on **both** Mac and iPhone (same tailnet) — recommended.
  Without Tailscale you can use `<mac-hostname>.local` over LAN.

## One-time install (per Mac)

```bash
cd ~/Echograph
./cli/setup.sh
```

The script:
- generates a bearer token at `~/.voicekeep-token` (only if missing),
- renders `~/Library/LaunchAgents/com.voicekeep.analyzer.plist`,
- bootstraps the launch agent (KeepAlive + RunAtLoad),
- prints the **URL** and **token** to paste into the iOS app.

Server listens on `0.0.0.0:19847` (port configurable via `VOICEKEEP_PORT`).

## One-time setup on iPhone

1. Install **Tailscale** from the App Store and log into the same tailnet.
2. Open Voicekeep → **Settings (Done) → AI Analyzer**.
3. Paste the **Tailscale URL** (e.g. `http://100.115.132.84:19847`).
4. Paste the **Bearer token** (from `~/.voicekeep-token`).
5. Tap **Test connection** → should turn green ("Connected").

## Daily use

1. In Voicekeep, open a recording with a finished transcript.
2. Tap **AI-анализ…** in the toolbar menu.
3. The button shows "Analysing…" for ~25–30 s.
4. The **AI Analysis** section appears in the recording with the rendered
   four-section Markdown (Резюме / Договорённости / Решения / Темы).

The analysis is persisted in the recording's metadata (in `recordings.json`)
so it survives app restarts.

## Endpoints

| Verb | Path | Auth | Description |
|---|---|---|---|
| GET  | `/health`  | none | Liveness probe; replies `ok`. |
| POST | `/analyze` | `Authorization: Bearer <token>` | Body = v1 JSON; returns Markdown. |

## Logs

- launchd stdout/stderr: `~/Library/Logs/voicekeep-analyzer.launchd.log`
- Includes per-request lines (`POST /analyze`, status codes, durations).

## Test from the command line

```bash
TOKEN="$(cat ~/.voicekeep-token)"
curl -X POST http://127.0.0.1:19847/analyze \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  --data @cli/test/sample.voicekeep.json
```

Should return ~2-3 KB of Markdown after ~25 s.

## Uninstall

```bash
launchctl bootout "gui/$(id -u)/com.voicekeep.analyzer"
rm "$HOME/Library/LaunchAgents/com.voicekeep.analyzer.plist"
# Token kept by default; delete with: rm ~/.voicekeep-token
```

## Cost note

~$0.04 per 30-minute Russian recording at Sonnet pricing
(~12k input + ~2k output tokens). Edit `cli/prompts/analyze.md` to tune;
no rebuild needed — the next request reads it from disk.
