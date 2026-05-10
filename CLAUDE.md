# Voicekeep (codename: Echograph) — context for Claude

iOS app that records voice and transcribes everything **on-device** using
OpenAI Whisper (via WhisperKit) + Apple Speech. The App Store listing is
**Voicekeep** (the original "Echograph" name was already taken at
submission time); the bundle id and the GitHub repo still use `echograph`.

## Stack

- Swift 6, SwiftUI, **iOS 17 minimum** (Apple Intelligence features need iOS 26)
- SPM: WhisperKit 0.10+ (pulls swift-transformers, swift-crypto, etc.)
- AVAudioRecorder for capture, AVAudioPlayer for playback
- StoreKit 2 for IAP (Pro lifetime $19.99, Pro+ $4.99/mo, $29.99/yr)
- ActivityKit for Live Activity (disabled on simulator — see `LiveActivityManager`)
- WatchConnectivity for the Apple Watch companion target
- App Intents (`StartRecordingIntent`) for Action Button
- Apple Foundation Models for AI Summary / Q&A / Auto-tagging (Pro+)

## Identifiers

| Thing | Value |
|---|---|
| Bundle ID | `by.timberbid.echograph` |
| Apple Developer Team | `U5BAN54DL2` (NOT `ZVYKY9TF2X` — that team has no App Store role) |
| App Store Connect App ID | `6768048620` |
| GitHub repo | https://github.com/iGrKukan/Echograph |
| Marketing site | https://igrkukan.github.io/Echograph/ (auto-deployed from `docs/`) |
| App Store name | Voicekeep |
| In-bundle display name | Voicekeep (CFBundleDisplayName) |

In-app purchase IDs (defined in `Echograph/Store/ProductID.swift`):
- `by.timberbid.echograph.pro.lifetime` — non-consumable, $19.99
- `by.timberbid.echograph.proplus.monthly` — subscription, $4.99/mo
- `by.timberbid.echograph.proplus.yearly` — subscription, $29.99/yr (7-day trial)

## First-time setup on a new Mac

```bash
# Prereqs
brew install xcodegen
# Xcode 16+ from the App Store (current dev was on 26.4)

# Clone & generate
git clone https://github.com/iGrKukan/Echograph.git ~/Echograph
cd ~/Echograph
xcodegen generate
open Echograph.xcodeproj
```

The `.xcodeproj` is generated from `project.yml` and **must not be edited
by hand** — re-run `xcodegen generate` after touching the YAML.

Sign in to Xcode with the Apple ID that's a member of team `U5BAN54DL2`.
Automatic signing will create a development provisioning profile on the
first build.

### Secrets you'll need to bring over

These are **gitignored** — they have to be transferred manually from the
old Mac (or recreated):

```
fastlane/secrets/AuthKey_798ZTD68WF.p8     # App Store Connect API key
private_keys/AuthKey_798ZTD68WF.p8          # same file, used by altool
```

If the `.p8` was lost, generate a new one at
https://appstoreconnect.apple.com/access/integrations/api and update
`KEY_ID` / `ISSUER_ID` in `fastlane/asc_token.py`.

You'll also need a Python 3 venv for the ASC scripts:

```bash
python3 -m venv fastlane/.venv
fastlane/.venv/bin/pip install pyjwt cryptography requests
```

## Project layout

