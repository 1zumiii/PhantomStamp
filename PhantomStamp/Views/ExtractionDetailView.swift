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
                imagePreviewCard
                statusCard
                resultCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Extraction Detail")
        .navigationBarTitleDisplayMode(.large)
    }

    private var imagePreviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(record.imageName)
                .font(.headline.weight(.semibold))

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))

                if let image = record.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)

                        Text("No preview available")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: record.status.iconName)
                .font(.title3)
                .foregroundStyle(record.status.tintColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("Status")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(record.status.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(record.status.tintColor)
            }

            Spacer()
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
    }

    @ViewBuilder
    private var resultCard: some View {
        switch record.status {
        case .extracted:
            extractedResultCard

        case .failed:
            failedResultCard

        case .pending:
            pendingResultCard
        }
    }

    private var extractedResultCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recovered Watermark")
                .font(.headline.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Watermark message")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(record.message ?? "No message")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.green.opacity(0.12))
                    }
            }

            if let confidence = record.confidence {
                HStack {
                    Text("Confidence")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(Int(confidence * 100))%")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            Button {
                UIPasteboard.general.string = record.message ?? ""
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
    }

    private var failedResultCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Extraction Failed")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.red)

            Text(record.failureReason ?? "The watermark could not be extracted from this image.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                // Retry action can be connected later through ViewModel.
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
    }

    private var pendingResultCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Waiting for Extraction")
                .font(.headline.weight(.semibold))

            Text("This image has not been processed yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
    }
}

#Preview {
    NavigationStack {
        ExtractionDetailView(
            record: ExtractionRecord(
                imageName: "Image 1",
                status: .extracted,
                message: "Hello PhantomStamp",
                confidence: 0.92
            )
        )
    }
}
