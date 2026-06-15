//
//  WatermarkInsertView.swift
//  PhantomStamp
//
//  Insert-watermark flow: pick images, validate payload length, embed via WatermarkService, save to Photos.
//

import PhotosUI
import SwiftUI

private final class AdvancedPreviewDebouncer {
    private var task: Task<Void, Never>?

    func schedule(action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

struct WatermarkInsertView: View {
    let watermarkService: any WatermarkServiceProtocol
    @Bindable var settingsStore: UserSettingsStore

    @State private var vm: WatermarkInsertViewModel
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showOverflowSheet = false
    @FocusState private var isPayloadFocused: Bool
    @State private var lastAppliedDefaultPayload: String?
    @State private var showTextureReferenceGuide: Bool = false

    // Advanced Mode — parameters are LOCAL view state, deliberately isolated from the global
    // `UserSettingsStore` until the sparkle button executes (no settings contamination while tuning).
    @State private var isAdvancedMode: Bool = false
    /// Local UI state for σ (0...10 gray levels); caps the gain-curve X axis at σ².
    @State private var advancedSigma: Double = 6.0
    @State private var loupePreviewSigma: Double = 6.0
    @State private var sigmaLoupeDebouncer = AdvancedPreviewDebouncer()
    /// Local variance → gain curve (Advanced Mode only; never written to `UserSettingsStore`).
    @State private var advancedGainCurve: VarianceGainCurve = {
        var curve = VarianceGainCurve.presetS
        curve.maxVariance = 36.0
        return curve
    }()
    /// Local UI state for the global embedding intensity (adaptive-Q multiplier).
    @State private var advancedIntensity: Double = 10.0
    @State private var loupePreviewIntensity: Double = 10.0
    @State private var intensityLoupeDebouncer = AdvancedPreviewDebouncer()
    @State private var gainCurveSummary: VarianceGainCurveSummary?
    @State private var amplitudeHistogram: AmplitudeHistogramSummary?
    @State private var selectedAdvancedSubTab: AdvancedSubTab = .smoothBlock

    @State private var advancedCanvasVM = AdvancedModeCanvasViewModel()

    private enum AdvancedSubTab {
        case smoothBlock
        case varianceGain
        case intensity
    }

    private struct GainSummaryRequest: Hashable {
        let photoID: UUID
        let curveKey: VarianceGainCurve.PackedKey
    }

    private struct AmplitudeSummaryRequest: Hashable {
        let photoID: UUID
        let curveKey: VarianceGainCurve.PackedKey
        let intensityBits: UInt64
    }

    init(watermarkService: any WatermarkServiceProtocol, settingsStore: UserSettingsStore) {
        self.watermarkService = watermarkService
        self.settingsStore = settingsStore
        _vm = State(initialValue: WatermarkInsertViewModel(watermarkService: watermarkService))
    }

    var body: some View {
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
        .simultaneousGesture(
            TapGesture().onEnded { dismissPayloadKeyboardIfNeeded() }
        )
        .navigationTitle("Embed Watermark")
        .scrollIndicators(.hidden)
        .background {
            PhantomThemeBackdrop()
        }
        .sheet(isPresented: $showTextureReferenceGuide) {
            TextureReferenceGuideSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
        .onChange(of: isAdvancedMode) { _, advanced in
            // Advanced mode is single-image: drop extra picks when switching in.
            if advanced {
                vm.keepOnlyFirstPhoto()
            } else {
                advancedCanvasVM.clear()
                gainCurveSummary = nil
                amplitudeHistogram = nil
            }
        }
        .onChange(of: vm.selectedPhotoItems.first?.id) { _, _ in
            guard isAdvancedMode, vm.selectedPhotoItems.first != nil else {
                advancedCanvasVM.clear()
                gainCurveSummary = nil
                amplitudeHistogram = nil
                return
            }
            gainCurveSummary = nil
            amplitudeHistogram = nil
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

    private var uploadedCountLabel: String {
        let max = WatermarkInsertViewModel.maxSelectedImageCount
        if vm.selectedPhotoItems.isEmpty { return "None yet" }
        return "\(vm.selectedPhotoItems.count) / \(max) photo(s)"
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

    private func dismissPayloadKeyboardIfNeeded() {
        guard isPayloadFocused else { return }
        isPayloadFocused = false
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
            Text("Embedding Flow")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.phantomAccent.opacity(0.14))
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
            // Mode toggle lives at the very top of the card.
            Picker("Embedding mode", selection: $isAdvancedMode) {
                Text("Adaptive").tag(false)
                Text("Advanced").tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(vm.isEmbedding || vm.showSuccessOverlay)

            Label("Upload", systemImage: "arrow.up.doc")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            // Middle viewport: in Advanced mode an uploaded photo takes over the dashed
            // container entirely and becomes the canvas for future visual overlays.
            if isAdvancedMode, let canvasItem = vm.selectedPhotoItems.first {
                advancedCanvasViewport(for: canvasItem)
            } else {
                photoPickerArea
            }

            Divider()
                .opacity(0.35)

            // Bottom panel: multi-image grid (Adaptive) vs parameter sub-tabs (Advanced).
            if isAdvancedMode {
                advancedControlPanel
            } else {
                HStack(alignment: .center, spacing: 10) {
                    Label("Uploaded", systemImage: "rectangle.stack")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(uploadedCountLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                uploadedThumbnailsRow
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .background {
            shape.fill(Color.phantomCardBackground)
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

    /// Dashed PhotosPicker container. In Advanced mode the picker enforces a single photo.
    private var photoPickerArea: some View {
        PhotosPicker(
            selection: $photoPickerItems,
            maxSelectionCount: isAdvancedMode ? 1 : (vm.isAtImageLimit ? 1 : vm.remainingImageSlots),
            matching: ImagePickerSupport.imagesOnlyFilter,
            preferredItemEncoding: .automatic,
            label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.phantomCardBackground)

                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            Color.primary.opacity(0.28),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 7])
                        )

                    VStack(spacing: 10) {
                        Image(systemName: "photo.badge.plus")
                            .font(.title2)
                            .foregroundStyle(Color.phantomAccent)
                        Text(isAdvancedMode ? "Tap to choose a photo" : "Tap to choose photos")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(pickerCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 18)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .contentShape(Rectangle())
            }
        )
        .buttonStyle(.plain)
        .disabled(vm.isEmbedding || vm.showSuccessOverlay || (!isAdvancedMode && vm.isAtImageLimit))
    }

    private var pickerCaption: String {
        if isAdvancedMode {
            return "Single image • Fills the canvas viewport"
        }
        return vm.isAtImageLimit
            ? "Maximum \(WatermarkInsertViewModel.maxSelectedImageCount) photos reached"
            : "Images only • Up to \(WatermarkInsertViewModel.maxSelectedImageCount) • Picks append"
    }

    /// Gain curve with X-axis ceiling synced to the committed σ threshold (σ²).
    private var advancedCurveWithSigmaCap: VarianceGainCurve {
        var curve = advancedGainCurve
        curve.maxVariance = advancedSigma * advancedSigma
        return curve
    }

    private var advancedCanvasVisualization: AdvancedCanvasVisualization {
        switch selectedAdvancedSubTab {
        case .smoothBlock:
            return .smoothBlock(varianceThreshold: Float(loupePreviewSigma * loupePreviewSigma))
        case .varianceGain:
            return .varianceGain(curve: advancedCurveWithSigmaCap)
        case .intensity:
            return .embedIntensity(
                curve: advancedCurveWithSigmaCap,
                embeddingIntensity: Float(loupePreviewIntensity)
            )
        }
    }

    /// Advanced-mode canvas: grid layout with custom reticle sliders (see `AdvancedModeCanvasView`).
    private func advancedCanvasViewport(for item: SelectedPhotoItem) -> some View {
        AdvancedModeCanvasView(
            viewModel: advancedCanvasVM,
            item: item,
            visualization: advancedCanvasVisualization,
            watermarkService: watermarkService,
            isInteractionEnabled: !vm.isEmbedding && !vm.showSuccessOverlay,
            onRemovePhoto: {
                vm.removePhoto(id: item.id)
                advancedCanvasVM.clear()
            }
        )
    }

    /// Advanced-mode bottom panel: nested sub-tab picker + per-parameter sliders.
    /// Sliders bind ONLY to local @State — nothing is written to `UserSettingsStore` here.
    private var advancedControlPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Parameter", selection: $selectedAdvancedSubTab) {
                Text("Soft Areas").tag(AdvancedSubTab.smoothBlock)
                Text("Texture Mix").tag(AdvancedSubTab.varianceGain)
                Text("Strength").tag(AdvancedSubTab.intensity)
            }
            .pickerStyle(.segmented)

            switch selectedAdvancedSubTab {
            case .smoothBlock:
                VStack(alignment: .leading, spacing: 10) {
                    advancedPanelIntroduction(
                        title: "Protect smooth areas",
                        detail: "Keep skies, skin, walls, and other even areas cleaner. Move right to protect more of the image.",
                        systemImage: "shield.lefthalf.filled",
                        tint: .blue
                    )

                    VarianceThresholdControl(
                        sigma: $advancedSigma,
                        histogram: advancedCanvasVM.varianceHistogram,
                        isEnabled: !vm.isEmbedding && !vm.showSuccessOverlay,
                        onLiveSigmaChange: { liveSigma in
                            guard !vm.isEmbedding, !vm.showSuccessOverlay else { return }
                            sigmaLoupeDebouncer.schedule {
                                loupePreviewSigma = liveSigma
                            }
                        },
                        onEditingChanged: { editing in
                            if editing {
                                sigmaLoupeDebouncer.cancel()
                            } else {
                                sigmaLoupeDebouncer.cancel()
                                loupePreviewSigma = advancedSigma
                                advancedGainCurve.maxVariance = advancedSigma * advancedSigma
                            }
                        }
                    )

                    Button {
                        showTextureReferenceGuide = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.subheadline.weight(.semibold))
                            Text("Texture reference guide")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(Color.phantomAccent)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            case .varianceGain:
                VStack(alignment: .leading, spacing: 10) {
                    advancedPanelIntroduction(
                        title: "Balance detail and resilience",
                        detail: "Choose how quickly strength rises with texture. A higher curve survives edits better; a lower curve stays subtler.",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        tint: Color(red: 0.58, green: 0.32, blue: 0.94)
                    )

                    VarianceGainCurveEditor(
                        curve: $advancedGainCurve,
                        varianceSummary: gainCurveSummary,
                        isEnabled: !vm.isEmbedding && !vm.showSuccessOverlay
                    )
                    .task(id: gainSummaryRequest) {
                        await refreshGainCurveSummary()
                    }
                }
            case .intensity:
                VStack(alignment: .leading, spacing: 10) {
                    advancedPanelIntroduction(
                        title: "Set overall strength",
                        detail: "Higher values survive more editing. Lower values are harder to notice.",
                        systemImage: "dial.high",
                        tint: .orange
                    )

                    EmbeddingIntensityControl(
                        intensity: $advancedIntensity,
                        histogram: amplitudeHistogram,
                        isEnabled: !vm.isEmbedding && !vm.showSuccessOverlay,
                        onLiveIntensityChange: { liveIntensity in
                            guard !vm.isEmbedding, !vm.showSuccessOverlay else { return }
                            intensityLoupeDebouncer.schedule {
                                loupePreviewIntensity = liveIntensity
                            }
                        },
                        onEditingChanged: { editing in
                            if editing {
                                intensityLoupeDebouncer.cancel()
                            } else {
                                intensityLoupeDebouncer.cancel()
                                loupePreviewIntensity = advancedIntensity
                            }
                        }
                    )
                    .task(id: amplitudeSummaryRequest) {
                        await refreshAmplitudeHistogram()
                    }
                }
            }
        }
        .disabled(vm.isEmbedding || vm.showSuccessOverlay)
    }

    private func advancedPanelIntroduction(
        title: String,
        detail: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tint.opacity(0.8))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(tint.opacity(0.86))
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 1)
    }

    private var gainSummaryRequest: GainSummaryRequest? {
        guard let photoID = vm.selectedPhotoItems.first?.id,
              advancedCanvasVM.varianceCache != nil else { return nil }
        return GainSummaryRequest(
            photoID: photoID,
            curveKey: advancedCurveWithSigmaCap.packedKey
        )
    }

    private var amplitudeSummaryRequest: AmplitudeSummaryRequest? {
        guard let photoID = vm.selectedPhotoItems.first?.id,
              advancedCanvasVM.varianceCache != nil,
              advancedCanvasVM.baseQCache != nil else { return nil }
        return AmplitudeSummaryRequest(
            photoID: photoID,
            curveKey: advancedCurveWithSigmaCap.packedKey,
            intensityBits: advancedIntensity.bitPattern
        )
    }

    private func refreshGainCurveSummary() async {
        guard gainSummaryRequest != nil,
              let varianceCache = advancedCanvasVM.varianceCache else {
            gainCurveSummary = nil
            return
        }
        let curve = advancedCurveWithSigmaCap

        // Coalesce rapid handle updates before scheduling CPU work.
        try? await Task.sleep(for: .milliseconds(90))
        guard !Task.isCancelled else { return }

        let summary = await Task.detached(priority: .utility) {
            VarianceGainCurveSummary.build(variance: varianceCache, curve: curve)
        }.value
        guard !Task.isCancelled else { return }
        gainCurveSummary = summary
    }

    private func refreshAmplitudeHistogram() async {
        guard amplitudeSummaryRequest != nil,
              let varianceCache = advancedCanvasVM.varianceCache,
              let baseQCache = advancedCanvasVM.baseQCache else {
            amplitudeHistogram = nil
            return
        }
        let curve = advancedCurveWithSigmaCap
        let intensity = Float(advancedIntensity)

        let histogram = await Task.detached(priority: .utility) {
            AmplitudeHistogramSummary.build(
                baseQ: baseQCache,
                variance: varianceCache,
                varianceGainCurve: curve,
                embeddingIntensity: intensity
            )
        }.value
        guard !Task.isCancelled else { return }
        amplitudeHistogram = histogram
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
                                .fill(PhantomTheme.actionGradient)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                                }
                        }
                        .shadow(color: Color.phantomAccent.opacity(0.42), radius: 16, x: 0, y: 8)
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
        UploadedThumbnailStrip(
            items: vm.selectedPhotoItems,
            isManageEnabled: !vm.selectedPhotoItems.isEmpty && !vm.isEmbedding && !vm.showSuccessOverlay,
            onManage: { showOverflowSheet = true }
        )
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Watermark Payload", systemImage: "character.cursor.ibeam")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
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
                        .fill(Color.phantomInputBackground)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }

                HStack(alignment: .bottom, spacing: 12) {
                    Text(payloadHintBelowField)
                        .font(.caption)
                        .foregroundStyle(vm.isPayloadLengthValid ? Color.secondary : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    embedActionButton
                }
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.phantomCardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        }
    }

