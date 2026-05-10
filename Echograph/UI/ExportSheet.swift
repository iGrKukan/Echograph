import SwiftUI

struct ExportSheet: View {
    let recording: Recording
    @Environment(\.dismiss) private var dismiss
    @State private var exportedURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ExportFormat.allCases) { format in
                        Button {
                            export(format)
                        } label: {
                            HStack {
                                Label(format.displayName, systemImage: format.systemImage)
                                Spacer()
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Files are generated locally on your device.")
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Export failed", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: shareBinding) {
                if let exportedURL {
                    ShareSheet(items: [exportedURL])
                        .presentationDetents([.medium])
                }
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { newValue in if !newValue { errorMessage = nil } })
    }

    private var shareBinding: Binding<Bool> {
        Binding(get: { exportedURL != nil }, set: { newValue in if !newValue { exportedURL = nil } })
    }

    private func export(_ format: ExportFormat) {
        do {
            exportedURL = try TranscriptExporter.export(recording: recording, format: format)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
