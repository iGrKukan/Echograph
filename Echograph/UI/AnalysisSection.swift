import SwiftUI
import MarkdownUI

struct AnalysisSection: View {
    let analysis: String?

    var body: some View {
        if let analysis, !analysis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.tint)
                    Text("AI Analysis")
                        .font(.headline)
                    Spacer()
                }
                Markdown(analysis)
                    .markdownTheme(.gitHub)
                    .textSelection(.enabled)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
