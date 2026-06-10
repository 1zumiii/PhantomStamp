//
//  TestPage.swift
//  PhantomStamp
//
//  Internal tools page: runs manual/DEBUG watermark tests.
//

import PhotosUI
import SwiftUI
import UIKit

struct RobustnessTestingView: View {
    let watermarkService: any WatermarkServiceProtocol
    @Bindable var settingsStore: UserSettingsStore

    @State private var isLoading = false
    @State private var alertMessage = ""
    @State private var alertTitle = "Test Failed"
    @State private var showAlert = false
    @State private var multiFileCount: Int = 5

    // Image manipulation tools (shared picked source for compress + resize).
    @State private var manipPickerItem: PhotosPickerItem?
    @State private var manipSourceImage: UIImage?
    @State private var manipSourcePx: (w: Int, h: Int)?
    @State private var manipSourceName: String?
    @State private var manipLoadingImage = false

    @State private var manipJpegQuality: Double = 0.60
    @State private var manipResizeTargetText: String = "1920"
    @State private var manipResizeFitMode: ImageResizeUtils.FitMode = .longEdge

    // Geometric (DFT sync template) test parameter.
    // Bound to `settingsStore.syncTemplateIntensity` via the slider in `geometricCard`, which also
    // updates the production embed pipeline (`WatermarkService.embedWatermark` reads the same
    // setting). The robustness tests pass this exact value into their private test binding so the
    // displayed slider value is what actually gets tested.
    private var currentSyncTemplateIntensity: Double { settingsStore.syncTemplateIntensity }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                testsCard
                batchCard
                attacksCard
                compressionCard
                geometricCard
                imageManipCard
                Spacer(minLength: 18)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Test Page")
        .navigationBarTitleDisplayMode(.large)
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .onChange(of: manipPickerItem) { _, newItem in
            Task { await loadManipSourceImage(from: newItem) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Internal tools")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                }

            Text("Watermark robustness tests")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Runs embed/extract validation and common attack simulations. Attacked images are saved to Photos for inspection.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var testsCard: some View {
        card(title: "Core", systemImage: "checkmark.seal") {
            VStack(spacing: 10) {
                testRow(
                    title: "Embed only (TestImg)",
                    subtitle: "Runs embed pipeline + progress timings.",
                    runTitle: "Run",
                    style: .prominent
                ) {
                    Task { await runEmbedOnlyTestOnBundledImage() }
                }

                Divider().opacity(0.25)

                testRow(
                    title: "E2E round-trip (TestImg)",
                    subtitle: "Embed → extract, validates progress events. Saves watermarked image.",
                    runTitle: "Run",
                    style: .normal
                ) {
                    Task { await runEndToEndTestOnBundledImage() }
                }
            }
        }
    }

    private var attacksCard: some View {
        card(title: "Crop attacks", systemImage: "crop") {
            testRow(
                title: "Crop 10% (left / top / right)",
                subtitle: "Saves attacked images to Photos, then extracts watermark.",
                runTitle: "Run",
                style: .normal
            ) {
                Task { await runCropAttackTestOnBundledImage() }
            }
        }
    }

    private var batchCard: some View {
        card(title: "Batch (multi-file)", systemImage: "square.stack.3d.up") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Multi-file embed (×\(multiFileCount))")
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
                        HStack(spacing: 4) {
                            Button {
                                multiFileCount = max(2, multiFileCount - 1)
                            } label: {
                                Image(systemName: "minus")
                                    .font(.footnote.weight(.semibold))
                                    .frame(width: 24, height: 25)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .disabled(isLoading || multiFileCount <= 2)

                            Text("\(multiFileCount)")
                                .font(.footnote.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 14)

                            Button {
                                multiFileCount = min(6, multiFileCount + 1)
                            } label: {
                                Image(systemName: "plus")
                                    .font(.footnote.weight(.semibold))
                                    .frame(width: 24, height: 25)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .disabled(isLoading || multiFileCount >= 6)
                        }
                        .padding(.horizontal, 0.5)
                        .padding(.vertical, 2)
                        .background(.thinMaterial, in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Images count")
                        .accessibilityValue("\(multiFileCount)")

                        Button {
                            Task { await runMultiFileEmbedTestOnBundledImage(fileCount: multiFileCount) }
                        } label: {
                            Text("Run")
                                .font(.callout.weight(.semibold))
                                .padding(.horizontal, 12)
                        }
                        .frame(width: 80, height: 32)
                        .modifier(RunButtonStyleModifier(style: .normal))
                        .controlSize(.small)
                        .disabled(isLoading)
                    }
                }
            }
        }
    }

    private var compressionCard: some View {
        card(title: "Compression attacks", systemImage: "arrow.down.right.and.arrow.up.left") {
            VStack(spacing: 10) {
                testRow(
                    title: "JPEG recompress (q = 0.60)",
                    subtitle: "Saves recompressed image to Photos, then extracts watermark.",
                    runTitle: "Run",
                    style: .normal
                ) {
                    Task { await runCompressionAttackTestOnBundledImage() }
                }

                Divider().opacity(0.25)

                testRow(
                    title: "JPEG limit sweep (auto)",
                    subtitle: "Coarse sweep + binary refinement. Saves boundary images (lowest pass / first fail).",
                    runTitle: "Run",
                    style: .normal
                ) {
                    Task { await runCompressionLimitSweepOnBundledImage() }
                }
            }
        }
    }

    // ==========================================
    // MARK: - Geometric (DFT Sync Template) Card
    // ==========================================
    //
    // Card surfaces the two `SyncTemplateGeometricAttackTests` entry points and a slider that
    // controls the spatial-template ripple intensity (`settingsStore.syncTemplateIntensity`).
    // Higher intensity = stronger FFT peaks (more robust geometric attack detection) but more
    // visible texture on flat areas. The slider value is also what `WatermarkService.embedWatermark`
    // reads in production, so changes here persist across launches.

    private var geometricCard: some View {
        card(title: "Geometric attacks (DFT sync template)", systemImage: "rotate.3d") {
            VStack(alignment: .leading, spacing: 12) {
                syncTemplateIntensityRow

                Divider().opacity(0.25)

                testRow(
                    title: "Identity detection (no attack)",
                    subtitle: "Embed → run `detectGeometricTransforms` on the un-attacked image. PASS iff detector returns angle≈0 and scale≈1 (detector-only — bit extraction not exercised).",
                    runTitle: "Run",
                    style: .prominent
                ) {
                    Task { await runSyncTemplateBasicTest() }
                }

                Divider().opacity(0.25)

                testRow(
                    title: "Rotation + scale detector sweep",
                    subtitle: "Sweeps rotation ±45° and scale 0.60×–1.50× (deliberately beyond the expected operating envelope to find the PASS/FAIL boundary). PASS iff detector recovers params within ±0.5° / ±2%. Top FFT peak printed per case.",
                    runTitle: "Run",
                    style: .normal
                ) {
                    Task { await runSyncTemplateLimitSweep() }
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
                // Live read from settingsStore so the label always matches the slider.
                Text(String(format: "±%.1f LSB", settingsStore.syncTemplateIntensity))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text("Peak amplitude (LSB per pixel) used by `applySpatialTiling`. Higher = stronger FFT peaks but more visible texture.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // Bound directly to settingsStore — persisted via AppUserDefault<Double>.
            Slider(
                value: $settingsStore.syncTemplateIntensity,
                in: 0.5...10.0,
                step: 0.5
            )
            .disabled(isLoading)
            .accessibilityValue(String(format: "%.1f", settingsStore.syncTemplateIntensity))
        }
    }

    // ==========================================
    // MARK: - Image Manipulation Tools
    // ==========================================

    private var imageManipCard: some View {
        card(title: "Image tools", systemImage: "photo.on.rectangle.angled") {
            VStack(alignment: .leading, spacing: 14) {
                manipImagePickerRow
                manipSourcePreviewRow

                Divider().opacity(0.25)

                manipJpegCompressSection

                Divider().opacity(0.25)

                manipResizeSection
            }
        }
    }

    private var manipImagePickerRow: some View {
        HStack(alignment: .center, spacing: 12) {
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
                selection: $manipPickerItem,
                matching: ImagePickerSupport.imagesOnlyFilter,
                photoLibrary: .shared()
            ) {
                Text(manipSourceImage == nil ? "Pick" : "Change")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isLoading || manipLoadingImage)
        }
    }

    @ViewBuilder
    private var manipSourcePreviewRow: some View {
        if manipLoadingImage {
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading image…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let img = manipSourceImage, let px = manipSourcePx {
            HStack(spacing: 12) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(manipSourceName ?? "Selected image")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text("\(px.w) × \(px.h) px")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear") {
                    clearManipSourceImage()
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
                Text(String(format: "%.2f", ImageCompressionUtils.clampQuality(manipJpegQuality)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: $manipJpegQuality, in: 0.05...0.95, step: 0.05)
                .disabled(isLoading || manipSourceImage == nil)

            HStack {
                Spacer()
                Button {
                    Task { await runManipJpegCompress() }
                } label: {
                    Text("Compress & Save")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isLoading || manipSourceImage == nil)
            }
        }
    }

    private var manipResizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Proportional resize")
                .font(.callout.weight(.semibold))

            Text("Scale the source so the chosen edge matches the target pixel count. Aspect ratio is preserved.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Fit by", selection: $manipResizeFitMode) {
                ForEach(ImageResizeUtils.FitMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isLoading || manipSourceImage == nil)

            HStack(spacing: 10) {
                Text("Target")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Pixels", text: $manipResizeTargetText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                    .disabled(isLoading || manipSourceImage == nil)
                Text("px")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if let preview = manipResizePreviewSize, let src = manipSourcePx {
                Text("Output: \(preview.w) × \(preview.h) px  (from \(src.w) × \(src.h))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button {
                    Task { await runManipResize() }
                } label: {
                    Text("Resize & Save")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoading || manipSourceImage == nil || manipResizePreviewSize == nil)
            }
        }
    }

    private var manipResizePreviewSize: (w: Int, h: Int)? {
        guard let px = manipSourcePx,
              let target = Int(manipResizeTargetText.trimmingCharacters(in: .whitespacesAndNewlines)),
              target > 0,
              let out = ImageResizeUtils.previewOutputSize(
                  sourceWidth: px.w,
                  sourceHeight: px.h,
                  targetPixels: target,
                  mode: manipResizeFitMode
              ) else { return nil }
        return (w: out.width, h: out.height)
    }

    // MARK: - Buttons / UI

    private enum RunButtonStyle {
        case prominent
        case normal
    }

    private func testRow(
        title: String,
        subtitle: String,
        runTitle: String,
        style: RunButtonStyle,
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
            .modifier(RunButtonStyleModifier(style: style))
            .controlSize(.small)
            .disabled(isLoading)
        }
        .padding(.vertical, 2)
    }

    private struct RunButtonStyleModifier: ViewModifier {
        let style: RunButtonStyle
        func body(content: Content) -> some View {
            switch style {
            case .prominent:
                content.buttonStyle(.borderedProminent)
            case .normal:
                content.buttonStyle(.bordered)
            }
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
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 10)
    }

    // (removed large, label-heavy buttons; use `testRow` instead)

    // MARK: - Helpers

    @MainActor
    private func saveToSystemPhotoAlbumIfPossible(_ image: UIImage) async {
        guard settingsStore.saveToPhotos else { return }
        do {
            try await PhotoLibraryExporter.saveToPhotoLibrary(image)
        } catch {
            #if DEBUG
            print("[TestPage] Photo save failed: \(error)")
            #endif
        }
    }

    private func present(_ message: String, title: String = "Test Failed") {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    private func presentSuccess(_ message: String) {
        present(message, title: "Done")
    }

    @MainActor
    private func loadManipSourceImage(from item: PhotosPickerItem?) async {
        guard let item else {
            clearManipSourceImage()
            return
        }
        manipLoadingImage = true
        defer { manipLoadingImage = false }

        let loaded = await ImagePickerSupport.loadPickedImages(from: [item])
        guard let first = loaded.first else {
            clearManipSourceImage()
            present("Could not load the selected image.")
            return
        }
        manipSourceImage = first.image
        manipSourcePx = (w: first.width, h: first.height)
        manipSourceName = first.displayName
    }

    private func clearManipSourceImage() {
        manipPickerItem = nil
        manipSourceImage = nil
        manipSourcePx = nil
        manipSourceName = nil
    }

    @MainActor
    private func saveManipResultToPhotos(_ image: UIImage) async throws {
        await PhotoLibraryExporter.preflightAddOnlyAuthorizationIfNeeded()
        try await PhotoLibraryExporter.saveToPhotoLibrary(image)
    }

    private func runManipJpegCompress() async {
        guard let source = manipSourceImage else {
            present("Pick a source image first.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        let q = ImageCompressionUtils.clampQuality(manipJpegQuality)
        guard let result = ImageCompressionUtils.recompressJPEG(image: source, quality: q) else {
            present("JPEG recompression failed.")
            return
        }

        let outPx = pixelSize(of: result.image)
        do {
            try await saveManipResultToPhotos(result.image)
            print("[TestPage] ManipJPEG q=\(String(format: "%.2f", q)) bytes=\(result.jpegBytes) out=\(outPx.w)x\(outPx.h)")
            presentSuccess("Saved to Photos.\nQuality \(String(format: "%.2f", q)), \(result.jpegBytes) bytes, \(outPx.w)×\(outPx.h) px.")
        } catch {
            present("Save failed: \(error.localizedDescription)")
        }
    }

    private func runManipResize() async {
        guard let source = manipSourceImage else {
            present("Pick a source image first.")
            return
        }
        guard let target = Int(manipResizeTargetText.trimmingCharacters(in: .whitespacesAndNewlines)),
              target > 0, target <= 16_384 else {
            present("Enter a target size between 1 and 16384 px.")
            return
        }
        guard let resized = ImageResizeUtils.resize(
            image: source,
            targetPixels: target,
            mode: manipResizeFitMode
        ) else {
            present("Resize failed.")
            return
        }

        let outPx = pixelSize(of: resized)
        do {
            try await saveManipResultToPhotos(resized)
            print("[TestPage] ManipResize mode=\(manipResizeFitMode.rawValue) target=\(target) out=\(outPx.w)x\(outPx.h)")
            presentSuccess("Saved to Photos.\n\(manipResizeFitMode.rawValue) = \(target) px → \(outPx.w)×\(outPx.h) px.")
        } catch {
            present("Save failed: \(error.localizedDescription)")
        }
    }

    private func pixelSize(of image: UIImage) -> (w: Int, h: Int) {
        (Int(image.size.width * image.scale), Int(image.size.height * image.scale))
    }

    // MARK: - Tests

    private func runEndToEndTestOnBundledImage() async {
        isLoading = true
        defer { isLoading = false }

        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidStart, object: nil)
        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkProgress,
            object: nil,
            userInfo: ["payload": ProgressPayload(step: .preparation, percentage: 0.05)]
        )

        let r = await WatermarkEndToEndTests.runAll()
        let ok = r.imageLoaded && r.embedSucceeded && r.extractSucceeded && r.textRoundTripPassed && r.progressPassed
        let status = ok ? "PASS" : "FAIL"
        print("[TestPage] E2E \(status) extracted=\(r.extractedText ?? "nil") events=\(r.progressEventCount)")
        if let watermarked = r.watermarkedImage {
            await saveToSystemPhotoAlbumIfPossible(watermarked)
        }

        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkProgress,
            object: nil,
            userInfo: ["payload": ProgressPayload(step: .reassembling, percentage: 1)]
        )
        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)

        if !ok {
            present("E2E failed. extracted=\(r.extractedText ?? "nil")")
        }
    }

    private func runEmbedOnlyTestOnBundledImage() async {
        isLoading = true
        defer { isLoading = false }

        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidStart, object: nil)
        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkProgress,
            object: nil,
            userInfo: ["payload": ProgressPayload(step: .preparation, percentage: 0.15)]
        )

        let r = await WatermarkEmbedOnlyTests.runOnBundledTestImg(text: "watermark OK")
        let ok = r.imageLoaded && r.embedSucceeded
        let status = ok ? "PASS" : "FAIL"
        print("[TestPage] EmbedOnly \(status) totalMs=\(String(format: "%.2f", r.totalMs)) events=\(r.progressEventCount)")
        for (s, ms) in r.stepTimingsMs {
            print("[TestPage] EmbedOnly step=\(s) ms=\(String(format: "%.2f", ms))")
        }

        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkProgress,
            object: nil,
            userInfo: ["payload": ProgressPayload(step: .reassembling, percentage: 1)]
        )
        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)