```
Echograph/                   iOS app target
├── App/                     entry point + UITestHooks
├── Audio/                   AVAudioRecorder, AVAudioPlayer, mic permission, file import
├── AppIntents/              StartRecordingIntent (Action Button)
├── Core/
│   ├── Models/              Recording, Transcript, TranscriptionLanguage
│   └── Stores/              RecordingStore (JSON in Documents/)
├── Export/                  TranscriptExporter — TXT/MD/SRT/VTT/PDF
├── Integrations/            CalendarService, RemindersService
├── LiveActivity/            LiveActivityManager (disabled on simulator)
├── Resources/               Assets.xcassets, Localizable.xcstrings, PrivacyInfo.xcprivacy
├── Store/                   StoreKit 2 products + paywall
├── Summary/                 SummaryService — Foundation Models AI
├── Sync/                    WatchConnectivityCoordinator
├── Transcription/           Apple Speech + WhisperKit engines
└── UI/                      All SwiftUI screens

EchographLiveActivity/       Widget extension (build target — embed disabled
                             by default because iOS Simulator can't register
                             the widget; re-enable in project.yml when
                             building for a real device)

EchographWatch/              watchOS standalone target (embed disabled by
                             default because watchOS Simulator runtime
                             isn't installed)

EchographUITests/            XCUITest target — generates App Store screenshots
                             via launch-arg seeded mock data

Shared/                      Shared between iOS app and Live Activity widget
                             (RecordingActivityAttributes)

StoreKitTesting/             .storekit config for simulator IAP testing
                             (NOT in the production bundle, referenced
                              only from the scheme)

docs/                        GitHub Pages landing page (index/privacy/support)
                             auto-deployed via .github/workflows/pages.yml

marketing/                   App Store metadata (en/ru/de/fr/ja),
                             screenshots/, screenshots/app-store/ (the
                             1320×2868 marketing-overlay versions),
                             privacy-policy.md, README.md (submission guide)

fastlane/
├── asc_token.py             JWT for App Store Connect API
├── upload_metadata.py       Push localized version metadata
├── iap_localizations.py     Push 3 IAP × 5 locales of names/descriptions
├── upload_screenshots.py    Staged-upload protocol for app screenshots
├── secrets/                 .p8 + cached IDs (gitignored)
└── .venv/                   Python venv (gitignored)
```

## Build / run / test

```bash
# Generate xcodeproj after any project.yml edit
xcodegen generate

# Build for simulator
xcodebuild -project Echograph.xcodeproj -scheme Echograph \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build

# Run UI snapshot tests (generates marketing screenshots)
xcodebuild test -project Echograph.xcodeproj -scheme Echograph \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:EchographUITests/SnapshotTests
# Screenshots end up at /tmp/echograph-snapshots/*.png

# Production archive — requires Apple Developer signing
xcodebuild archive -project Echograph.xcodeproj -scheme Echograph \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/Echograph.xcarchive \
  -allowProvisioningUpdates \
  -authenticationKeyID 798ZTD68WF \
  -authenticationKeyIssuerID 69a6de8e-0e6d-47e3-e053-5b8c7c11a4d1 \
  -authenticationKeyPath fastlane/secrets/AuthKey_798ZTD68WF.p8

# Export .ipa
xcodebuild -exportArchive -archivePath build/Echograph.xcarchive \
  -exportPath build/export -exportOptionsPlist build/ExportOptions.plist \
  -allowProvisioningUpdates \
  -authenticationKeyID 798ZTD68WF \
  -authenticationKeyIssuerID 69a6de8e-0e6d-47e3-e053-5b8c7c11a4d1 \
  -authenticationKeyPath fastlane/secrets/AuthKey_798ZTD68WF.p8

# Upload to TestFlight
xcrun altool --upload-app --type ios -f build/export/Echograph.ipa \
  --apiKey 798ZTD68WF \
  --apiIssuer 69a6de8e-0e6d-47e3-e053-5b8c7c11a4d1
```

## Gotchas / things that bit us

1. **`Echograph` name is taken in App Store** — that's why the listing
   is `Voicekeep`. Don't try to rename back.

2. **Live Activity widget** breaks in simulator with "Failed to get
   descriptors for extensionBundleID". The fix in `project.yml` is
   commenting out `- target: EchographLiveActivity` from the iOS app's
   `dependencies`. Re-enable when building for real device.

3. **watchOS target** doesn't build in CI on machines without the
   watchOS Simulator runtime installed. It's also commented out of the
   iOS app's deps. Install runtime via Xcode → Settings → Components
   then re-enable.

4. **Whisper expects ISO-639-1 codes** (`ru`, `en`, `de`), not BCP-47
   (`ru-RU`). `WhisperKitTranscriber` strips region before passing to
   `DecodingOptions`. Without this Whisper emits only special tokens
   like `<|startoftranscript|><|endoftext|>` and looks broken.

5. **Apple Speech on simulator** has no on-device model — we set
   `requiresOnDeviceRecognition = false` for `targetEnvironment(simulator)`
   only. On device it stays strictly on-device.

6. **DEBUG override for Pro/Pro+** lives in `PurchaseManager`. In Debug
   builds `hasPro = true` always (unless `-uitest_force_paywall` arg is
   set). Release builds use real StoreKit transactions.

7. **PrivacyInfo.xcprivacy** declares zero data collection. WhisperKit
   makes one network call to download model weights from Hugging Face
   on first use — this is the only outbound network the app makes
   (along with Apple Translation if user invokes it).

