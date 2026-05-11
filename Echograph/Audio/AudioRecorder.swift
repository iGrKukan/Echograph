import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class AudioRecorder {
    enum State: Equatable {
        case idle
        case preparing
        case recording(startedAt: Date)
        case interrupted(reason: String, accumulated: TimeInterval)
        case stopped
        case failed(message: String)
    }

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var pendingURL: URL?
    private var timer: Timer?
    private let observerHolder = ObserverHolder()

    init() {
        observerHolder.token = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let info = note.userInfo
            let typeRaw = info?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = info?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor in
                self?.handleInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw)
            }
        }
    }

    /// Begin recording. Returns the destination URL on success.
    @discardableResult
    func start() throws -> URL {
        if case .recording = state {
            return pendingURL ?? Recording.recordingsDirectory
        }

        state = .preparing

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true, options: [])

        let filename = "rec-\(Self.timestampString()).m4a"
        let url = Recording.recordingsDirectory.appendingPathComponent(filename)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            state = .failed(message: "Recorder failed to start")
            throw RecorderError.startFailed
        }

        self.recorder = recorder
        self.pendingURL = url
        self.elapsed = 0
        let now = Date.now
        self.state = .recording(startedAt: now)
        Task { await LiveActivityManager.shared.start(title: "Recording") }
        startTimer()
        return url
    }

    func stop() -> URL? {
        switch state {
        case .recording, .interrupted:
            break
        default:
            return nil
        }
        timer?.invalidate()
        timer = nil

        recorder?.stop()
        let url = pendingURL
        recorder = nil
        pendingURL = nil
        state = .stopped

        Task { await LiveActivityManager.shared.end() }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        return url
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        if let url = pendingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recorder = nil
        pendingURL = nil
        elapsed = 0
        state = .idle
        Task { await LiveActivityManager.shared.end() }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt?) {
        guard let typeRaw,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }

        switch type {
        case .began:
            guard case .recording(let startedAt) = state else { return }
            recorder?.pause()
            timer?.invalidate()
            timer = nil
            let accumulated = Date.now.timeIntervalSince(startedAt)
            elapsed = accumulated
            // iOS doesn't tell us the cause directly, but during a phone call
            // this is the only interruption that fires — surface a useful reason.
            let reason = "Paused — phone call active (iOS blocks third-party recording during calls)"
            state = .interrupted(reason: reason, accumulated: accumulated)
            Task { await LiveActivityManager.shared.update(elapsed: accumulated, startedAt: startedAt) }

        case .ended:
            guard case .interrupted(_, let accumulated) = state else { return }
            let shouldResume = optionsRaw
                .map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) }
                ?? true
            guard shouldResume else { return }
            do {
                try AVAudioSession.sharedInstance().setActive(true, options: [])
                guard let recorder, recorder.record() else {
                    state = .failed(message: "Couldn't resume after interruption")
                    return
                }
                // Reset startedAt so elapsed math continues seamlessly from `accumulated`.
                let virtualStart = Date.now.addingTimeInterval(-accumulated)
                state = .recording(startedAt: virtualStart)
                startTimer()
            } catch {
                state = .failed(message: "Couldn't reactivate audio: \(error.localizedDescription)")
            }

        @unknown default:
            break
        }
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, case .recording(let startedAt) = self.state else { return }
                self.elapsed = Date.now.timeIntervalSince(startedAt)
                // Throttle Live Activity updates to ~1Hz to stay within iOS budget
                if Int(self.elapsed * 10) % 10 == 0 {
                    await LiveActivityManager.shared.update(elapsed: self.elapsed, startedAt: startedAt)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    enum RecorderError: Error {
        case startFailed
    }

    /// Holds the NotificationCenter observer outside the @MainActor isolation
    /// domain so its `deinit` can fire from any context (Swift 6 forbids a
    /// nonisolated deinit on @MainActor classes from touching isolated state).
    private final class ObserverHolder: @unchecked Sendable {
        var token: NSObjectProtocol?
        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }

    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: .now)
    }
}