    private struct TextureReferenceGuideSheet: View {
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Texture reference guide")
                            .font(.title3.weight(.semibold))
                            .padding(.top, 4)

                        guideBlock(
                            title: "σ 0–3 (Aggressive / Maximum Robustness)",
                            body: "Think of: clear blue skies, flat painted walls, or pure white paper. Embeds at full strength almost everywhere for maximum survival, but faint noise (banding) might be visible in completely smooth areas."
                        )
                        guideBlock(
                            title: "σ 4–5.5 (Balanced / Recommended)",
                            body: "Think of: human skin, soft clouds, or gentle shadows. Only perfectly flat regions drop to the gentle low-energy embed while keeping strong redundancy."
                        )
                        guideBlock(
                            title: "σ 7–10 (Conservative / Maximum Invisibility)",
                            body: "Think of: dense foliage, tree bark, brick walls, or pet fur. Extremely subtle, but extraction headroom shrinks on mostly smooth photos since most blocks embed at reduced energy."
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
                }
                .background(Color.phantomPageBackground)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }

        private func guideBlock(title: String, body: String) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.phantomCardBackground)
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
        PhantomTheme.brightActionGradient
    }

    @ViewBuilder
    private var embedFABBackgroundFill: some View {
        let shape = Capsule(style: .continuous)
        if vm.canStartEmbed || vm.isEmbedding {
            shape.fill(embedFABGradient)
        } else {
            shape.fill(Color.phantomElevatedBackground)
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
        embedFABReady ? 14 : (vm.isEmbedding ? 10 : 4)
    }

    private var embedFABShadowY: CGFloat {
        embedFABReady ? 6 : 3
    }

    /// Matches `manageUploadedChip` when there is nothing to open: same fill + dimmed with `0.42` opacity.
    private var embedFABInactiveDimOpacity: Double {
        (embedFABReady || vm.isEmbedding) ? 1.0 : 0.42
    }

    private var embedActionButton: some View {
        Button {
            guard vm.canStartEmbed else { return }
            if isAdvancedMode {
                let overrides = AdvancedEmbedOverrides(
                    varianceGainCurve: advancedCurveWithSigmaCap,
                    embeddingIntensity: advancedIntensity
                )
                Task { await vm.embedWatermark(advancedOverrides: overrides) }
            } else {
                Task { await vm.embedWatermark() }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: vm.isEmbedding ? "hourglass" : "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .symbolEffect(.pulse, options: .repeating, isActive: vm.canStartEmbed && !vm.isEmbedding)
                Text("Embed")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(embedFABIconColor)
        .background { embedFABBackgroundFill }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(embedFABStrokeColor, lineWidth: embedFABReady ? 1.5 : 1)
        }
        .shadow(color: embedFABShadowColor, radius: embedFABShadowRadius, x: 0, y: embedFABShadowY)
        .scaleEffect(embedFABReady ? 1.03 : 1.0)
        .opacity(embedFABInactiveDimOpacity)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: embedFABReady)
        .animation(.easeOut(duration: 0.2), value: vm.isEmbedding)
        .allowsHitTesting(vm.canStartEmbed)
        .accessibilityLabel(
            vm.canStartEmbed
                ? "Insert watermark"
                : "Insert watermark, unavailable until photos and watermark text are valid."
        )
    }
}

