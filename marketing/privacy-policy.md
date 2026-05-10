# Echograph Privacy Policy

_Last updated: 2026-05-10_

## Summary

Echograph processes everything on your iPhone. We do not collect, store, or transmit any of the following:

- Your voice recordings
- Your transcripts
- Your summaries
- Your tags or notes
- Any analytics or usage telemetry
- Any device identifiers

## What stays local

All recordings, transcripts, summaries, custom vocabularies, and tags are stored on your device, in the app's sandboxed Documents directory. They are never uploaded to any server we control.

When you transcribe audio with Apple Speech or Whisper, processing happens on the iPhone's Neural Engine. The audio data does not leave your device.

When you generate an AI summary or ask the AI a question, Apple's Foundation Models run on-device on iPhone 15 Pro and newer with iOS 26 and Apple Intelligence enabled. Your transcript text is processed locally and is not sent to OpenAI, Anthropic, Google, or any third party.

## Network use

The app makes network requests in two specific cases:

1. **Whisper model download.** The first time you select a Whisper model (Tiny / Base / Small / Large v3 Turbo), the app downloads the model weights from the public Hugging Face repository `argmaxinc/whisperkit-coreml`. This is a one-time download per model, performed by the open-source WhisperKit framework.

2. **Apple Translation framework.** When you tap "Translate Transcript", iOS invokes Apple's Translation framework. Translation can run on-device for downloaded language packs; otherwise it routes through Apple's translation servers per Apple's published privacy policy.

The app does not make any other network requests.

## Permissions

Echograph requests the following iOS permissions, only for the stated purpose:

- **Microphone**: to capture audio when you tap Record. Audio is written to local storage and never uploaded.
- **Speech Recognition**: when you use Apple Speech as the transcription engine. With `requiresOnDeviceRecognition = true`, Apple processes audio locally.
- **Reminders** (optional): only when you tap "Add to Reminders" in a transcript context menu. The app creates a single reminder with the segment text.
- **Calendar** (optional): only when you tap "Add to Calendar". The app creates a single event tied to the recording.

You can revoke any of these in iOS Settings → Privacy & Security at any time. The app continues to work; only the related feature becomes unavailable.

## In-app purchases

Echograph offers in-app purchases (Pro lifetime, Pro+ subscription) processed by Apple via StoreKit. Apple handles all payment information per Apple's privacy practices. Echograph does not see your payment details.

## iCloud (optional, Pro+)

If you opt in to iCloud sync, your recordings and transcripts are stored in your private iCloud container, encrypted in transit and at rest by Apple. Echograph cannot access this data on Apple's servers; only your devices signed in with the same Apple ID can.

## Data retention

Data lives on your device until you delete it. There is no remote copy unless you opt in to iCloud sync.

## Your rights

- Access: open the Files app or Echograph itself; everything is there.
- Deletion: delete recordings inside the app or uninstall the app.
- Portability: export to PDF, Word, Markdown, TXT, SRT, or VTT at any time.

## Children

Echograph is suitable for ages 4+. We do not knowingly collect data from anyone, including children.

## Contact

Privacy questions: privacy@echograph.app
General support: support@echograph.app

## Changes

If this policy changes materially, we'll publish the new version at echograph.app/privacy with an updated date and bump the in-app About section.
