//
//  WatermarkExtractUI.swift
//  PhantomStamp
//
//  Presentational-only UI for extract flow.
//  Keep business logic (loading, service calls, state mutations) in the caller.
//

import SwiftUI
import PhotosUI
import UIKit

struct WatermarkExtractUI: View {
    var records: [ExtractionRecord]
    var isExtracting: Bool
    var canExtract: Bool

    @Binding var photoPickerItems: [PhotosPickerItem]

    /// Non-extract failures (e.g. picker load failures).
    var pickerErrorMessage: String?
    var onDismissPickerError: () -> Void

    var onTapExtract: () -> Void
    var onTapClearResults: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                uploadCard
                extractButton
                recordsList
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Extract Watermark")
        .navigationBarTitleDisplayMode(.large)
        .alert("Could not load images", isPresented: pickerErrorBinding, actions: {
            Button("OK", role: .cancel) { onDismissPickerError() }
        }, message: {
            Text(pickerErrorMessage ?? "")
        })
    }

    private var pickerErrorBinding: Binding<Bool> {
        Binding(
            get: { pickerErrorMessage != nil },
            set: { if !$0 { onDismissPickerError() } }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Demo mode")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                }

            Text("Recover hidden watermark data.")
                .font(.headline.weight(.semibold))

            Text("Upload a stamped image to detect and recover a hidden message.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var uploadCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Stamped Image", systemImage: "photo")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            PhotosPicker(
                selection: $photoPickerItems,
                maxSelectionCount: nil,
                matching: ImagePickerSupport.imagesOnlyFilter,
                preferredItemEncoding: .automatic
            ) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))

                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            Color.primary.opacity(0.28),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 7])
                        )

                    VStack(spacing: 10) {
                        Image(systemName: "photo.badge.plus")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)

                        Text("Tap to upload a watermarked photo")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("PNG or JPEG · Up to 4K")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 18)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var recordsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Extraction Records")
                    .font(.headline.weight(.semibold))
                Spacer(minLength: 12)
                if !records.isEmpty {
                    Button {
                        onTapClearResults()
                    } label: {
                        Text("Clear results")
                            .font(.subheadline.weight(.semibold))
                    }
                    .disabled(isExtracting)
                    .accessibilityLabel("Clear extraction records on this page")
                }
            }

            if records.isEmpty {
                emptyRecordsCard
            } else {
                ForEach(records) { record in
                    NavigationLink {
                        ExtractionDetailView(record: record)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: record.status.iconName)
                                .foregroundStyle(record.status.tintColor)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.imageName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text(record.status.title)
                                    .font(.caption)
                                    .foregroundStyle(record.status.tintColor)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyRecordsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "tray")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("No extraction records yet.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Upload a watermarked image and run extraction to create a record.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
    }

    private var extractButton: some View {
        Button {
            onTapExtract()
        } label: {
            HStack {
                Image(systemName: isExtracting ? "hourglass" : "sparkles")
                Text(isExtracting ? "Extracting..." : "Extract Watermark")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor)
            }
        }
        .buttonStyle(.plain)
        .disabled(!canExtract)
        .opacity(canExtract ? 1 : 0.45)
    }
}

struct WatermarkExtractView: View {
    let watermarkService: any WatermarkServiceProtocol

    @State private var vm: WatermarkExtractViewModel
    @State private var photoPickerItems: [PhotosPickerItem] = []

    init(watermarkService: any WatermarkServiceProtocol) {
        self.watermarkService = watermarkService
        _vm = State(initialValue: WatermarkExtractViewModel(watermarkService: watermarkService))
    }

    var body: some View {
        WatermarkExtractUI(
            records: vm.records,
            isExtracting: vm.isExtracting,
            canExtract: vm.canExtract,
            photoPickerItems: $photoPickerItems,
            pickerErrorMessage: vm.errorMessage,
            onDismissPickerError: { vm.errorMessage = nil },
            onTapExtract: { Task { await vm.extractWatermarks() } },
            onTapClearResults: { vm.clearPageResults() }
        )
        .onChange(of: photoPickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                let loaded = await ImagePickerSupport.loadPickedImages(from: items)
                await MainActor.run {
                    if loaded.isEmpty {
                        vm.errorMessage = "Failed to load one or more selected images."
                    } else {
                        vm.errorMessage = nil
                        vm.appendPickedPhotoItems(loaded)
                    }
                    photoPickerItems = []
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        WatermarkExtractView(watermarkService: WatermarkService())
    }
}

