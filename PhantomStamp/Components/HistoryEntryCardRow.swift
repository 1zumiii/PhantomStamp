//
//  HistoryEntryCardRow.swift
//  PhantomStamp
//
//  Reusable card row for HistoryEntry list.
//

import SwiftUI

/// A modern card-style row for a single `HistoryEntry`.
///
/// Current data model only contains `kind/message/createdAt`, so:
/// - File name is a placeholder ("Untitled image") until persisted metadata exists.
/// - The "watermark name" is best-effort parsed from `message` for now.
struct HistoryEntryCardRow: View {
    let entry: HistoryEntry
    let compact: Bool

    public init(entry: HistoryEntry, compact: Bool) {
        self.entry = entry
        self.compact = compact
    }

    var body: some View {
        let meta = HistoryRowMeta(entry: entry)

        HStack(alignment: .top, spacing: 14) {
            HistoryPreviewTile(kind: entry.kind)

            VStack(alignment: .leading, spacing: compact ? 6 : 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(meta.fileName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 10)

                    Text(entry.createdAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                if let watermarkName = meta.watermarkName {
                    Label(watermarkName, systemImage: "seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                } else {
                    Text(entry.kind)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(entry.message)
                    .font(compact ? .caption : .subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 2 : 3)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 18, x: 0, y: 10)
        .contentShape(Rectangle())
    }
}

/// Preview tile used by history cards (placeholder until real thumbnails exist).
struct HistoryPreviewTile: View {
    let kind: String

    var body: some View {
        let style = HistoryPreviewStyle(kind: kind)
        return ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(style.gradient)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)

            Image(systemName: style.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 62, height: 62)
        .accessibilityLabel("Preview")
    }
}

// MARK: - Parsing helpers

private struct HistoryRowMeta {
    var fileName: String
    var watermarkName: String?

    init(entry: HistoryEntry) {
        fileName = "Untitled image"
        watermarkName = HistoryRowMeta.parseWatermarkName(from: entry.message)
    }

    private static func parseWatermarkName(from message: String) -> String? {
        if let v = extractBetween(message, start: "文案：", end: "）") { return v }
        if let v = extractAfter(message, prefix: "text:") { return v.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }

    private static func extractBetween(_ s: String, start: String, end: String) -> String? {
        guard let r1 = s.range(of: start) else { return nil }
        let tail = s[r1.upperBound...]
        guard let r2 = tail.range(of: end) else { return nil }
        let v = String(tail[..<r2.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    private static func extractAfter(_ s: String, prefix: String) -> String? {
        guard let r = s.range(of: prefix, options: [.caseInsensitive]) else { return nil }
        let v = String(s[r.upperBound...])
        return v.isEmpty ? nil : v
    }
}

private struct HistoryPreviewStyle {
    var systemImage: String
    var gradient: LinearGradient

    init(kind: String) {
        if kind.contains("embedded") {
            systemImage = "wand.and.stars"
            gradient = LinearGradient(
                colors: [Color.blue.opacity(0.95), Color.purple.opacity(0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if kind.contains("extract") {
            systemImage = "text.magnifyingglass"
            gradient = LinearGradient(
                colors: [Color.teal.opacity(0.95), Color.blue.opacity(0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            systemImage = "doc.text"
            gradient = LinearGradient(
                colors: [Color.gray.opacity(0.75), Color.black.opacity(0.65)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

#Preview {
    let entry = HistoryEntry(kind: "watermark.embedded", message: "Embedding completed (Text: MyText)")
    return VStack {
        HistoryEntryCardRow(entry: entry, compact: false)
        HistoryEntryCardRow(entry: entry, compact: true)
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}

