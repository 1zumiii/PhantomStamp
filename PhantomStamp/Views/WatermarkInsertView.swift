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
    @Bindable var settingsStore: UserSettingsStore

    @State private var vm: WatermarkInsertViewModel
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showOverflowSheet = false
    @FocusState private var isPayloadFocused: Bool
    @State private var lastAppliedDefaultPayload: String?

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
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Embed Watermark")
            .scrollIndicators(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))

            floatingActions
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
        }
        .sheet(isPresented: $showOverflowSheet) {
            UploadedImagesOverflowSheet(items: vm.selectedPhotoItems, onRemove: { vm.removePhoto(id: $0) })
        }
        .onAppear {
            // Sync initial payload from Settings (persisted) into the input box.
            // Only seed when the draft is empty so we never overwrite user edits.
            applyDefaultPayloadIfAppropriate()
        }
        .onChange(of: settingsStore.defaultWatermarkText) { _, _ in
            // "active notification": when the default watermark text in the settings changes,
            // if the insert page is not currently editing the payload, and the user has not manually overwritten the payload, update the input field automatically.
            applyDefaultPayloadIfAppropriate()
        }
        .onChange(of: isPayloadFocused) { _, focused in
            // try to update the default payload when the payload field loses focus (more user-friendly, avoid overwriting during editing).
            if !focused { applyDefaultPayloadIfAppropriate() }
        }
        .onChange(of: vm.selectedPhotoItems.count) { _, count in
            if count == 0 { showOverflowSheet = false }
        }
        .onChange(of: photoPickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                let loaded = await ImagePickerSupport.loadPickedImages(from: items)
                await MainActor.run {
                    vm.appendPickedItems(loaded)
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

    private func applyDefaultPayloadIfAppropriate() {
        // Never override while the user is actively editing.
        guard !isPayloadFocused else { return }

        let current = vm.watermarkPayload
        let trimmedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)

        let defaultText = settingsStore.defaultWatermarkText
        let trimmedDefault = defaultText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDefault.isEmpty else { return }

        // Only apply when:
        // - input is empty, OR
        // - input equals the last default we applied (meaning user hasn't customized after that)
        let shouldApply: Bool
        if trimmedCurrent.isEmpty {
            shouldApply = true
        } else if let last = lastAppliedDefaultPayload, current == last {
            shouldApply = true
        } else {
            shouldApply = false
        }
        guard shouldApply else { return }

        vm.watermarkPayload = defaultText
        lastAppliedDefaultPayload = defaultText
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
                        HStack(spacing: 10) {
                            Image(systemName: "rectangle.stack.badge.plus")
                                .font(.body.weight(.semibold))
                            Text("Insert more")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(Color.white.opacity(0.95))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.38, green: 0.22, blue: 0.72),
                                            Color(red: 0.18, green: 0.42, blue: 0.78),
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                                }
                        }
                        .shadow(color: Color(red: 0.35, green: 0.2, blue: 0.65).opacity(0.45), radius: 16, x: 0, y: 8)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                }
                .padding(20)
            }
            .allowsHitTesting(true)
    }

    /// Fixed strip height so the Uploaded section keeps layout before any picks arrive.
    private var uploadedThumbnailsRow: some View {
        let items = vm.selectedPhotoItems
        let visible = Array(items.prefix(thumbnailStripMaxVisible))
        let count = items.count
        let manageEnabled = count > 0 && !vm.isEmbedding && !vm.showSuccessOverlay

        return ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(visible) { item in
                    thumbnailCell(for: item.image)
                }

                // Always show the gallery/manage affordance; disabled when there is nothing to manage.
                Button {
                    guard manageEnabled else { return }
                    showOverflowSheet = true
                } label: {
                    manageUploadedChip(totalCount: count)
                }
                .buttonStyle(.plain)
                .disabled(!manageEnabled)
                .opacity(manageEnabled ? 1 : 0.42)
                .accessibilityLabel(count > 0 ? "View all \(count) uploads" : "Manage uploads, no photos selected")
            }
            .padding(.vertical, 4)
            .frame(minHeight: thumbnailStripMinHeight, alignment: .center)
        }
        .scrollIndicators(.hidden)
        .frame(minHeight: thumbnailStripMinHeight + 8)
    }

    private var thumbnailStripMinHeight: CGFloat { 62 }

    private func manageUploadedChip(totalCount: Int) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .frame(width: 58, height: 58)
            .overlay {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .overlay(alignment: .topTrailing) {
                if totalCount > 0 {
                    Text("\(totalCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(Color.accentColor))
                        .offset(x: 4, y: -4)
                }
            }
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

                // Inline character budget on the trailing edge of the field.
                HStack(spacing: 10) {
                    TextField(
                        "Watermark message",
                        text: payloadTextBinding,
                        axis: .vertical
                    )
                    .lineLimit(1...3)
                    .focused($isPayloadFocused)
                    .submitLabel(.done)
                    .onSubmit { isPayloadFocused = false }
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .textFieldStyle(.plain)
                    .disabled(vm.isEmbedding || vm.showSuccessOverlay)

                    Text(payloadCountLabel)
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(payloadCountColor)
                        .padding(.leading, 4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }

                Text(payloadHintBelowField)
                    .font(.caption)
                    .foregroundStyle(vm.isPayloadLengthValid ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isPayloadFocused = false }
            }
        }
    }

    private var payloadCountLabel: String {
        "\(vm.trimmedPayload.count)/\(WatermarkInsertViewModel.payloadMaxLength)"
    }

    private var payloadCountColor: Color {
        vm.isPayloadLengthValid ? Color.secondary : Color.orange
    }

    /// Guidance only (counts live on the right inside the field container).
    private var payloadHintBelowField: String {
        "Required: \(WatermarkInsertViewModel.payloadMinLength)–\(WatermarkInsertViewModel.payloadMaxLength) non-empty characters after trimming spaces."
    }

    private var embedFABReady: Bool {
        vm.canStartEmbed && !vm.isEmbedding
    }

    private var embedFABIconColor: Color {
        if vm.isEmbedding { return Color.white.opacity(0.92) }
        if vm.canStartEmbed { return .white }
        // Idle: same low-contrast treatment as the disabled “manage uploads” chip (`.secondary` on tertiary fill).
        return Color.secondary
    }

    /// Bright gradient when ready or running.
    private var embedFABGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.32, green: 0.55, blue: 1.00),
                Color(red: 0.35, green: 0.85, blue: 0.95),
                Color(red: 0.88, green: 0.42, blue: 0.98),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var embedFABBackgroundFill: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if vm.canStartEmbed || vm.isEmbedding {
            shape.fill(embedFABGradient)
        } else {
            shape.fill(Color(uiColor: .tertiarySystemGroupedBackground))
        }
    }

    private var embedFABStrokeColor: Color {
        if embedFABReady { return Color.white.opacity(0.45) }
        if vm.isEmbedding { return Color.white.opacity(0.18) }
        return Color.primary.opacity(0.12)
    }

    private var embedFABShadowColor: Color {
        if embedFABReady {
            return Color(red: 0.38, green: 0.42, blue: 1.0).opacity(0.5)
        }
        if vm.isEmbedding {
            return Color.black.opacity(0.2)
        }
        return Color.black.opacity(0.04)
    }

    private var embedFABShadowRadius: CGFloat {
        embedFABReady ? 26 : (vm.isEmbedding ? 20 : 6)
    }

    private var embedFABShadowY: CGFloat {
        embedFABReady ? 16 : 6
    }

    /// Matches `manageUploadedChip` when there is nothing to open: same fill + dimmed with `0.42` opacity.
    private var embedFABInactiveDimOpacity: Double {
        (embedFABReady || vm.isEmbedding) ? 1.0 : 0.42
    }

    private var floatingActions: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Spacer()

                Button {
                    guard vm.canStartEmbed else { return }
                    Task { await vm.embedWatermark() }
                } label: {
                    Image(systemName: vm.isEmbedding ? "hourglass" : "sparkles")
                        .font(.body.weight(.semibold))
                        .symbolEffect(.pulse, options: .repeating, isActive: vm.canStartEmbed && !vm.isEmbedding)
                        .frame(width: 52, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(embedFABIconColor)
                .background {
                    embedFABBackgroundFill
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(embedFABStrokeColor, lineWidth: embedFABReady ? 1.5 : 1)
                }
                .shadow(color: embedFABShadowColor, radius: embedFABShadowRadius, x: 0, y: embedFABShadowY)
                .scaleEffect(embedFABReady ? 1.04 : 1.0)
                .opacity(embedFABInactiveDimOpacity)
                .animation(.spring(response: 0.32, dampingFraction: 0.72), value: embedFABReady)
                .animation(.easeOut(duration: 0.2), value: vm.isEmbedding)
                // Use hit-testing instead of `.disabled` so SwiftUI does not apply extra gray wash over our styling.
                .allowsHitTesting(vm.canStartEmbed)
                .accessibilityLabel(
                    vm.canStartEmbed
                        ? "Insert watermark"
                        : "Insert watermark, unavailable until photos and watermark text are valid."
                )
            }
        }
    }
}

#Preview {
    NavigationStack {
        WatermarkInsertView(watermarkService: WatermarkService(), settingsStore: UserSettingsStore())
    }
}
