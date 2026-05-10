# Phase B: In-App Analysis Display — Plan

> Extension of [Phase A spec](../specs/2026-05-10-cli-conversation-analysis-design.md) and [Phase A plan](2026-05-10-cli-conversation-analysis.md). The non-goal "Writing analysis back into the iOS app" from Phase A is **lifted** here.

**Goal:** Add iCloud Container so iOS app writes JSON directly (no Share Sheet) and renders the resulting `.analysis.md` inline in `RecordingDetailView` via `NSMetadataQuery`.

**Architecture change:** Move from user-visible `iCloud Drive/Voicekeep/` to app-private `iCloud.by.timberbid.echograph/Documents/`. iOS app reads & writes its own container directly. Mac watcher path updates accordingly.

**Tech stack additions:**
- iCloud entitlement (`com.apple.developer.icloud-container-identifiers`, `com.apple.developer.icloud-services = CloudDocuments`).
- `MarkdownUI` SwiftPM package (https://github.com/gonzalezreal/swift-markdown-ui) — renders the four-section Markdown with tables and lists in SwiftUI.
- `NSMetadataQuery` for ubiquity-folder observation.

---

## File structure

**New files:**
- `Echograph/Echograph.entitlements` — iCloud container declaration.
- `Echograph/Echograph/Core/Stores/AnalysisStore.swift` — `@Observable`, indexed by `recording.id`.
- `Echograph/Echograph/UI/AnalysisSection.swift` — SwiftUI view rendering Markdown via `MarkdownUI`.

**Modified files:**
- `Echograph/project.yml` — entitlements path, MarkdownUI package, container ID.
- `Echograph/Echograph/Core/Models/AnalysisExport.swift` — drop Transferable, add `static func send(_:) async throws -> URL` writing directly to ubiquity container.
- `Echograph/Echograph/UI/RecordingDetailView.swift` — replace `ShareLink` with a Button that calls `AnalysisExport.send`; embed `AnalysisSection`.
- `Echograph/Echograph/App/EchographApp.swift` — inject shared `AnalysisStore`.
- `Echograph/Echograph/Resources/Localizable.xcstrings` — add status strings ("Sent for analysis", "Awaiting analysis", "iCloud not available").
- `cli/setup.sh` — point launchd `WatchPaths` to new container path.
- `cli/README.md` — document the path change.
- `docs/superpowers/specs/2026-05-10-cli-conversation-analysis-design.md` — strike non-goal #5, add Phase B section.

**Path migration on Mac:**
- Old: `~/Library/Mobile Documents/com~apple~CloudDocs/Voicekeep/{inbox,processed,failed}`
- New: `~/Library/Mobile Documents/iCloud~by~timberbid~echograph/Documents/{inbox,processed,failed}`
- Old folder is left alone (not migrated automatically — it's a personal prototype, no real data yet).

**Filename convention change:**
- Old: `<yyyy-MM-dd-HHmmss>-<safe-title>.voicekeep.json`
- New: `<recording.id.uuidString>.voicekeep.json` → `<recording.id.uuidString>.analysis.md`. iOS finds the result by UUID match — no filename guessing.

---

## Phase B tasks

### Task B1: iCloud entitlement + MarkdownUI dep in project.yml

**Files:**
- Create: `Echograph/Echograph.entitlements`
- Modify: `Echograph/project.yml`

- [ ] **Step 1: Write entitlements file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.by.timberbid.echograph</string>
    </array>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudDocuments</string>
    </array>
    <key>com.apple.developer.ubiquity-container-identifiers</key>
    <array>
        <string>iCloud.by.timberbid.echograph</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 2: Update Info.plist's `NSUbiquitousContainers` for Files-app visibility**

Open `Echograph/Echograph/Info.plist` and add (next to other top-level keys):

```xml
<key>NSUbiquitousContainers</key>
<dict>
    <key>iCloud.by.timberbid.echograph</key>
    <dict>
        <key>NSUbiquitousContainerIsDocumentScopePublic</key>
        <true/>
        <key>NSUbiquitousContainerName</key>
        <string>Voicekeep</string>
        <key>NSUbiquitousContainerSupportedFolderLevels</key>
        <string>Any</string>
    </dict>
</dict>
```

This makes the container appear as a **Voicekeep** folder under iCloud Drive in Files app.

- [ ] **Step 3: Update `project.yml` — add entitlements + MarkdownUI**

In the `packages:` section, add (next to WhisperKit):

```yaml
  MarkdownUI:
    url: https://github.com/gonzalezreal/swift-markdown-ui.git
    from: 2.4.0
```

In the `Echograph` target's `settings.base`, add:

```yaml
    CODE_SIGN_ENTITLEMENTS: Echograph/Echograph.entitlements
```

In the `Echograph` target's `dependencies`, add:

```yaml
      - package: MarkdownUI
        product: MarkdownUI
```

- [ ] **Step 4: Regenerate xcodeproj**

```bash
cd ~/Echograph && xcodegen generate
```

- [ ] **Step 5: Verify entitlements wired**

```bash
grep -c "Echograph.entitlements\|MarkdownUI" Echograph.xcodeproj/project.pbxproj
```
Expected: ≥3 (entitlements path × 2 configs + MarkdownUI references).

- [ ] **Step 6: Commit**

```bash
git add Echograph/Echograph.entitlements Echograph/Echograph/Info.plist project.yml Echograph.xcodeproj/project.pbxproj
git commit -m "feat(ios): iCloud container + MarkdownUI dep for in-app analysis display"
```

---

### Task B2: Refactor `AnalysisExport` — direct ubiquity write

**Files:**
- Modify: `Echograph/Echograph/Core/Models/AnalysisExport.swift`

- [ ] **Step 1: Replace file contents**

```swift
import Foundation

/// Writes a `Recording` as JSON into the app's iCloud Drive inbox so the
/// Mac-side `cli/voicekeep_analyze.sh` watcher can pick it up. The result
/// `<recording.id>.analysis.md` lands in the same container's `processed/`
/// folder and is observed by `AnalysisStore`.
enum AnalysisExport {
    static let containerIdentifier = "iCloud.by.timberbid.echograph"

    enum ExportError: LocalizedError {
        case iCloudUnavailable
        case noTranscript
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .iCloudUnavailable:
                return String(localized: "iCloud Drive is not available. Sign into iCloud and enable Voicekeep in Settings → Apple ID → iCloud Drive.")
            case .noTranscript:
                return String(localized: "Recording has no transcript yet. Transcribe it first.")
            case .writeFailed(let detail):
                return String(localized: "Could not save the export: \(detail)")
            }
        }
    }

    /// Returns the URL of the JSON file in `<container>/Documents/inbox/`.
    @discardableResult
    static func send(_ recording: Recording) async throws -> URL {
        guard recording.transcript != nil else {
            throw ExportError.noTranscript
        }
        let inbox = try inboxURL()
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        let payload = Payload(recording: recording)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data: Data
        do {
            data = try encoder.encode(payload)
        } catch {
            throw ExportError.writeFailed(String(describing: error))
        }

        let url = inbox.appendingPathComponent("\(recording.id.uuidString).voicekeep.json")
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw ExportError.writeFailed(String(describing: error))
        }
        return url
    }

    static func inboxURL() throws -> URL {
        try documentsURL().appendingPathComponent("inbox", isDirectory: true)
    }

    static func processedURL() throws -> URL {
        try documentsURL().appendingPathComponent("processed", isDirectory: true)
    }

    static func documentsURL() throws -> URL {
        guard let root = FileManager.default
            .url(forUbiquityContainerIdentifier: containerIdentifier) else {
            throw ExportError.iCloudUnavailable
        }
        return root.appendingPathComponent("Documents", isDirectory: true)
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
            self.highlighted = s.isHighlighted ? true : nil
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Echograph/Echograph/Core/Models/AnalysisExport.swift
git commit -m "feat(ios): AnalysisExport.send writes JSON to ubiquity container/inbox"
```

---

### Task B3: `AnalysisStore` — NSMetadataQuery-backed observable

**Files:**
- Create: `Echograph/Echograph/Core/Stores/AnalysisStore.swift`

- [ ] **Step 1: Write `AnalysisStore.swift`**

```swift
import Foundation
import Observation

/// Observes `<container>/Documents/processed/*.analysis.md` and exposes a
/// `recording.id → markdown` map. Updates as iCloud syncs new analyses
/// from the Mac.
@MainActor
@Observable
final class AnalysisStore {
    private(set) var analyses: [UUID: String] = [:]
    private(set) var lastError: String?

    private let query = NSMetadataQuery()
    private var observer: NSObjectProtocol?

    init() {
        startObserving()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        query.stop()
    }

    func markdown(for recordingId: UUID) -> String? {
        analyses[recordingId]
    }

    private func startObserving() {
        guard FileManager.default
            .url(forUbiquityContainerIdentifier: AnalysisExport.containerIdentifier) != nil else {
            lastError = "iCloud unavailable"
            return
        }

        query.searchScopes = [NSMetadataQueryUbiquitousDataScope]
        query.predicate = NSPredicate(format: "%K LIKE '*.analysis.md'", NSMetadataItemFSNameKey)
        query.notificationBatchingInterval = 0.5

        let center = NotificationCenter.default
        observer = center.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        center.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        query.start()
    }

    private func refresh() {
        query.disableUpdates()
        defer { query.enableUpdates() }

        var fresh: [UUID: String] = [:]
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            // We only care about files inside our `Documents/processed/` folder.
            guard url.pathComponents.contains("processed") else { continue }
            // Filename pattern: <UUID>.analysis.md
            let stem = url.deletingPathExtension().deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: stem) else { continue }
            // Trigger download if iCloud hasn't materialised the file yet.
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                fresh[id] = text
            }
        }
        analyses = fresh
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Echograph/Echograph/Core/Stores/AnalysisStore.swift
git commit -m "feat(ios): AnalysisStore — NSMetadataQuery observer for processed analyses"
```

---

### Task B4: Inject `AnalysisStore` into `EchographApp`

**Files:**
- Modify: `Echograph/Echograph/App/EchographApp.swift`

- [ ] **Step 1: Read current state**

```bash
grep -n "RecordingStore\|@State\|@Environment" Echograph/Echograph/App/EchographApp.swift | head -10
```

- [ ] **Step 2: Add `AnalysisStore` next to `RecordingStore`**

In `EchographApp` body — wherever `RecordingStore` is instantiated and passed via `.environment()` — add a sibling `AnalysisStore`:

```swift
@State private var analysisStore = AnalysisStore()
```

And in the view tree:

```swift
.environment(analysisStore)
```

- [ ] **Step 3: Commit**

```bash
git add Echograph/Echograph/App/EchographApp.swift
git commit -m "feat(ios): inject shared AnalysisStore into environment"
```

---

### Task B5: `AnalysisSection` view (Markdown rendering)

**Files:**
- Create: `Echograph/Echograph/UI/AnalysisSection.swift`

- [ ] **Step 1: Write the view**

```swift
import SwiftUI
import MarkdownUI

struct AnalysisSection: View {
    let recordingId: UUID

    @Environment(AnalysisStore.self) private var analysisStore

    var body: some View {
        if let markdown = analysisStore.markdown(for: recordingId) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.tint)
                    Text("AI Analysis")
                        .font(.headline)
                    Spacer()
                }
                Markdown(markdown)
                    .markdownTheme(.gitHub)
                    .textSelection(.enabled)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Echograph/Echograph/UI/AnalysisSection.swift
git commit -m "feat(ios): AnalysisSection — MarkdownUI render of AI analysis"
```

---

### Task B6: Wire button + section into `RecordingDetailView`

**Files:**
- Modify: `Echograph/Echograph/UI/RecordingDetailView.swift`
- Modify: `Echograph/Echograph/Resources/Localizable.xcstrings`

- [ ] **Step 1: Replace the `ShareLink` with a Button**

Find the ShareLink block we added in Task 12 (Phase A) — `ShareLink(item: AnalysisExport(...)`.

Replace it with:

```swift
Button {
    Task { await sendForAnalysis(recording) }
} label: {
    Label("Analyze with AI…", systemImage: "sparkles")
}
.disabled(recording.transcript == nil || isAnalyzing)
```

- [ ] **Step 2: Add the supporting state and method**

Inside `RecordingDetailView`'s `@State` declarations:

```swift
@State private var isAnalyzing = false
@State private var analysisError: String?
@Environment(AnalysisStore.self) private var analysisStore
```

Inside the view body, add an alert:

```swift
.alert("Analysis error", isPresented: Binding(
    get: { analysisError != nil },
    set: { if !$0 { analysisError = nil } }
)) {
    Button("OK", role: .cancel) {}
} message: {
    Text(analysisError ?? "")
}
```

Add the helper method to the view:

```swift
private func sendForAnalysis(_ recording: Recording) async {
    isAnalyzing = true
    defer { isAnalyzing = false }
    do {
        try await AnalysisExport.send(recording)
    } catch {
        analysisError = error.localizedDescription
    }
}
```

- [ ] **Step 3: Embed `AnalysisSection` below the existing transcript view**

Find where the transcript section is rendered in `RecordingDetailView`'s body (search for `TranscriptView` or transcript rendering). Add right below it:

```swift
if let recording {
    AnalysisSection(recordingId: recording.id)
        .padding(.horizontal)
}
```

- [ ] **Step 4: Add localized strings**

Add via jq (matching Task 12 pattern):

```bash
cd ~/Echograph && jq '.strings += {
  "Analysis error": {
    "localizations": {
      "de": {"stringUnit": {"state": "translated", "value": "Analysefehler"}},
      "en": {"stringUnit": {"state": "translated", "value": "Analysis error"}},
      "fr": {"stringUnit": {"state": "translated", "value": "Erreur d'\''analyse"}},
      "ja": {"stringUnit": {"state": "translated", "value": "分析エラー"}},
      "ru": {"stringUnit": {"state": "translated", "value": "Ошибка анализа"}}
    }
  }
}' Echograph/Resources/Localizable.xcstrings > /tmp/lstrings.json && mv /tmp/lstrings.json Echograph/Resources/Localizable.xcstrings
```

- [ ] **Step 5: Commit**

```bash
git add Echograph/Echograph/UI/RecordingDetailView.swift Echograph/Echograph/Resources/Localizable.xcstrings
git commit -m "feat(ios): replace ShareLink with direct send + render AnalysisSection"
```

---

### Task B7: Update Mac side — point to new container path

**Files:**
- Modify: `cli/setup.sh`
- Modify: `cli/README.md`

- [ ] **Step 1: Edit `cli/setup.sh` — change `ROOT`**

```bash
ROOT="$HOME/Library/Mobile Documents/iCloud~by~timberbid~echograph/Documents"
```

(Replace the existing `ROOT="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Voicekeep"` line.)

- [ ] **Step 2: Edit `cli/watch_inbox.sh` — same change for the default ROOT**

```bash
ROOT="${VOICEKEEP_ROOT:-$HOME/Library/Mobile Documents/iCloud~by~timberbid~echograph/Documents}"
```

- [ ] **Step 3: Update `cli/README.md` paths**

Find every `com~apple~CloudDocs/Voicekeep` and replace with `iCloud~by~timberbid~echograph/Documents`. Update the install-on-iPhone section to note that Files app shows the folder as **iCloud Drive → Voicekeep** (visible because of `NSUbiquitousContainers` in the iOS app's Info.plist) but the actual macOS path is the container path.

- [ ] **Step 4: Re-run installer on this Mac to migrate**

```bash
~/Echograph/cli/setup.sh
```

This re-renders the plist and reloads the agent on the new path. The old `com~apple~CloudDocs/Voicekeep` folder is left untouched (no real data there).

- [ ] **Step 5: Verify the new agent is loaded with the new path**

```bash
launchctl print "gui/$(id -u)/com.voicekeep.analyzer" | grep -A1 WatchPaths
```
Expected: shows `iCloud~by~timberbid~echograph/Documents/inbox`.

- [ ] **Step 6: Commit**

```bash
cd ~/Echograph && git add cli/setup.sh cli/watch_inbox.sh cli/README.md && git commit -m "feat(cli): migrate to iCloud container path for Phase B in-app display"
```

---

### Task B8: Strike the lifted non-goal in Phase A spec

**Files:**
- Modify: `docs/superpowers/specs/2026-05-10-cli-conversation-analysis-design.md`

- [ ] **Step 1: Edit non-goals section**

Find:
```
- Writing analysis back into the iOS app. Result lives only as Markdown on disk.
```

Replace with:
```
- ~~Writing analysis back into the iOS app.~~ — **Lifted in Phase B** (see plan `2026-05-10-cli-conversation-analysis-phase-b.md`).
```

- [ ] **Step 2: Commit**

```bash
cd ~/Echograph && git add docs/superpowers/specs/2026-05-10-cli-conversation-analysis-design.md && git commit -m "docs: lift Phase A non-goal — in-app display added in Phase B"
```

---

### Task B9: Push everything

- [ ] **Step 1: Push**

```bash
cd ~/Echograph && git push
```

---

### Task B10: Manual e2e test on Xcode Mac

Same shape as Phase A Task 13, but with the in-app display path now active.

- [ ] **Step 1: On Xcode Mac**

```bash
cd ~/Echograph && git pull && xcodegen generate && open Echograph.xcodeproj
```

In Xcode the first build will refresh the provisioning profile (auto-managed signing creates `iCloud.by.timberbid.echograph` container under team `U5BAN54DL2`). If a signing error pops up, click **Fix** in the Signing & Capabilities tab.

- [ ] **Step 2: Run on iPhone 17 Pro simulator (or real iPhone with iCloud signed in)**

iCloud Drive WILL work on the simulator if it's signed into your Apple ID. If not — use a real device.

- [ ] **Step 3: Smoke test**

1. Open a recording with a completed transcript.
2. Tap **AI-анализ…** — no Share Sheet now; expect a brief activity, then the button disables until the result arrives.
3. The `<recording.id>.voicekeep.json` is written to `iCloud Drive/Voicekeep/inbox/`.
4. iCloud syncs to the Mac watcher (~10–60 s). Watcher runs claude.
5. iCloud syncs the result back to the device.
6. The detail view gets a new section **AI Analysis** with the four-section Markdown rendered.

- [ ] **Step 4: Verify error paths**

Sign out of iCloud Drive → tap the button → expect the alert "iCloud Drive is not available...".
