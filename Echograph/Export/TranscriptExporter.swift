import Foundation
import PDFKit
import UIKit

enum ExportFormat: String, CaseIterable, Identifiable, Hashable {
    case txt
    case markdown
    case srt
    case vtt
    case pdf

    var id: String { rawValue }
    var fileExtension: String {
        switch self {
        case .txt: return "txt"
        case .markdown: return "md"
        case .srt: return "srt"
        case .vtt: return "vtt"
        case .pdf: return "pdf"
        }
    }

    var displayName: String {
        switch self {
        case .txt: return "Plain Text"
        case .markdown: return "Markdown"
        case .srt: return "SubRip (.srt)"
        case .vtt: return "WebVTT (.vtt)"
        case .pdf: return "PDF"
        }
    }

    var systemImage: String {
        switch self {
        case .txt: return "doc.text"
        case .markdown: return "text.alignleft"
        case .srt, .vtt: return "captions.bubble"
        case .pdf: return "doc.richtext"
        }
    }
}

enum TranscriptExporter {
    /// Render the transcript to the given format and return a temporary file URL.
    static func export(
        recording: Recording,
        format: ExportFormat
    ) throws -> URL {
        let body = renderBody(recording: recording, format: format)

        let safeTitle = sanitize(recording.title)
        let filename = "\(safeTitle).\(format.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)

        switch format {
        case .pdf:
            let data = try renderPDF(title: recording.title, body: body)
            try data.write(to: url, options: [.atomic])
        case .txt, .markdown, .srt, .vtt:
            try body.data(using: .utf8)?.write(to: url, options: [.atomic])
        }

        return url
    }

    private static func renderBody(recording: Recording, format: ExportFormat) -> String {
        guard let transcript = recording.transcript else {
            return "No transcript available."
        }

        switch format {
        case .txt:
            return transcript.fullText
        case .markdown:
            var lines: [String] = []
            lines.append("# \(recording.title)")
            lines.append("")
            lines.append("_\(recording.createdAt.formatted(date: .abbreviated, time: .shortened))_")
            lines.append("")
            for segment in transcript.segments {
                lines.append("**\(timecode(segment.startTime))**  \(segment.text)")
                lines.append("")
            }
            return lines.joined(separator: "\n")
        case .srt:
            var output = ""
            for (index, segment) in transcript.segments.enumerated() {
                output += "\(index + 1)\n"
                output += "\(srtTime(segment.startTime)) --> \(srtTime(segment.endTime))\n"
                output += "\(segment.text)\n\n"
            }
            return output
        case .vtt:
            var output = "WEBVTT\n\n"
            for segment in transcript.segments {
                output += "\(vttTime(segment.startTime)) --> \(vttTime(segment.endTime))\n"
                output += "\(segment.text)\n\n"
            }
            return output
        case .pdf:
            // PDF body assembled separately, using markdown-ish layout
            var lines: [String] = []
            lines.append(recording.title)
            lines.append(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
            lines.append("")
            for segment in transcript.segments {
                lines.append("[\(timecode(segment.startTime))]  \(segment.text)")
            }
            return lines.joined(separator: "\n")
        }
    }

    private static func renderPDF(title: String, body: String) throws -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let margin: CGFloat = 48
        let contentRect = pageRect.insetBy(dx: margin, dy: margin)
        let format = UIGraphicsPDFRendererFormat()
        let metadata: [AnyHashable: Any] = [
            kCGPDFContextTitle: title,
            kCGPDFContextCreator: "Echograph"
        ]
        format.documentInfo = metadata as? [String: Any] ?? [:]

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        return renderer.pdfData { context in
            context.beginPage()

            let titleFont = UIFont.systemFont(ofSize: 22, weight: .semibold)
            let bodyFont = UIFont.systemFont(ofSize: 12)
            let lineSpacing: CGFloat = 6

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.label
            ]
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: UIColor.label
            ]

            var y = contentRect.minY
            let titleString = NSAttributedString(string: title, attributes: titleAttrs)
            titleString.draw(in: CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: 32))
            y += 40

            let paragraphs = body.components(separatedBy: "\n")
            for line in paragraphs {
                let attr = NSAttributedString(string: line, attributes: bodyAttrs)
                let textRect = CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: contentRect.maxY - y)
                let bounding = attr.boundingRect(with: CGSize(width: contentRect.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil)
                if y + bounding.height > contentRect.maxY {
                    context.beginPage()
                    y = contentRect.minY
                }
                attr.draw(with: textRect, options: [.usesLineFragmentOrigin], context: nil)
                y += bounding.height + lineSpacing
            }
        }
    }

    private static func sanitize(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: " -_"))
        return s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
            .map(String.init).joined()
            .trimmingCharacters(in: .whitespaces)
            .isEmpty ? "Recording" : s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
            .map(String.init).joined()
    }

    private static func timecode(_ time: TimeInterval) -> String {
        let total = Int(time.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private static func srtTime(_ time: TimeInterval) -> String {
        let total = Int(time)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        let ms = Int((time - floor(time)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    private static func vttTime(_ time: TimeInterval) -> String {
        let total = Int(time)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        let ms = Int((time - floor(time)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
    }
}
