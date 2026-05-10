import AVFoundation
import Foundation
import Observation
@preconcurrency import WatchConnectivity

@MainActor
@Observable
final class WatchRecorder: NSObject {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var isTransferring = false
    private(set) var lastError: String?

    private var recorder: AVAudioRecorder?
    private var startTime: Date?
    private var timer: Timer?

    override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    func toggle() {
        if isRecording {
            stop()
        } else {
            start()
        }
    }

    func start() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [])
            try session.setActive(true, options: [])

            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let filename = "watch-\(Self.timestamp()).m4a"
            let url = documents.appendingPathComponent(filename)

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000
            ]

            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.record() else {
                lastError = "Failed to start recording"
                return
            }

            self.recorder = recorder
            self.startTime = .now
            self.isRecording = true
            self.elapsed = 0
            startTimer()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        guard let recorder else { return }
        let url = recorder.url
        recorder.stop()
        let recordedDuration = elapsed
        self.recorder = nil
        startTime = nil
        isRecording = false
        elapsed = 0

        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])

        sendToPhone(url: url, duration: recordedDuration)
    }

    private func sendToPhone(url: URL, duration: TimeInterval) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        isTransferring = true
        let metadata: [String: Any] = [
            "filename": url.lastPathComponent,
            "duration": duration,
            "createdAt": Date.now.timeIntervalSince1970
        ]
        _ = session.transferFile(url, metadata: metadata)
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startTime else { return }
                self.elapsed = Date.now.timeIntervalSince(start)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: .now)
    }
}

extension WatchRecorder: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        Task { @MainActor in
            self.isTransferring = false
            if error == nil {
                try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
            } else {
                self.lastError = error?.localizedDescription
            }
        }
    }
}
