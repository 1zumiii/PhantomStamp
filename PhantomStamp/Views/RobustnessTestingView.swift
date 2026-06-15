//
//  RobustnessTestingView.swift
//  PhantomStamp
//
//  Internal tools page: runs manual/DEBUG watermark robustness limit tests.
//

import PhotosUI
import SwiftUI
import UIKit

struct RobustnessTestingView: View {
    let watermarkService: any WatermarkServiceProtocol
    @Bindable var settingsStore: UserSettingsStore
    @State private var vm: RobustnessTestingViewModel

    init(settingsStore: UserSettingsStore, watermarkService: any WatermarkServiceProtocol) {
        self.watermarkService = watermarkService
        self.settingsStore = settingsStore
        _vm = State(initialValue: RobustnessTestingViewModel(
            settingsStore: settingsStore,
            watermarkService: watermarkService
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                progressOverlayCard
                imageManipCard
                attackLimitsCard
                geometricCard
                batchCard
                Spacer(minLength: 18)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .background {
            PhantomThemeBackdrop()
        }
        .navigationTitle("Robustness Tests")
        .navigationBarTitleDisplayMode(.large)
        .alert(vm.alertTitle, isPresented: $vm.showAlert) {
            Button("OK", role: .cancel) { vm.dismissAlert() }
        } message: {
            Text(vm.alertMessage)
        }
        .sensoryFeedback(.success, trigger: vm.manipJpegFeedbackTrigger)
        .sensoryFeedback(.success, trigger: vm.manipResizeFeedbackTrigger)
        .sensoryFeedback(.success, trigger: vm.manipScribbleFeedbackTrigger)
        .onChange(of: vm.manipPickerItem) { _, newItem in
            Task { await vm.loadManipSourceImage(from: newItem) }
        }
    }

    // MARK: - Progress overlay

    private var progressOverlayCard: some View {
        card(title: "Progress overlay", systemImage: "hourglass.badge.plus") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Plays the real production overlay one stage at a time. Each message remains on screen for one second.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("Pipeline", selection: $vm.selectedProgressPreviewMode) {
                    ForEach(RobustnessTestingViewModel.ProgressPreviewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(vm.isLoading)

                HStack {
                    Label(
                        "\(vm.selectedProgressPreviewMode.stages.count) stages",
                        systemImage: "text.line.first.and.arrowtriangle.forward"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        Task { await vm.runProgressOverlayPreview() }
                    } label: {
                        HStack(spacing: 6) {
                            if vm.progressPreviewRunning {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.caption.weight(.semibold))
                            }
                            Text(vm.progressPreviewRunning ? "Running" : "Run")
                                .font(.callout.weight(.semibold))
                        }
                        .frame(minWidth: 76)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(vm.isLoading)
                }
            }
        }
    }

    // MARK: - Attack limit sweeps

    private var attackLimitsCard: some View {
        card(title: "Extraction limits", systemImage: "scope") {
            VStack(spacing: 14) {
                limitTestRow(
                    title: "JPEG quality limit",
                    subtitle: "Coarse sweep high→low, then fine drill-down. Saves lowest-pass / first-fail images.",
                    runTitle: "Sweep"
                ) {
                    Task { await vm.runCompressionLimitSweep() }
                }

                Divider().opacity(0.25)

                cropLimitSection
            }
        }
    }

    private var cropLimitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Crop edge limit")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Coarse 50%→0% in 10% steps, then 1% drill-up on the selected edge. Saves boundary crops.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 10)
                Button {
                    Task { await vm.runCropLimitSweep() }
                } label: {
                    Text("Sweep")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(vm.isLoading)
            }

            HStack {
                Text("Direction")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Crop direction", selection: $vm.selectedCropKind) {
                    ForEach(WatermarkCropAttackTests.CropKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .disabled(vm.isLoading)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Geometric

    private var geometricCard: some View {
        card(title: "Geometric detection limits", systemImage: "rotate.3d") {
            VStack(alignment: .leading, spacing: 12) {
                syncTemplateIntensityRow

                Divider().opacity(0.25)

                limitTestRow(
                    title: "Identity baseline",
                    subtitle: "Embed → detect on un-attacked image. Confirms detector returns angle≈0°, scale≈1×.",
                    runTitle: "Run"
                ) {
                    Task { await vm.runSyncTemplateBasicTest() }
                }

                Divider().opacity(0.25)

                limitTestRow(
                    title: "Rotation + scale limit sweep",
                    subtitle: "Coarse outward sweep ± rotation & scale, then fine drill-down to exact breakdown.",
                    runTitle: "Sweep"
                ) {
                    Task { await vm.runSyncTemplateLimitSweep() }
                }
            }
        }
    }

    private var syncTemplateIntensityRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Template intensity")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(String(format: "±%.1f LSB", settingsStore.syncTemplateIntensity))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text("Peak amplitude (LSB per pixel) for `applySpatialTiling`. Higher = stronger FFT peaks but more visible texture.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Slider(
                value: $settingsStore.syncTemplateIntensity,
                in: 0.5...10.0,
                step: 0.5
            )
            .disabled(vm.isLoading)
            .accessibilityValue(String(format: "%.1f", settingsStore.syncTemplateIntensity))
        }
    }

    // MARK: - Batch

    private var batchCard: some View {
        card(title: "Batch stress", systemImage: "square.stack.3d.up") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Multi-file embed (×\(vm.multiFileCount))")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Sequential embed for multiple files. Shows batch progress bar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 10)
                }

                HStack {
                    Text("Images")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    HStack(spacing: 10) {
                        stepperCapsule(
                            value: $vm.multiFileCount,
                            range: 2...6,
                            decrementDisabled: vm.isLoading || vm.multiFileCount <= 2,
                            incrementDisabled: vm.isLoading || vm.multiFileCount >= 6
                        )

                        Button {
                            Task { await vm.runMultiFileEmbedTest(fileCount: vm.multiFileCount) }
                        } label: {
                            Text("Run")
                                .font(.callout.weight(.semibold))
                                .padding(.horizontal, 12)
                        }
                        .frame(width: 80, height: 32)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(vm.isLoading)
                    }
                }
            }
        }
    }

    // MARK: - Image tools

    private var imageManipCard: some View {
        card(title: "Image tools", systemImage: "photo.on.rectangle.angled") {
            VStack(alignment: .leading, spacing: 14) {
                manipImagePickerRow
                manipSourcePreviewRow

                Divider().opacity(0.75)

                manipScribbleSection

                Divider().opacity(0.75)

                manipJpegCompressSection

                Divider().opacity(0.75)

                manipResizeSection
            }
        }
    }

    private var manipImagePickerRow: some View {
        let pickerTitle = vm.manipSourceImage == nil ? "Pick" : "Change"
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Source image")
                    .font(.callout.weight(.semibold))
                Text("Pick one photo. Both tools below operate on this image.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            PhotosPicker(
                selection: $vm.manipPickerItem,
                matching: ImagePickerSupport.imagesOnlyFilter,
                photoLibrary: .shared()
            ) {
                Text(pickerTitle)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(vm.isLoading || vm.manipLoadingImage)
        }
    }

    @ViewBuilder
    private var manipSourcePreviewRow: some View {
        if vm.manipLoadingImage {
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading image…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let img = vm.manipSourceImage, let px = vm.manipSourcePx {
            HStack(spacing: 12) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.manipSourceName ?? "Selected image")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text("\(px.w) × \(px.h) px")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear") {
                    vm.clearManipSourceImage()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        } else {
            Text("No image selected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var manipJpegCompressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("JPEG compress")
                .font(.callout.weight(.semibold))

            Text("Re-encode the source as JPEG at the chosen quality (simulates platform compression). Saves result to Photos.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Quality")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f", ImageCompressionUtils.clampQuality(vm.manipJpegQuality)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: $vm.manipJpegQuality, in: 0.05...0.95, step: 0.05)
                .disabled(vm.isLoading || vm.manipSourceImage == nil)

            HStack {
                Spacer()
                ManipSaveButton(
                    title: "Compress & Save",
                    prominent: true,
                    isRunning: vm.manipJpegRunning,
                    feedback: vm.manipJpegFeedback
                ) {
                    Task { await vm.runManipJpegCompress() }
                }
                .disabled(vm.isLoading || vm.manipSourceImage == nil)
            }
        }
    }

    private var manipScribbleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Random local scribble")
                .font(.callout.weight(.semibold))

            Text("Adds a few short high-contrast curves and saves at exactly the original pixel dimensions. Each run generates a new pattern.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Strokes")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                stepperCapsule(
                    value: $vm.manipScribbleStrokeCount,
                    range: 1...8,
                    decrementDisabled: vm.isLoading || vm.manipScribbleStrokeCount <= 1,
                    incrementDisabled: vm.isLoading || vm.manipScribbleStrokeCount >= 8
                )
            }

            HStack {
                Text("Width")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f%% of short edge", vm.manipScribbleWidthPercent))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: $vm.manipScribbleWidthPercent, in: 0.15...2.0, step: 0.05)
                .disabled(vm.isLoading || vm.manipSourceImage == nil)

            if let src = vm.manipSourcePx {
                Text("Output: \(src.w) × \(src.h) px  (unchanged)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                ManipSaveButton(
                    title: "Scribble & Save",
                    prominent: true,
                    isRunning: vm.manipScribbleRunning,
                    feedback: vm.manipScribbleFeedback
                ) {
                    Task { await vm.runManipRandomScribble() }
                }
                .disabled(vm.isLoading || vm.manipSourceImage == nil)
            }
        }
    }

    private var manipResizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Proportional resize")
                .font(.callout.weight(.semibold))

            Text("Uniformly scale the source image. Aspect ratio is preserved.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Scale")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2fx", vm.manipResizeScaleFactor))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: $vm.manipResizeScaleFactor, in: 0.8...1.6, step: 0.05)
                .disabled(vm.isLoading || vm.manipSourceImage == nil)

            if let preview = vm.manipResizePreviewSize, let src = vm.manipSourcePx {
                Text("Output: \(preview.w) × \(preview.h) px  (from \(src.w) × \(src.h))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                ManipSaveButton(
                    title: "Resize & Save",
                    prominent: false,
                    isRunning: vm.manipResizeRunning,
                    feedback: vm.manipResizeFeedback
                ) {
                    Task { await vm.runManipResize() }
                }
                .disabled(vm.isLoading || vm.manipSourceImage == nil || vm.manipResizePreviewSize == nil)
            }
        }
    }

    // MARK: - Shared UI

    private func limitTestRow(
        title: String,
        subtitle: String,
        runTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            Button(action: action) {
                Text(runTitle)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(vm.isLoading)
        }
        .padding(.vertical, 2)
    }

    private func stepperCapsule(
        value: Binding<Int>,
        range: ClosedRange<Int>,
        decrementDisabled: Bool,
        incrementDisabled: Bool
    ) -> some View {
        HStack(spacing: 4) {
            Button {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
            } label: {
                Image(systemName: "minus")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 24, height: 25)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(decrementDisabled)

            Text("\(value.wrappedValue)")
                .font(.footnote.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 14)

            Button {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
            } label: {
                Image(systemName: "plus")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 24, height: 25)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(incrementDisabled)
        }
        .padding(.horizontal, 0.5)
        .padding(.vertical, 2)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private func card<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.phantomCardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 10)
    }
}

