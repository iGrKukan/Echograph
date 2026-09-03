import Foundation

/// Tracks how many free (non-subscriber) transcriptions have been used.
/// Transcription is free up to `freeTranscriptionLimit`, after which it
/// requires a Pro/Pro+ subscription — see `TranscriptionService.transcribe`.
///
/// Subscribers (`PurchaseManager.hasPro` / `hasProPlus`) bypass this
/// entirely: callers pass `unlimited: true` and the counter is never
/// touched for them.
enum FreeTranscriptionLimiter {
    /// Free transcriptions before a subscription is required. Single knob —
    /// change this to adjust the limit.
    static let freeTranscriptionLimit = 10

    private static let usedCountKey = "Voicekeep.freeTranscriptionsUsed"

    static var used: Int {
        UserDefaults.standard.integer(forKey: usedCountKey)
    }

    static var remaining: Int {
        max(0, freeTranscriptionLimit - used)
    }

    static var isExhausted: Bool {
        remaining <= 0
    }

    /// Call this only after a transcription has actually *succeeded* — not
    /// on failure or cancellation, and not at all for subscribers (see
    /// `TranscriptionService.transcribe`'s `unlimited` parameter, which
    /// guards every call site of this method).
    static func recordSuccessfulTranscription() {
        UserDefaults.standard.set(used + 1, forKey: usedCountKey)
    }

    /// UI-test-only: force the quota to its limit so the paywall-on-exhaustion
    /// path can be exercised without actually running 10 real transcriptions.
    /// Called only from `UITestHooks`, itself gated on a `-uitest_*` launch
    /// argument.
    static func uitestExhaust() {
        UserDefaults.standard.set(freeTranscriptionLimit, forKey: usedCountKey)
    }
}
