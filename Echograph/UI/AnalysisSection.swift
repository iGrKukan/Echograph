import SwiftUI
import MarkdownUI

struct AnalysisSection: View {
    let recordingId: UUID

    @Environment(AnalysisStore.self) private var analysisStore

    var body: some View {
        if let markdown = analysisStore.markdown(for: recordingId) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.tint)
                    Text("AI Analysis")
                        .font(.headline)
                    Spacer()
                }
                Markdown(markdown)
                    .markdownTheme(.gitHub)
                    .textSelection(.enabled)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
