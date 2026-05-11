//
//  ExtractionDetailView.swift
//  PhantomStamp
//

import SwiftData
import SwiftUI
import UIKit

/// Unified detail screen for a single embed/extract operation (live session or history).
struct ExtractionDetailView: View {
    let display: OperationDetailDisplay

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroCard
                headerRow
                messageCard
                metricsGrid
                failureCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(display.navigationTitleName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if display.persistedHistoryRecordId != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                    .accessibilityLabel("Delete from history")
                }
            }
        }
        .alert("Delete this entry?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deletePersistedHistoryIfNeeded()
            }
        } message: {
            Text(
                "“\(display.imageName)” will be removed from history on this device. This cannot be undone."
            )
        }
    }

    private func deletePersistedHistoryIfNeeded() {
        guard let id = display.persistedHistoryRecordId else { return }
        do {
            _ = try HistoryRecordService.deleteRecord(id: id, context: modelContext)
            NotificationCenter.default.post(
                name: AppConstants.Notifications.watermarkHistoryRecordsDidChange,
                object: nil
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            print("[ExtractionDetailView] delete failed: \(error)")
        }
    }

    private var heroCard: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let height = heroHeight(forWidth: width)

            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 0.88, green: 0.85, blue: 0.82))

                if let image = display.previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: height)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.2))
                    }
                    .frame(width: width, height: height)
                }

                statusPill
                    .padding(12)
            }
            .frame(width: width, height: height)
        }
        .frame(height: heroHeight(forWidth: UIScreen.main.bounds.width - 40))
        .overlay(alignment: .bottomLeading) {
            Text(display.formatBadgeUppercase)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.45))
                }
                .padding(12)
        }
    }

    private func heroHeight(forWidth width: CGFloat) -> CGFloat {
        if let image = display.previewImage {
            let iw = max(1, image.size.width * image.scale)
            let ih = max(1, image.size.height * image.scale)
            let ratio = ih / iw
            return min(max(width * ratio, 220), 340)
        }
        if let w = display.imagePixelWidth, let h = display.imagePixelHeight, w > 0, h > 0 {
            let ratio = CGFloat(h) / CGFloat(w)
            return min(max(width * ratio, 220), 340)
        }
        return 260
    }

    private var statusPill: some View {
        let isSuccess = display.status == .success
        let isFailed = display.status == .failed

        let fgColor: Color = isSuccess ? .green : (isFailed ? .red : .orange)
        let bgColor: Color = .black.opacity(0.24)
        let iconName = isSuccess ? "checkmark.circle.fill" : (isFailed ? "xmark.octagon.fill" : "clock.fill")
        let text = isSuccess ? "Success" : (isFailed ? "Failed" : "Pending")

        return HStack(spacing: 6) {
            Image(systemName: iconName)
            Text(text)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(fgColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule(style: .continuous)
                .fill(bgColor)
        }
    }

    private var operationTitle: String {
        switch display.operationKind {
        case .extract:
            return "Extract watermark"
        case .embed:
            return "Embed watermark"
        }
    }

    private var operationIcon: String {
        switch display.operationKind {
        case .extract:
            return "doc.text.magnifyingglass"
        case .embed:
            return "wand.and.stars"
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center) {
            Label(operationTitle, systemImage: operationIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                }

            Spacer(minLength: 12)

            Text(RelativeDateTimeFormat.humanReadable(display.occurredAt))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var payloadSectionTitle: String {
        switch display.operationKind {
        case .extract:
            return "WATERMARK TEXT"
        case .embed:
            return "EMBEDDED TEXT"
        }
    }

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(payloadSectionTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(display.status == .success ? (display.primaryText ?? "—") : "—")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if display.status == .success, let text = display.primaryText, !text.isEmpty {
                    Button {
                        UIPasteboard.general.string = text
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(uiColor: .systemBackground).opacity(0.55))
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy watermark text")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
    }

    private var metricsGrid: some View {
        let sizeText: String = {
            if let w = display.imagePixelWidth, let h = display.imagePixelHeight, w > 0, h > 0 {
                return "\(w) × \(h)"
            }
            if let img = display.previewImage {
                let w = Int(img.size.width * img.scale)
                let h = Int(img.size.height * img.scale)
                return "\(w) × \(h)"
            }
            return "—"
        }()
        let formatText: String = {
            let ext = ((display.imageName as NSString).pathExtension).uppercased()
            return ext.isEmpty ? "—" : ext
        }()
        let durationText: String = {
            guard let ms = display.durationMs else { return "—" }
            return String(format: "%.1fs", ms / 1000.0)
        }()

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                metricCard(title: "Processing", value: durationText, systemImage: "clock")
                metricCard(title: "Format", value: formatText, systemImage: "doc")
            }
            metricCard(title: "Image size", value: sizeText, systemImage: "arrow.up.left.and.arrow.down.right")
            if display.operationKind == .extract, let sync = display.syncMatchCount {
                metricCard(title: "Sync matches", value: "\(sync)", systemImage: "checklist")
            }
        }
    }

    @ViewBuilder
    private var failureCard: some View {
        if display.status == .failed {
            VStack(alignment: .leading, spacing: 8) {
                Text("Failure reason")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(display.failureReason ?? defaultFailureCopy)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            }
        }
    }

    private var defaultFailureCopy: String {
        switch display.operationKind {
        case .extract:
            return "The watermark could not be extracted from this image."
        case .embed:
            return "The watermark could not be embedded in this image."
        }
    }

    private func metricCard(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
    }
}

extension ExtractionDetailView {
    /// Convenience for the extract tab’s in-memory `ExtractionRecord` list.
    init(record: ExtractionRecord) {
        self.init(display: OperationDetailDisplay(extraction: record))
    }
}