// MARK: - Uploaded thumbnail strip

private struct UploadedThumbnailStrip: View {
    let items: [SelectedPhotoItem]
    let isManageEnabled: Bool
    var onManage: () -> Void

    private static let thumbSize: CGFloat = 58
    private static let spacing: CGFloat = 10
    private static let separatorWidth: CGFloat = 1
    private static let separatorLeadingPadding: CGFloat = 10
    private static let stripMinHeight: CGFloat = 62
    private static let scrollableMinCount = 5
    private static let scrollFadeWidth: CGFloat = 6
    private static let cardBackground = Color.phantomCardBackground

    var body: some View {
        Group {
            if items.count < Self.scrollableMinCount {
                inlineLayout
            } else {
                scrollableLayout
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: Self.stripMinHeight + 8)
    }

    /// ≤4 photos: thumbnails and manage chip in one plain row.
    private var inlineLayout: some View {
        HStack(spacing: Self.spacing) {
            ForEach(items) { item in
                thumbnailCell(for: item.image)
            }
            manageButton
        }
        .padding(.vertical, 4)
        .frame(minHeight: Self.stripMinHeight, alignment: .center)
    }

    /// >4 photos: scrollable thumbnails + fixed separator + manage entry.
    private var scrollableLayout: some View {
        HStack(spacing: Self.separatorLeadingPadding) {
            ScrollView(.horizontal) {
                HStack(spacing: Self.spacing) {
                    ForEach(items) { item in
                        thumbnailCell(for: item.image)
                    }
                }
                .padding(.vertical, 4)
                .padding(.trailing, Self.scrollFadeWidth / 2)
                .frame(minHeight: Self.stripMinHeight, alignment: .center)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) {
                scrollTrailingFade
            }

            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: Self.separatorWidth, height: Self.thumbSize)

            manageButton
                .padding(.vertical, 4)
        }
        .frame(minHeight: Self.stripMinHeight, alignment: .center)
    }

