//
//  ExtractionDetailView.swift
//  PhantomStamp
//

import SwiftUI

struct ExtractionDetailView: View {
    let record: ExtractionRecord

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
        .navigationTitle("Record detail")
        .navigationBarTitleDisplayMode(.large)
    }

    private var heroCard: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.88, green: 0.85, blue: 0.82))

            if let image = record.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.2))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 260)
            }

            statusPill
                .padding(12)
        }
        .overlay(alignment: .bottomLeading) {
            Text(record.imageName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.45))
                }
                .padding(12)
        }
    }

    private var statusPill: some View {
        let isSuccess = record.status == .extracted
        let isFailed = record.status == .failed
        
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

    private var headerRow: some View {
        HStack(alignment: .center) {
            Label("Extract watermark", systemImage: "doc.text.magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                }
            
            Spacer(minLength: 12)
            
            Text(RelativeDateTimeFormat.humanReadable(record.createdAt))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WATERMARK TEXT")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(record.status == .extracted ? (record.message ?? "—") : "—")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if record.status == .extracted, let text = record.message, !text.isEmpty {
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
                    .accessibilityLabel("Copy extracted text")
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
            guard let img = record.image else { return "—" }
            let w = Int(img.size.width * img.scale)
            let h = Int(img.size.height * img.scale)
            return "\(w) × \(h)"
        }()
        let formatText: String = {
            let ext = ((record.imageName as NSString).pathExtension).uppercased()
            return ext.isEmpty ? "—" : ext
        }()
        let durationText: String = {
            guard let ms = record.durationMs else { return "—" }
            return String(format: "%.1fs", ms / 1000.0)
        }()

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                metricCard(title: "Processing", value: durationText, systemImage: "clock")
                metricCard(title: "Format", value: formatText, systemImage: "doc")
            }
            // 替换为一个更符合原型图的尺寸调整图标
            metricCard(title: "Image size", value: sizeText, systemImage: "arrow.up.left.and.arrow.down.right")
        }
    }

    @ViewBuilder
    private var failureCard: some View {
        if record.status == .failed {
            VStack(alignment: .leading, spacing: 8) {
                Text("Failure reason")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(record.failureReason ?? "The watermark could not be extracted from this image.")
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

    // 重构的 metricCard 布局：图标和标题一行，数值在第二行
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
