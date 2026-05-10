# Phase C: HTTP transport (replaces Phase B iCloud)

> Replaces the iCloud Container transport from Phase B with a direct HTTP API on the Mac, accessed by iPhone via Tailscale. Closer architecturally to the future Pro+ backend (just swap the URL).

**Goal:** iPhone POSTs the recording JSON to `http://<mac-tailscale-ip>:8765/analyze` with a Bearer token; Mac runs `claude -p`; markdown body comes back synchronously and is persisted in `Recording.analysis: String?`.

**Architecture:**

```
iPhone                                Mac (in Tailscale tailnet)
──────                                ──────────────────────────
RecordingDetailView                   cli/server.py
  → AI-анализ tap                     │ launchd KeepAlive=true
  POST /analyze ───────────────────►  /analyze handler
       Bearer <token>                 │
       {recording JSON}              voicekeep_analyze.sh
                                      │
  ◄──────────── 200 OK ──────────── claude -p
       <markdown>
  recording.analysis = body
  AnalysisSection (MarkdownUI) renders
```

**What we remove from Phase B:** iCloud entitlement, NSUbiquitousContainers, `AnalysisStore` (NSMetadataQuery), file-watcher launchd plist.

**What we keep from Phase B:** `AnalysisSection.swift` (render), `MarkdownUI` dep, localizations, CLI analyzer + prompt.

**What we add:** Python HTTP server on Mac, iOS `AnalysisService` (URLSession client), Settings UI for URL+token, `Recording.analysis` field for persistence.

---

## Tasks

### C1: Remove Phase B iCloud surface (clean slate)

**Files:**
- Delete: `Echograph/Echograph.entitlements`
- Delete: `Echograph/Echograph/Core/Stores/AnalysisStore.swift`
- Modify: `Echograph/project.yml` (remove `CODE_SIGN_ENTITLEMENTS`, remove `NSUbiquitousContainers`)
- Modify: `Echograph/Echograph/App/EchographApp.swift` (remove `analysisStore` state and env)

- [ ] **Step 1: Delete files**

```bash
cd ~/Echograph
git rm Echograph/Echograph.entitlements Echograph/Core/Stores/AnalysisStore.swift
```

- [ ] **Step 2: Edit `project.yml` — remove entitlement and NSUbiquitousContainers**

Remove:
```yaml
CODE_SIGN_ENTITLEMENTS: Echograph/Echograph.entitlements
```
And the `NSUbiquitousContainers:` block under `info.properties`.

- [ ] **Step 3: Edit `EchographApp.swift` — remove `analysisStore`**

Remove the `@State private var analysisStore: AnalysisStore`, the init line, and `.environment(analysisStore)`.

- [ ] **Step 4: Regenerate xcodeproj**

```bash
xcodegen generate
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(ios): remove iCloud Container surface (replaced by HTTP in Phase C)"
```

---

### C2: Add `analysis: String?` to Recording

**Files:**
- Modify: `Echograph/Echograph/Core/Models/Recording.swift`

- [ ] **Step 1: Add field with backwards-compatible decoding**

Add `var analysis: String?` to the struct fields. Add it to `CodingKeys`. In `init(from decoder:)`:

```swift
self.analysis = try c.decodeIfPresent(String.self, forKey: .analysis)
```

- [ ] **Step 2: Commit**

```bash
git add Echograph/Echograph/Core/Models/Recording.swift
git commit -m "feat(ios): Recording.analysis: String? — persisted markdown analysis"
```

---

### C3: Mac side — `cli/server.py` HTTP server

**Files:**
- Create: `cli/server.py`
- Modify: `cli/launchd/com.voicekeep.analyzer.plist.template` (KeepAlive instead of WatchPaths)
- Modify: `cli/setup.sh` (generate token, install HTTP server, print Tailscale URL)

- [ ] **Step 1: Write `cli/server.py`**

Python stdlib only (no pip deps). ~80 lines. Bearer token from env var. Calls `voicekeep_analyze.sh` per request.

