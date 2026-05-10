import SwiftUI

struct WatchHomeView: View {
    @Environment(WatchRecorder.self) private var recorder

    var body: some View {
        VStack(spacing: 12) {
            timerLabel

            recordButton

            statusFooter
        }
        .padding()
    }

    @ViewBuilder
    private var timerLabel: some View {
        if recorder.isRecording {
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text(format(recorder.elapsed))
                    .font(.title3.monospacedDigit().weight(.semibold))
            }
        } else {
            Text("Echograph")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var recordButton: some View {
        Button {
            recorder.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(.red.gradient)
                    .frame(width: 80, height: 80)
                    .shadow(color: .red.opacity(0.4), radius: 6)
                if recorder.isRecording {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.white)
                        .font(.title2)
                }
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: recorder.isRecording)
        .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start recording")
    }

    @ViewBuilder
    private var statusFooter: some View {
        if recorder.isTransferring {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Sending…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if let error = recorder.lastError {
            Text(error)
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }

    private func format(_ time: TimeInterval) -> String {
        let total = Int(time)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
