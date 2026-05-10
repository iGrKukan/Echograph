import SwiftUI

struct ConsentDisclaimerView: View {
    let onAccept: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)
                    Text("Welcome to Voicekeep")
                        .font(.largeTitle.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("Before you record your first note, a few things to know.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 22) {
                    PointRow(
                        icon: "iphone",
                        title: "On-device only",
                        text: "Audio, transcripts, and AI summaries are processed locally. Nothing is uploaded to any server."
                    )
                    PointRow(
                        icon: "person.2",
                        title: "Recording laws vary",
                        text: "Many countries (and 13 U.S. states) require all participants to consent before being recorded. Please ask before pressing record."
                    )
                    PointRow(
                        icon: "phone.down",
                        title: "Phone calls",
                        text: "iOS doesn't allow third-party apps to record calls directly. For meetings, use speakerphone — Voicekeep will pick up both sides via the mic."
                    )
                    PointRow(
                        icon: "square.and.arrow.down",
                        title: "Import audio files",
                        text: "You can also import existing voice memos and audio files from the Files app — Voicekeep will transcribe them locally."
                    )
                }

                Button {
                    onAccept()
                } label: {
                    Text("I Understand")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 12)

                Text("By continuing you confirm you'll comply with local laws when recording.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
            }
            .padding(28)
        }
        .interactiveDismissDisabled()
    }
}

private struct PointRow: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    ConsentDisclaimerView(onAccept: {})
}