        if !ok {
            present("Embed-only test failed.")
        }
    }

    private func runCropAttackTestOnBundledImage() async {
        isLoading = true
        defer { isLoading = false }

        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidStart, object: nil)
        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkProgress,
            object: nil,
            userInfo: ["payload": ProgressPayload(step: .preparation, percentage: 0.05)]
        )

        let r = await WatermarkCropAttackTests.runAllCrop10PercentOnBundledTestImg()
        let ok = r.imageLoaded && !r.cases.isEmpty && r.cases.allSatisfy { $0.embedSucceeded && $0.cropSucceeded && $0.extractSucceeded && $0.textRoundTripPassed }
        print("[TestPage] CropAttack \(ok ? "PASS" : "FAIL") cases=\(r.cases.count)")
        for c in r.cases {
            let cropInfo = c.cropPx.map { "\($0.w)x\($0.h)px" } ?? "nil"
            let caseOk = c.embedSucceeded && c.cropSucceeded && c.extractSucceeded && c.textRoundTripPassed
            print("  - case=\(c.kind.rawValue) \(caseOk ? "PASS" : "FAIL") extracted=\(c.extractedText ?? "nil") crop=\(cropInfo) saved=\(c.saveSucceeded)")
        }

        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkProgress,
            object: nil,
            userInfo: ["payload": ProgressPayload(step: .reassembling, percentage: 1)]
        )
        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)

        if !ok {
            present("Crop attack test failed. See console for details.")
        }
    }

    private func runMultiFileEmbedTestOnBundledImage(fileCount: Int) async {
        isLoading = true
        defer { isLoading = false }

        let r = await WatermarkMultiFileTests.runMultiFileEmbedOnBundledTestImg(text: "Batch watermark OK", fileCount: fileCount)
        let ok = r.imageLoaded && r.embedSucceeded
        let status = ok ? "PASS" : "FAIL"
        print("[TestPage] MultiFileEmbed \(status) files=\(r.fileCount) totalMs=\(String(format: "%.2f", r.totalMs))")

        if let outs = r.outputImages {
            // Save a couple of outputs for quick inspection (best effort).
            if let first = outs.first { await saveToSystemPhotoAlbumIfPossible(first) }
            if outs.count > 1, let last = outs.last { await saveToSystemPhotoAlbumIfPossible(last) }
        }

        if !ok {
            present("Multi-file embed failed.")
        }
    }

    private func runCompressionAttackTestOnBundledImage() async {
        isLoading = true
        defer { isLoading = false }

        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidStart, object: nil)
        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkProgress,
            object: nil,
            userInfo: ["payload": ProgressPayload(step: .preparation, percentage: 0.05)]
        )

        let r = await WatermarkCompressionAttackTests.runMediumJpegCompressionOnBundledTestImg(quality: 0.60)
        let ok = r.imageLoaded && r.embedSucceeded && r.recompressSucceeded && r.extractSucceeded && r.textRoundTripPassed
        let px = r.attackedPx.map { "\($0.w)x\($0.h)px" } ?? "nil"
        let bytes = r.jpegBytes.map(String.init) ?? "nil"
        print("[TestPage] CompressionAttack \(ok ? "PASS" : "FAIL") q=\(String(format: "%.2f", r.quality)) jpegBytes=\(bytes) px=\(px) saved=\(r.saveSucceeded) extracted=\(r.extractedText ?? "nil")")

        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkProgress,
            object: nil,
            userInfo: ["payload": ProgressPayload(step: .reassembling, percentage: 1)]
        )
        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)

        if !ok {
            present("Compression attack test failed. extracted=\(r.extractedText ?? "nil")")
        }
    }

    private func runCompressionLimitSweepOnBundledImage() async {
        isLoading = true
        defer { isLoading = false }

        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidStart, object: nil)
        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkProgress,
            object: nil,
            userInfo: ["payload": ProgressPayload(step: .preparation, percentage: 0.05)]
        )

        let r = await WatermarkCompressionAttackTests.runJpegQualityLimitSweepOnBundledTestImg()
        let ok = r.imageLoaded && r.embedSucceeded && (r.lowestPassingQuality != nil)
        let status = ok ? "PASS" : "FAIL"
        let lowest = r.lowestPassingQuality.map { String(format: "%.2f", $0) } ?? "nil"
        let firstFail = r.firstFailingQuality.map { String(format: "%.2f", $0) } ?? "nil"
        print("[TestPage] CompressionSweep \(status) lowestPass=\(lowest) firstFail=\(firstFail) cases=\(r.cases.count)")

        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkProgress,
            object: nil,
            userInfo: ["payload": ProgressPayload(step: .reassembling, percentage: 1)]
        )
        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)

        if !ok {
            present("Compression sweep failed. lowestPass=\(lowest)")
        }
    }

    // MARK: - Geometric (DFT sync template) tests

    /// Basic detector check: embed → run `detectGeometricTransforms` on the un-attacked image.
    /// PASS criterion is detection accuracy only: angle ≈ 0° and scale ≈ 1×, within the test
    /// module's tolerances. The bit-extraction pipeline is intentionally NOT exercised here so
    /// any failure points directly at the geometric module.
    private func runSyncTemplateBasicTest() async {
        isLoading = true
        defer { isLoading = false }

        // Snapshot the slider value at the point of execution so a mid-run slider change can't
        // produce a misleading report.
        let intensity = currentSyncTemplateIntensity

        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidStart, object: nil)
        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkProgress,
            object: nil,
            userInfo: ["payload": ProgressPayload(step: .preparation, percentage: 0.05)]
        )

        let r = await SyncTemplateGeometricAttackTests.runBasicSyncTemplateOnBundledTestImg(
            syncTemplateIntensity: intensity
        )
        let ok = r.imageLoaded && r.embedSucceeded && r.detectionRan && r.detectedIdentity
        let status = ok ? "PASS" : "FAIL"
        let detAng = r.detectedAngleDegrees.map { String(format: "%.4f°", $0) } ?? "nil"
        let detSc = r.detectedScale.map { String(format: "%.6f", $0) } ?? "nil"
        let px = r.watermarkedPx.map { "\($0.w)x\($0.h)px" } ?? "nil"
        let tolA = SyncTemplateGeometricAttackTests.angleToleranceDegrees
        let tolS = SyncTemplateGeometricAttackTests.scaleRelativeTolerance
        print("[TestPage] SyncTemplateBasic \(status) intensity=\(String(format: "%.2f", intensity)) px=\(px) detected(angle=\(detAng), scale=\(detSc)) tol(|angle|≤\(String(format: "%.2f°", tolA)), |scale-1|≤\(String(format: "%.2f", tolS)))")
        // Top peaks help see whether the template peaks (r≈100, ±45°) actually won the magnitude
        // race vs image-content peaks at other radii.
        for (i, p) in r.topPeaks.enumerated() {
            print("  - peak[\(i)] r=\(String(format: "%6.2f", p.radius)) θ=\(String(format: "%+7.2f°", p.angleDegrees)) (x=\(String(format: "%+6.2f", p.centeredX)), y=\(String(format: "%+6.2f", p.centeredY)))")
        }

        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkProgress,
            object: nil,
            userInfo: ["payload": ProgressPayload(step: .reassembling, percentage: 1)]
        )
        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)

        if !ok {
            present("Sync template basic test failed. detected(angle=\(detAng), scale=\(detSc)). Top peak r=\(r.topPeaks.first.map { String(format: "%.1f", $0.radius) } ?? "nil").")
        }
    }

    /// Rotation + isotropic-scale detector sweep. For each known attack, asks the detector to
    /// recover (angle, scale) and records the numeric error. Reports the largest attack still
    /// inside the detector's tolerance window on each axis.
    private func runSyncTemplateLimitSweep() async {
        isLoading = true
        defer { isLoading = false }

        let intensity = currentSyncTemplateIntensity

        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidStart, object: nil)
        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkProgress,
            object: nil,
            userInfo: ["payload": ProgressPayload(step: .preparation, percentage: 0.05)]
        )

        let r = await SyncTemplateGeometricAttackTests.runRotationAndScaleLimitSweepOnBundledTestImg(
            syncTemplateIntensity: intensity
        )
        let ok = r.imageLoaded && r.embedSucceeded
        let status = ok ? "RAN" : "FAIL"
        let rotLimit = r.maxPassingAbsRotationDegrees.map { String(format: "±%.2f°", $0) } ?? "none"
        let minSc = r.minPassingScaleFactor.map { String(format: "%.3f", $0) } ?? "none"
        let maxSc = r.maxPassingScaleFactor.map { String(format: "%.3f", $0) } ?? "none"
        let tolA = SyncTemplateGeometricAttackTests.angleToleranceDegrees
        let tolS = SyncTemplateGeometricAttackTests.scaleRelativeTolerance
        print("[TestPage] SyncTemplateSweep \(status) intensity=\(String(format: "%.2f", intensity)) rotationLimit=\(rotLimit) scaleRange=[\(minSc), \(maxSc)] tol(|angleErr|≤\(String(format: "%.2f°", tolA)), |scaleRelErr|≤\(String(format: "%.2f", tolS))) rotCases=\(r.rotationCases.count) scaleCases=\(r.scaleCases.count)")

        // Per-case detail with detected values, errors, AND top peaks — makes tuning iterations
        // (intensity, search ring, etc.) easy from the console.
        for c in r.rotationCases {
            let detAng = c.detectedAngleDegrees.map { String(format: "%.3f°", $0) } ?? "nil"
            let detSc = c.detectedScale.map { String(format: "%.4f", $0) } ?? "nil"
            let angErr = c.angleErrorDegrees.map { String(format: "%.3f°", $0) } ?? "nil"
            let scErr = c.scaleRelativeError.map { String(format: "%.4f", $0) } ?? "nil"
            let pass = c.passed ? "PASS" : "FAIL"
            print("  - rotation \(String(format: "%+6.2f°", c.attackParam)) \(pass) detected(angle=\(detAng), scale=\(detSc)) err(angle=\(angErr), scaleRel=\(scErr)) topPeak r=\(c.topPeaks.first.map { String(format: "%.1f", $0.radius) } ?? "nil") θ=\(c.topPeaks.first.map { String(format: "%+.1f°", $0.angleDegrees) } ?? "nil")")
        }
        for c in r.scaleCases {
            let detAng = c.detectedAngleDegrees.map { String(format: "%.3f°", $0) } ?? "nil"
            let detSc = c.detectedScale.map { String(format: "%.4f", $0) } ?? "nil"
            let angErr = c.angleErrorDegrees.map { String(format: "%.3f°", $0) } ?? "nil"
            let scErr = c.scaleRelativeError.map { String(format: "%.4f", $0) } ?? "nil"
            let pass = c.passed ? "PASS" : "FAIL"
            print("  - scale    \(String(format: "%5.3fx", c.attackParam)) \(pass) detected(angle=\(detAng), scale=\(detSc)) err(angle=\(angErr), scaleRel=\(scErr)) topPeak r=\(c.topPeaks.first.map { String(format: "%.1f", $0.radius) } ?? "nil") θ=\(c.topPeaks.first.map { String(format: "%+.1f°", $0.angleDegrees) } ?? "nil")")
        }

        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkProgress,
            object: nil,
            userInfo: ["payload": ProgressPayload(step: .reassembling, percentage: 1)]
        )
        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)

        if !ok {
            present("Sync template limit sweep failed to run (embed or image load failure).")
        }
    }
}

#Preview {
    NavigationStack {
        RobustnessTestingView(watermarkService: WatermarkService(), settingsStore: UserSettingsStore())
    }
}

