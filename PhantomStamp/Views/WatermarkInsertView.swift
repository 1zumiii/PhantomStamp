//
//  WatermarkInsertView.swift
//  PhantomStamp
//
//  Insert-watermark flow: pick images, validate payload length, embed via WatermarkService, save to Photos.
//

import PhotosUI
import SwiftUI

struct WatermarkInsertView: View {
    let watermarkService: any WatermarkServiceProtocol
    var settingsStore: UserSettingsStore

    @State private var vm: WatermarkInsertViewModel
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showOverflowSheet = false

    private let thumbnailStripMaxVisible = 6

    init(watermarkService: any WatermarkServiceProtocol, settingsStore: UserSettingsStore) {
        self.watermarkService = watermarkService
        self.settingsStore = settingsStore
        _vm = State(initialValue: WatermarkInsertViewModel(watermarkService: watermarkService))
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    uploadCard
                    inputCard
                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Insert Watermark")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        RobustnessTestingView(watermarkService: watermarkService, settingsStore: settingsStore)
                    } label: {
                        Label("Tools", systemImage: "wrench.and.screwdriver")
                    }
                }
            }

            floatingActions
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
        }
        .sheet(isPresented: $showOverflowSheet) {
            UploadedImagesOverflowSheet(items: vm.selectedPhotoItems, onRemove: { vm.removePhoto(id: $0) })
                .presentationDetents([.medium, .large])
        }
        .onChange(of: vm.selectedPhotoItems.count) { _, count in
            if count == 0 { showOverflowSheet = false }
        }
        .onChange(of: photoPickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                let loaded = await ImagePickerSupport.loadImages(from: items)
                await MainActor.run {
                    vm.appendImages(loaded)
                    photoPickerItems = []
                }
            }
        }
        .alert("Embedding failed", isPresented: embedErrorBinding, actions: {
            Button("OK", role: .cancel) { vm.acknowledgeEmbedError() }
        }, message: {
            Text(vm.embedErrorMessage ?? "")
        })
    }

    private var embedErrorBinding: Binding<Bool> {
        Binding(
            get: { vm.showEmbedErrorAlert },
            set: { vm.showEmbedErrorAlert = $0 }
        )
    }

    private var payloadTextBinding: Binding<String> {
        Binding(
            get: { vm.watermarkPayload },
            set: { newValue in
                if newValue.count > WatermarkInsertViewModel.payloadMaxLength {
                    vm.watermarkPayload = String(newValue.prefix(WatermarkInsertViewModel.payloadMaxLength))
                } else {
                    vm.watermarkPayload = newValue
                }
            }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Embed flow")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                }

            Text("Add photos & payload")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Pick one or more images, enter \(WatermarkInsertViewModel.payloadMinLength)–\(WatermarkInsertViewModel.payloadMaxLength) characters for the watermark, then tap the sparkle button.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var uploadCard: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        return VStack(alignment: .leading, spacing: 12) {
            Label("Upload", systemImage: "arrow.up.doc")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            PhotosPicker(
                selection: $photoPickerItems,
                maxSelectionCount: nil,
                matching: ImagePickerSupport.imagesOnlyFilter,
                preferredItemEncoding: .automatic,
                label: {
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
                            Text("Tap to choose photos")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Images only • Added picks append to the strip")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 18)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .contentShape(Rectangle())
                }
            )
            .buttonStyle(.plain)
            .disabled(vm.isEmbedding || vm.showSuccessOverlay)

            Divider()
                .opacity(0.35)

            HStack(alignment: .center, spacing: 10) {
                Label("Uploaded", systemImage: "rectangle.stack")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(vm.selectedPhotoItems.isEmpty ? "None yet" : "\(vm.selectedPhotoItems.count) photo(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            uploadedThumbnailsRow
        }
        .padding(18)
        .background {
            shape.fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .overlay {
            shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 22, x: 0, y: 12)
        .overlay {
            if vm.showSuccessOverlay {
                uploadSuccessOverlay
            }
        }
    }

    /// Blurred overlay after a successful embed; offers “Insert more” to reset upload state.
    private var uploadSuccessOverlay: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green, .primary.opacity(0.15))
                        .symbolRenderingMode(.palette)

                    Text("Watermark embedded")
                        .font(.headline.weight(.semibold))

                    Text("Images were saved to your photo library.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    Button {
                        vm.dismissSuccessOverlayAndResetUploadState()
                    } label: {
                        Text("Insert more")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 24)
                }
                .padding(20)
            }
            .allowsHitTesting(true)
    }

    private var uploadedThumbnailsRow: some View {
        let items = vm.selectedPhotoItems
        let visible = Array(items.prefix(thumbnailStripMaxVisible))
        let overflow = max(0, items.count - visible.count)

        return ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(visible) { item in
                    thumbnailCell(for: item.image)
                }

                if overflow > 0 {
                    Button {
                        showOverflowSheet = true
                    } label: {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                            }
                            .frame(width: 58, height: 58)
                            .overlay {
                                Image(systemName: "square.grid.2x2.fill")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .overlay(alignment: .topTrailing) {
                                Text("\(items.count)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(Circle().fill(Color.accentColor))
                                    .offset(x: 4, y: -4)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View all \(items.count) uploads")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func thumbnailCell(for uiImage: UIImage) -> some View {
        Image(uiImage: uiImage)
            .resizable()
            .scaledToFill()
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Payload", systemImage: "character.cursor.ibeam")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Text("Watermark text")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField(
                    "Enter \(WatermarkInsertViewModel.payloadMinLength)–\(WatermarkInsertViewModel.payloadMaxLength) characters",
                    text: payloadTextBinding
                )
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
                .textFieldStyle(.roundedBorder)
                .disabled(vm.isEmbedding || vm.showSuccessOverlay)

                HStack {
                    Text(lengthHint)
                        .font(.caption)
                        .foregroundStyle(vm.isPayloadLengthValid ? Color.secondary : Color.orange)
                    Spacer()
                }
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        }
    }

    private var lengthHint: String {
        let n = vm.trimmedPayload.count
        return "\(n)/\(WatermarkInsertViewModel.payloadMaxLength) • Minimum \(WatermarkInsertViewModel.payloadMinLength) characters (trimmed)"
    }

    private var floatingActions: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Spacer()

                Button {
                    vm.resetDraft()
                    photoPickerItems = []
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.body.weight(.semibold))
                        .frame(width: 52, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.14), radius: 18, x: 0, y: 10)
                .disabled(vm.isEmbedding)
                .accessibilityLabel("Reset draft")

                Button {
                    Task { await vm.embedWatermark() }
                } label: {
                    Image(systemName: vm.isEmbedding ? "hourglass" : "sparkles")
                        .font(.body.weight(.semibold))
                        .frame(width: 52, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.32, green: 0.55, blue: 1.00),
                                    Color(red: 0.35, green: 0.85, blue: 0.95),
                                    Color(red: 0.88, green: 0.42, blue: 0.98),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 14)
                .disabled(!vm.canStartEmbed || vm.isEmbedding)
                .accessibilityLabel("Insert watermark")
            }
        }
    }
}

#Preview {
    NavigationStack {
        WatermarkInsertView(watermarkService: WatermarkService(), settingsStore: UserSettingsStore())
    }
}
