import SwiftUI

struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer pulse ring while recording.
                Circle()
                    .stroke(.red.opacity(0.35), lineWidth: 4)
                    .frame(width: 96, height: 96)
                    .scaleEffect(pulse ? 1.25 : 1.0)
                    .opacity(pulse ? 0 : 1)
                    .animation(
                        isRecording
                            ? .easeOut(duration: 1.4).repeatForever(autoreverses: false)
                            : .default,
                        value: pulse
                    )

                Circle()
                    .fill(.red.gradient)
                    .frame(width: 96, height: 96)
                    .shadow(color: .red.opacity(0.35), radius: 12, y: 4)

                if isRecording {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white)
                        .frame(width: 28, height: 28)
                } else {
                    Circle()
                        .fill(.white)
                        .frame(width: 32, height: 32)
                }
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: isRecording)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        .onChange(of: isRecording, initial: true) { _, newValue in
            pulse = newValue
        }
    }
}

#Preview {
    RecordButton(isRecording: false, action: {})
}
