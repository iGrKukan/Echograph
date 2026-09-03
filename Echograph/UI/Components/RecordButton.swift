import SwiftUI

struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    @State private var pulse = false

    private let diameter: CGFloat = 72

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer pulse ring — only while recording; fully hidden at
                // rest so idle state reads as a soft shadow, not a glow.
                Circle()
                    .stroke(DS.Color.record.opacity(0.35), lineWidth: 4)
                    .frame(width: diameter + 24, height: diameter + 24)
                    .scaleEffect(pulse ? 1.25 : 1.0)
                    .opacity(isRecording ? (pulse ? 0 : 1) : 0)
                    .animation(
                        isRecording
                            ? .easeOut(duration: 1.4).repeatForever(autoreverses: false)
                            : .default,
                        value: pulse
                    )

                Circle()
                    .fill(DS.Color.record.gradient)
                    .frame(width: diameter, height: diameter)
                    .shadow(color: DS.Color.record.opacity(isRecording ? 0.5 : 0.3), radius: isRecording ? 16 : 10, y: 4)

                if isRecording {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.white)
                        .frame(width: 22, height: 22)
                } else {
                    Circle()
                        .fill(.white)
                        .frame(width: 26, height: 26)
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