```python
#!/usr/bin/env python3
"""Voicekeep analyzer HTTP server.
POST /analyze with Bearer token + JSON body → runs claude -p, returns markdown.
"""
import json
import os
import subprocess
import sys
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

CLI_DIR = Path(__file__).resolve().parent
ANALYZER = CLI_DIR / "voicekeep_analyze.sh"
TOKEN = os.environ.get("VOICEKEEP_TOKEN")
PORT = int(os.environ.get("VOICEKEEP_PORT", "8765"))

if not TOKEN:
    print("FATAL: VOICEKEEP_TOKEN env var not set", file=sys.stderr)
    sys.exit(1)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write(f"[{self.address_string()}] {fmt % args}\n")

    def _reject(self, code, msg):
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(msg.encode("utf-8"))

    def do_POST(self):
        if self.path != "/analyze":
            return self._reject(404, "not found")

        auth = self.headers.get("Authorization", "")
        if auth != f"Bearer {TOKEN}":
            return self._reject(401, "unauthorized")

        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > 10_000_000:
            return self._reject(400, "bad content length")

        body = self.rfile.read(length)
        try:
            doc = json.loads(body)
            if doc.get("version") != 1 or "transcript" not in doc:
                raise ValueError("schema")
        except Exception as e:
            return self._reject(400, f"bad JSON: {e}")

        with tempfile.NamedTemporaryFile(
            mode="wb", suffix=".voicekeep.json", delete=False
        ) as src:
            src.write(body)
            src_path = src.name
        out_path = src_path.replace(".voicekeep.json", ".analysis.md")

        try:
            res = subprocess.run(
                [str(ANALYZER), src_path, out_path],
                capture_output=True, text=True, timeout=120
            )
            if res.returncode != 0:
                return self._reject(502, f"analyzer failed: {res.stderr}")
            md = Path(out_path).read_text(encoding="utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/markdown; charset=utf-8")
            self.send_header("Content-Length", str(len(md.encode("utf-8"))))
            self.end_headers()
            self.wfile.write(md.encode("utf-8"))
        finally:
            for p in (src_path, out_path):
                try:
                    os.unlink(p)
                except FileNotFoundError:
                    pass

    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"ok\n")
        else:
            self._reject(404, "not found")


def main():
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"voicekeep server listening on 0.0.0.0:{PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Update launchd plist template**

Replace `WatchPaths` block with KeepAlive + ProgramArguments pointing to python3 server.py:

```xml
<key>ProgramArguments</key>
<array>
    <string>/usr/bin/env</string>
    <string>python3</string>
    <string>__SERVER_PATH__</string>
</array>
<key>KeepAlive</key>
<true/>
<key>RunAtLoad</key>
<true/>
<key>EnvironmentVariables</key>
<dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    <key>VOICEKEEP_TOKEN</key>
    <string>__TOKEN__</string>
    <key>VOICEKEEP_PORT</key>
    <string>__PORT__</string>
</dict>
```

(Remove WatchPaths key entirely.)

- [ ] **Step 3: Update `cli/setup.sh`**

- Generate token if `~/.voicekeep-token` doesn't exist (`openssl rand -hex 32`).
- Render new plist with `__SERVER_PATH__`, `__TOKEN__`, `__PORT__` placeholders.
- After bootstrap, print:
  ```
  ✓ Server URL (Tailscale): http://<tailscale-ip>:8765
  ✓ Token: <token>
  ```
  Use `tailscale ip -4` if available; else fall back to `hostname -s`.

Detailed code in implementation.

- [ ] **Step 4: Make server.py executable**

```bash
chmod +x cli/server.py
```

- [ ] **Step 5: Run setup.sh and verify health**

```bash
./cli/setup.sh
curl -i http://localhost:8765/health
```

Expected: `HTTP/1.0 200 OK` + `ok`.

- [ ] **Step 6: Smoke test /analyze locally**

```bash
TOKEN=$(cat ~/.voicekeep-token)
curl -X POST http://localhost:8765/analyze \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  --data @cli/test/sample.voicekeep.json
```

Expected: ~30 s, returns the four-section markdown.

- [ ] **Step 7: Commit**

```bash
git add cli/server.py cli/launchd/com.voicekeep.analyzer.plist.template cli/setup.sh
git commit -m "feat(cli): HTTP server replaces file watcher; bearer-auth /analyze"
```

---

### C4: iOS — `AnalysisExport` becomes pure JSON helper, add `AnalysisService` (HTTP)

**Files:**
- Modify: `Echograph/Echograph/Core/Models/AnalysisExport.swift` (drop iCloud paths, keep schema)
- Create: `Echograph/Echograph/Core/Stores/AnalysisService.swift`

- [ ] **Step 1: Refactor `AnalysisExport.swift`**

Strip everything iCloud-related. Keep only the `Payload` / `TranscriptPayload` / `SegmentPayload` Codable structs and a static `makeJSON(_:) -> Data` helper.

- [ ] **Step 2: Write `AnalysisService.swift`**

```swift
import Foundation

@MainActor
@Observable
final class AnalysisService {
    @ObservationIgnored @AppStorage("Voicekeep.analyzerURL") private var urlString = ""
    @ObservationIgnored @AppStorage("Voicekeep.analyzerToken") private var token = ""