// MARK: - Image tools save button

private struct ManipSaveButton: View {
    let title: String
    let prominent: Bool
    let isRunning: Bool
    let feedback: RobustnessTestingViewModel.ManipSaveFeedback
    var action: () -> Void

    private var isSuccess: Bool { feedback == .success }

    var body: some View {
        Group {
            if prominent {
                Button(action: action) { label }
                    .buttonStyle(.borderedProminent)
            } else {
                Button(action: action) { label }
                    .buttonStyle(.bordered)
            }
        }
        .tint(isSuccess ? .green : nil)
        .controlSize(.small)
        .scaleEffect(isSuccess ? 1.03 : 1.0)
        .animation(.easeInOut(duration: 0.35), value: isRunning)
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: isSuccess)
    }

    private var label: some View {
        HStack(spacing: 6) {
            Group {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else if isSuccess {
                    Image(systemName: "checkmark")
                        .font(.callout.weight(.bold))
                }
            }
            .frame(width: isRunning || isSuccess ? 16 : 0)
            .opacity(isRunning || isSuccess ? 1 : 0)

            Text(isSuccess ? "Saved" : title)
                .font(.callout.weight(.semibold))
                .contentTransition(.interpolate)
        }
        .padding(.horizontal, 12)
    }
}

#Preview {
    NavigationStack {
        RobustnessTestingView(settingsStore: UserSettingsStore(), watermarkService: WatermarkService())
    }
}