8. **StoreKit Configuration** (`StoreKitTesting/Echograph.storekit`)
   is referenced from the scheme only, NOT bundled with the app.
   Apple flags shipping `.storekit` files in Release.

9. **Apple Foundation Models** (Pro+ AI features) only run on iPhone
   15 Pro+ with iOS 26 + Apple Intelligence enabled. Simulator and
   older devices show "Apple Intelligence required" instead of the AI
   buttons. `SummaryService.isAvailable` is the gate.

10. **Subscription pricing via API** — Apple's ASC API does NOT let
    you set subscription prices reliably (we got 409 ENTITY_ERROR).
    Pricing for `proplus.monthly` ($4.99) and `proplus.yearly` ($29.99)
    must be set in the App Store Connect web UI by hand. `pro.lifetime`
    pricing was set successfully via `inAppPurchasePriceSchedules`.

11. **App creation via API** is not supported by Apple. Initial app
    creation has to happen in App Store Connect web. After that
    everything (metadata, IAP, screenshots, build upload) can be
    automated through the scripts in `fastlane/`.

## Status as of last commit

Everything pushed to GitHub `main`:

- iOS app with full feature set: record, on-device transcription
  (Apple Speech + 4 Whisper models), word-level timestamps with
  tap-to-seek, transcript editing, highlights, manual speaker labels,
  custom vocabulary, AI summary / Q&A / auto-tags, tags, search,
  exports (TXT/MD/PDF/SRT/VTT), reminders/calendar/translate hooks,
  consent disclaimer, audio file import.
- App Store Connect product `Voicekeep` (id 6768048620) created with
  metadata in 5 locales, 3 IAP products, 3 marketing screenshots in
  en-US.
- Build 1.0.0 (1) uploaded to TestFlight.
- GitHub Pages landing/privacy/support live with auto-deploy on `docs/`
  changes.

What's still left (web UI, no code):
- Subscription prices for `proplus.monthly` / `proplus.yearly`
- App Privacy questionnaire (Data Not Collected everywhere)
- Banking & tax agreements (if not done already)
- Attach build 1.0.0(1) to version 1.0 once Apple finishes processing
- More screenshots in non-en locales (drag&drop)
- Submit for Review

## Next steps after pulling on a new Mac

1. Open the project, hit Cmd+R against `iPhone 17 Pro` simulator —
   the consent disclaimer should appear on first launch.
2. Test recording → transcribing with Apple Speech (works in simulator).
3. Whisper Tiny works in simulator (slow on CPU, ~10× realtime); larger
   Whisper models need a real iPhone for sane speed.
4. To test paywall flow, append `-uitest_force_paywall` to the scheme's
   launch arguments — DEBUG bypass turns off and tapping a Whisper
   model in the Transcribe menu opens `PaywallView`.
5. Live Activity, Action Button, and watchOS app only work on a real
   iPhone. Re-enable the relevant `dependencies` lines in `project.yml`,
   regenerate, archive, and run on device.

## Common requests and where they live

- "Add a new language to the UI" → edit `Echograph/Resources/Localizable.xcstrings`
- "Add a new transcript export format" → `Echograph/Export/TranscriptExporter.swift`
- "Tweak the paywall copy" → `Echograph/UI/PaywallView.swift`
- "Change pricing" → `fastlane/asc_token.py` + `Echograph/Resources/Echograph.storekit`
  in `StoreKitTesting/` (for simulator) + App Store Connect web (production)
- "Add a new Apple Intelligence feature" → `Echograph/Summary/SummaryService.swift`
  (already supports summary, ask, auto-tags)
- "Modify a UI test screenshot" → edit `EchographUITests/SnapshotTests.swift` +
  update mock data in `Echograph/Core/UITestHooks.swift`
- "Update marketing site" → edit `docs/index.html` (or privacy/support); push
  triggers GitHub Actions auto-deploy.

## Workflow conventions

- Commit messages in Russian or English, follow the existing style in
  `git log` (concise summary line + detailed body for non-trivial work).
- Keep `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`
  trailer when commits are AI-assisted.
- Don't commit `xcodeproj` changes — regenerate via xcodegen.
- Re-run `xcodebuild test ... SnapshotTests` whenever a UI change might
  affect the App Store screenshots.
