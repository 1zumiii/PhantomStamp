//
//  ExtractionDetailView.swift
//  PhantomStamp
//

import SwiftUI

struct ExtractionDetailView: View {
    let record: ExtractionRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let image = record.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                detailCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Extraction Detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.imageName)
                .font(.headline.weight(.semibold))
            Text(record.status.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(record.status.tintColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if record.status == .extracted {
                Text("Message")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(record.message ?? "")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            } else if record.status == .failed {
                Text("Failure reason")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(record.failureReason ?? "")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            } else {
                Text("Pending")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Ready to extract.")
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

#Preview {
    NavigationStack {
        ExtractionDetailView(
            record: ExtractionRecord(
                imageName: "IMG_0001.JPG",
                status: .failed,
                message: nil,
                confidence: nil,
                failureReason: "Failed to extract watermark."
            )
        )
    }
}

