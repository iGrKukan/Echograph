import Foundation

/// Compile-time gated hooks for the UITests target. They only fire when the
/// app is launched with the matching `-uitest_*` launch argument; in normal
/// user runs none of this code executes.
enum UITestHooks {
    static var forcePaywall: Bool {
        CommandLine.arguments.contains("-uitest_force_paywall")
    }

    static func applyIfNeeded() {
        let args = CommandLine.arguments
        guard args.contains(where: { $0.hasPrefix("-uitest_") }) else { return }

        // Дисклеймер согласия перекрывает любой экран при первом запуске, поэтому
        // в UI-тестах и при съёмке скриншотов сразу помечаем его показанным —
        // иначе все снимки получаются одинаковыми, с приветственным экраном.
        UserDefaults.standard.set(true, forKey: "Echograph.didShowConsentDisclaimer")

        if args.contains("-uitest_seed_recordings") {
            seedMockRecordings()
        }
    }

    private static func seedMockRecordings() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsDir = documents.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

        // Generate a tiny silent .m4a placeholder so AudioPlayer doesn't crash.
        let placeholderURL = recordingsDir.appendingPathComponent("uitest-silent.m4a")
        if !FileManager.default.fileExists(atPath: placeholderURL.path),
           let url = Bundle.main.url(forResource: nil, withExtension: nil) {
            // No-op; in practice the AVAudioPlayer simply errors out on missing file
            // and the UI degrades gracefully — but we still want a valid filename.
            _ = url
        }

        let json = #"""
        [
          {
            "createdAt": "2026-05-10T10:30:00Z",
            "duration": 1843.2,
            "filename": "uitest-silent.m4a",
            "id": "AAAAAAAA-1111-1111-1111-111111111111",
            "speakerCount": 2,
            "tags": ["interview", "research", "ai-ethics"],
            "summary": "Dr. Vasquez explains how on-device transcription protects patient privacy and why the medical community is shifting away from cloud-only solutions. Key concerns: HIPAA compliance, data retention, and recent class-action settlements.\n\nAction items:\n- Draft privacy policy section on Whisper local processing\n- Schedule follow-up with hospital IT\n- Share Bryan Litz's research on speaker diarization",
            "title": "Interview with Dr. Vasquez",
            "transcript": {
              "language": "en",
              "modelUsed": "whisperLargeV3Turbo",
              "segments": [
                {
                  "endTime": 8.4,
                  "id": "S1AAAAAA-0001-0001-0001-000000000001",
                  "isHighlighted": false,
                  "speaker": {"id": "SPK00001-1111-1111-1111-111111111111", "label": "Interviewer"},
                  "startTime": 0,
                  "text": "So tell me, why did you switch your entire practice to on-device transcription?",
                  "words": []
                },
                {
                  "endTime": 24.1,
                  "id": "S1AAAAAA-0002-0002-0002-000000000002",
                  "isHighlighted": true,
                  "speaker": {"id": "SPK00002-2222-2222-2222-222222222222", "label": "Dr. Vasquez"},
                  "startTime": 8.4,
                  "text": "Honestly? After the Otter class action last year I just couldn't justify uploading patient consultations to a third-party server, no matter how many SOC 2 badges they had.",
                  "words": []
                },
                {
                  "endTime": 38.2,
                  "id": "S1AAAAAA-0003-0003-0003-000000000003",
                  "isHighlighted": true,
                  "speaker": {"id": "SPK00002-2222-2222-2222-222222222222", "label": "Dr. Vasquez"},
                  "startTime": 24.5,
                  "text": "Whisper running locally on my iPhone gives me 95 percent accuracy and the audio literally never leaves the device. That changes the conversation with hospital legal completely.",
                  "words": []
                },
                {
                  "endTime": 47.8,
                  "id": "S1AAAAAA-0004-0004-0004-000000000004",
                  "isHighlighted": false,
                  "speaker": {"id": "SPK00001-1111-1111-1111-111111111111", "label": "Interviewer"},
                  "startTime": 39.0,
                  "text": "And the AI summary feature — Apple Intelligence does it all on-device too?",
                  "words": []
                }
              ]
            }
          },
          {
            "createdAt": "2026-05-10T07:30:00Z",
            "duration": 3217.5,
            "filename": "uitest-silent.m4a",
            "id": "BBBBBBBB-2222-2222-2222-222222222222",
            "speakerCount": 1,
            "tags": ["лекция", "баллистика"],
            "title": "Лекция: Введение в баллистику"
          },
          {
            "createdAt": "2026-05-10T04:30:00Z",
            "duration": 612.1,
            "filename": "uitest-silent.m4a",
            "id": "CCCCCCCC-3333-3333-3333-333333333333",
            "speakerCount": 4,
            "tags": ["standup", "mobile"],
            "title": "Standup · Mobile team"
          },
          {
            "createdAt": "2026-05-09T14:00:00Z",
            "duration": 47.3,
            "filename": "uitest-silent.m4a",
            "id": "DDDDDDDD-4444-4444-4444-444444444444",
            "speakerCount": 1,
            "tags": [],
            "title": "Voice memo · Saturday morning"
          },
          {
            "createdAt": "2026-05-08T18:00:00Z",
            "duration": 2702.0,
            "filename": "uitest-silent.m4a",
            "id": "EEEEEEEE-5555-5555-5555-555555555555",
            "speakerCount": 2,
            "tags": ["podcast", "privacy", "encryption"],
            "title": "Podcast pilot · The Privacy Tax"
          }
        ]
        """#

        let metadataURL = documents.appendingPathComponent("recordings.json")
        try? json.data(using: .utf8)?.write(to: metadataURL)
    }
}