    enum ServiceError: LocalizedError {
        case notConfigured
        case noTranscript
        case http(Int, String)
        case network(String)

        var errorDescription: String? { ... }
    }

    func analyze(_ recording: Recording) async throws -> String {
        guard !urlString.isEmpty, !token.isEmpty else { throw ServiceError.notConfigured }
        guard recording.transcript != nil else { throw ServiceError.noTranscript }
        guard let base = URL(string: urlString) else { throw ServiceError.notConfigured }

        let body = try AnalysisExport.makeJSON(recording)

        var req = URLRequest(url: base.appendingPathComponent("analyze"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = body
        req.timeoutInterval = 180

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw ServiceError.network(error.localizedDescription)
        }
        guard let http = resp as? HTTPURLResponse else {
            throw ServiceError.network("unexpected response")
        }
        if http.statusCode != 200 {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.http(http.statusCode, detail)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func healthCheck() async -> Bool {
        guard !urlString.isEmpty, let base = URL(string: urlString) else { return false }
        var req = URLRequest(url: base.appendingPathComponent("health"))
        req.timeoutInterval = 5
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }
}
```

`@AppStorage` requires `import SwiftUI` — but inside a non-View class needs `@ObservationIgnored` plus `@AppStorage` direct usage works.

(Implementation detail: `@AppStorage` is a SwiftUI property wrapper that doesn't quite work outside Views. Will likely use raw `UserDefaults.standard` in actual implementation.)

- [ ] **Step 3: Inject AnalysisService in EchographApp**

```swift
@State private var analysisService = AnalysisService()
...
.environment(analysisService)
```

- [ ] **Step 4: Commit**

```bash
git add Echograph/Echograph/Core/Models/AnalysisExport.swift \
        Echograph/Echograph/Core/Stores/AnalysisService.swift \
        Echograph/Echograph/App/EchographApp.swift
git commit -m "feat(ios): AnalysisService — HTTP client with bearer auth"
```

---

### C5: Settings UI for URL + token

**Files:**
- Modify: `Echograph/Echograph/UI/SettingsView.swift`

- [ ] **Step 1: Add a section**

```swift
Section("AI Analyzer") {
    TextField("Server URL", text: $analyzerURL)
        .textInputAutocapitalization(.never)
        .keyboardType(.URL)
        .autocorrectionDisabled()
    SecureField("Bearer token", text: $analyzerToken)
    HStack {
        Text("Status")
        Spacer()
        Text(connectionStatus)
            .foregroundStyle(connectionOK ? .green : .secondary)
    }
    Button("Test connection") {
        Task { await testConnection() }
    }
}
```

With `@AppStorage` bindings.

- [ ] **Step 2: Add localized strings**

"AI Analyzer", "Server URL", "Bearer token", "Test connection", "Connected", "Not connected".

- [ ] **Step 3: Commit**

---

### C6: Update RecordingDetailView — call AnalysisService

**Files:**
- Modify: `Echograph/Echograph/UI/RecordingDetailView.swift`

- [ ] **Step 1: Change Environment from `AnalysisStore` to `AnalysisService`**

- [ ] **Step 2: Rewrite `sendForAnalysis`**

```swift
private func sendForAnalysis(_ recording: Recording) async {
    isAnalyzing = true
    defer { isAnalyzing = false }
    do {
        let md = try await analysisService.analyze(recording)
        var updated = recording
        updated.analysis = md
        store.update(updated)
    } catch {
        analysisError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
```

- [ ] **Step 3: Commit**

---

### C7: Update `AnalysisSection` to read from Recording directly

**Files:**
- Modify: `Echograph/Echograph/UI/AnalysisSection.swift`

- [ ] **Step 1: Replace store lookup with direct prop**

```swift
struct AnalysisSection: View {
    let analysis: String?

    var body: some View {
        if let analysis, !analysis.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ...
                Markdown(analysis)
                ...
            }
        }
    }
}
```

Update call site in `RecordingDetailView`:
```swift
AnalysisSection(analysis: recording.analysis)
```

- [ ] **Step 2: Commit**

---

### C8: Update `cli/README.md`

Document the new flow:
- Tailscale install on iPhone
- `tailscale ip -4` for the URL
- token from `~/.voicekeep-token`
- copy URL+token to iPhone Settings → AI Analyzer
- daily use unchanged

---

### C9: Push + manual e2e

`git push`, then on Xcode-Mac:
- pull, xcodegen, open, build
- in Settings paste URL `http://<tailscale-ip>:8765` and the token
- tap "Test connection" → "Connected"
- open recording → AI-анализ → wait ~30 s → AnalysisSection appears with rendered markdown