    private var scrollTrailingFade: some View {
        LinearGradient(
            colors: [
                Self.cardBackground.opacity(0),
                Self.cardBackground.opacity(0.68),
                Self.cardBackground,
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: Self.scrollFadeWidth)
        .allowsHitTesting(false)
    }

    private var manageButton: some View {
        Button {
            guard isManageEnabled else { return }
            onManage()
        } label: {
            manageUploadedChip(totalCount: items.count)
        }
        .buttonStyle(.plain)
        .disabled(!isManageEnabled)
        .opacity(isManageEnabled ? 1 : 0.42)
        .accessibilityLabel(
            items.isEmpty ? "Manage uploads, no photos selected" : "View all \(items.count) uploads"
        )
    }

    private func manageUploadedChip(totalCount: Int) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.phantomElevatedBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .frame(width: Self.thumbSize, height: Self.thumbSize)
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
                        .background(Circle().fill(Color.phantomAccent))
                        .offset(x: 4, y: -4)
                }
            }
    }

    private func thumbnailCell(for uiImage: UIImage) -> some View {
        Image(uiImage: uiImage)
            .resizable()
            .scaledToFill()
            .frame(width: Self.thumbSize, height: Self.thumbSize)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

#Preview {
    NavigationStack {
        WatermarkInsertView(watermarkService: WatermarkService(), settingsStore: UserSettingsStore())
    }
}
