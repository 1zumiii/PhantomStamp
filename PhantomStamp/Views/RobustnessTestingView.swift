//
//  TestPage.swift
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
    @State private var manipResultSheet: ManipResultSheetModel?
    @State private var selectedCropKind: WatermarkCropAttackTests.CropKind = .right

    private var currentSyncTemplateIntensity: Double { settingsStore.syncTemplateIntensity }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Robustness Tests")
        .navigationBarTitleDisplayMode(.large)
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .sheet(item: $manipResultSheet) { model in
            ManipResultSheet(model: model) {
                manipResultSheet = nil
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: manipPickerItem) { _, newItem in
            Task { await loadManipSourceImage(from: newItem) }
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
                    Task { await runCompressionLimitSweepOnBundledImage() }
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
                    Task { await runCropLimitSweepOnBundledImage() }
                } label: {
                    Text("Sweep")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoading)
            }

            HStack {
                Text("Direction")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Crop direction", selection: $selectedCropKind) {
                    ForEach(WatermarkCropAttackTests.CropKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isLoading)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Geometric (DFT sync template)

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
                    Task { await runSyncTemplateBasicTest() }
                }

                Divider().opacity(0.25)

                limitTestRow(
                    title: "Rotation + scale limit sweep",
                    subtitle: "Coarse outward sweep ± rotation & scale, then fine drill-down to exact breakdown.",
                    runTitle: "Sweep"
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
            .disabled(isLoading)
            .accessibilityValue(String(format: "%.1f", settingsStore.syncTemplateIntensity))
        }
    }

    // MARK: - Batch

    private var batchCard: some View {
        card(title: "Batch stress", systemImage: "square.stack.3d.up") {
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
                        stepperCapsule(
                            value: $multiFileCount,
                            range: 2...6,
                            decrementDisabled: isLoading || multiFileCount <= 2,
                            incrementDisabled: isLoading || multiFileCount >= 6
                        )

                        Button {
                            Task { await runMultiFileEmbedTestOnBundledImage(fileCount: multiFileCount) }
                        } label: {
                            Text("Run")
                                .font(.callout.weight(.semibold))
                                .padding(.horizontal, 12)
                        }
                        .frame(width: 80, height: 32)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isLoading)
                    }
                }
            }
        }
    }

    // MARK: - Image manipulation tools

    private var imageManipCard: some View {
        card(title: "Image tools", systemImage: "photo.on.rectangle.angled") {
            VStack(alignment: .leading, spacing: 14) {
                manipImagePickerRow
                manipSourcePreviewRow

                Divider().opacity(0.75)

                manipJpegCompressSection

                Divider().opacity(0.75)

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
            .disabled(isLoading)
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
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 10)
    }

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

    private func presentManipSuccess(
        title: String,
        subtitle: String,
        details: [(label: String, value: String)]
    ) {
        manipResultSheet = ManipResultSheetModel(
            isSuccess: true,
            title: title,
            subtitle: subtitle,
            details: details.map { ManipResultSheetModel.Detail(label: $0.label, value: $0.value) }
        )
    }

    private func presentManipFailure(title: String, subtitle: String) {
        manipResultSheet = ManipResultSheetModel(
            isSuccess: false,
            title: title,
            subtitle: subtitle,
            details: []
        )
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
            presentManipFailure(title: "Could not load image", subtitle: "The selected photo could not be decoded.")
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
            presentManipFailure(title: "No source image", subtitle: "Pick a photo in Image tools before compressing.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        let q = ImageCompressionUtils.clampQuality(manipJpegQuality)
        guard let result = ImageCompressionUtils.recompressJPEG(image: source, quality: q) else {
            presentManipFailure(title: "Compression failed", subtitle: "JPEG re-encoding did not produce a valid image.")
            return
        }

        let outPx = pixelSize(of: result.image)
        do {
            try await saveManipResultToPhotos(result.image)
            print("[TestPage] ManipJPEG q=\(String(format: "%.2f", q)) bytes=\(result.jpegBytes) out=\(outPx.w)x\(outPx.h)")
            presentManipSuccess(
                title: "Saved to Photos",
                subtitle: "JPEG recompression finished successfully.",
                details: [
                    ("Quality", String(format: "%.2f", q)),
                    ("File size", "\(result.jpegBytes) bytes"),
                    ("Output", "\(outPx.w) × \(outPx.h) px"),
                ]
            )
        } catch {
            presentManipFailure(title: "Save failed", subtitle: error.localizedDescription)
        }
    }

    private func runManipResize() async {
        guard let source = manipSourceImage else {
            presentManipFailure(title: "No source image", subtitle: "Pick a photo in Image tools before resizing.")
            return
        }
        guard let target = Int(manipResizeTargetText.trimmingCharacters(in: .whitespacesAndNewlines)),
              target > 0, target <= 16_384 else {
            presentManipFailure(title: "Invalid target size", subtitle: "Enter a value between 1 and 16384 px.")
            return
        }
        guard let resized = ImageResizeUtils.resize(
            image: source,
            targetPixels: target,
            mode: manipResizeFitMode
        ) else {
            presentManipFailure(title: "Resize failed", subtitle: "Could not scale the image with the current settings.")
            return
        }

        let outPx = pixelSize(of: resized)
        do {
            try await saveManipResultToPhotos(resized)
            print("[TestPage] ManipResize mode=\(manipResizeFitMode.rawValue) target=\(target) out=\(outPx.w)x\(outPx.h)")
            presentManipSuccess(
                title: "Saved to Photos",
                subtitle: "Proportional resize finished successfully.",
                details: [
                    ("Fit mode", manipResizeFitMode.rawValue),
                    ("Target", "\(target) px"),
                    ("Output", "\(outPx.w) × \(outPx.h) px"),
                ]
            )
        } catch {
            presentManipFailure(title: "Save failed", subtitle: error.localizedDescription)
        }
    }

    private func pixelSize(of image: UIImage) -> (w: Int, h: Int) {
        (Int(image.size.width * image.scale), Int(image.size.height * image.scale))
    }

    // MARK: - Limit sweep runners

    private func postProgressOverlayStart() {
        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidStart, object: nil)
        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkProgress,
            object: nil,
            userInfo: ["payload": ProgressPayload(step: .preparation, percentage: 0.05)]
        )
    }

    private func postProgressOverlayEnd() {
        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkProgress,
            object: nil,
            userInfo: ["payload": ProgressPayload(step: .reassembling, percentage: 1)]
        )
        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)
    }

    private func runCompressionLimitSweepOnBundledImage() async {
        isLoading = true
        defer { isLoading = false }

        postProgressOverlayStart()

        let r = await WatermarkCompressionAttackTests.runJpegQualityLimitSweepOnBundledTestImg()
        let ok = r.imageLoaded && r.embedSucceeded && (r.lowestPassingQuality != nil)
        let status = ok ? "PASS" : "FAIL"
        let lowest = r.lowestPassingQuality.map { String(format: "%.2f", $0) } ?? "nil"
        let firstFail = r.firstFailingQuality.map { String(format: "%.2f", $0) } ?? "nil"
        print("[TestPage] CompressionSweep \(status) lowestPass=\(lowest) firstFail=\(firstFail) cases=\(r.cases.count)")
        for c in r.cases {
            let mark = c.passed ? "PASS" : "FAIL"
            print("  - q=\(String(format: "%.2f", c.quality)) \(mark) extracted=\(c.extractedText ?? "nil") bytes=\(c.jpegBytes)")
        }

        postProgressOverlayEnd()

        if !ok {
            present("Compression sweep failed. lowestPass=\(lowest)")
        }
    }

    private func runCropLimitSweepOnBundledImage() async {
        isLoading = true
        defer { isLoading = false }

        postProgressOverlayStart()

        let r = await WatermarkCropAttackTests.runCropPercentLimitSweepOnBundledTestImg(kind: selectedCropKind)
        let ok = r.imageLoaded && r.embedSucceeded
        let status = ok ? "RAN" : "FAIL"
        let maxPass = r.maxPassingCropPercent.map { String(format: "%.1f%%", $0 * 100) } ?? "none"
        let firstFail = r.firstFailingCropPercent.map { String(format: "%.1f%%", $0 * 100) } ?? "none"
        print("[TestPage] CropSweep \(status) kind=\(r.kind.displayName) maxPass=\(maxPass) firstFail=\(firstFail) cases=\(r.cases.count)")
        for c in r.cases {
            let mark = c.passed ? "PASS" : "FAIL"
            let px = c.cropPx.map { "\($0.w)x\($0.h)" } ?? "nil"
            print("  - crop=\(String(format: "%.1f%%", c.cropPercent * 100)) \(mark) px=\(px) extracted=\(c.extractedText ?? "nil")")
        }

        postProgressOverlayEnd()

        if !ok {
            present("Crop limit sweep failed to run (image load or embed failure).")
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
            if let first = outs.first { await saveToSystemPhotoAlbumIfPossible(first) }
            if outs.count > 1, let last = outs.last { await saveToSystemPhotoAlbumIfPossible(last) }
        }

        if !ok {
            present("Multi-file embed failed.")
        }
    }

    // MARK: - Geometric tests

    private func runSyncTemplateBasicTest() async {
        isLoading = true
        defer { isLoading = false }

        let intensity = currentSyncTemplateIntensity

        postProgressOverlayStart()

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
        for (i, p) in r.topPeaks.enumerated() {
            print("  - peak[\(i)] r=\(String(format: "%6.2f", p.radius)) θ=\(String(format: "%+7.2f°", p.angleDegrees)) (x=\(String(format: "%+6.2f", p.centeredX)), y=\(String(format: "%+6.2f", p.centeredY)))")
        }

        postProgressOverlayEnd()

        if !ok {
            present("Sync template basic test failed. detected(angle=\(detAng), scale=\(detSc)). Top peak r=\(r.topPeaks.first.map { String(format: "%.1f", $0.radius) } ?? "nil").")
        }
    }

    private func runSyncTemplateLimitSweep() async {
        isLoading = true
        defer { isLoading = false }

        let intensity = currentSyncTemplateIntensity

        postProgressOverlayStart()

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

        postProgressOverlayEnd()

        if !ok {
            present("Sync template limit sweep failed to run (embed or image load failure).")
        }
    }
}

// MARK: - Image tools result sheet

private struct ManipResultSheetModel: Identifiable {
    struct Detail: Identifiable {
        let id = UUID()
        var label: String
        var value: String
    }

    let id = UUID()
    var isSuccess: Bool
    var title: String
    var subtitle: String
    var details: [Detail]
}

private struct ManipResultSheet: View {
    let model: ManipResultSheetModel
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.primary.opacity(0.18))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 18)

            VStack(spacing: 14) {
                Image(systemName: model.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(
                        model.isSuccess ? .green : .orange,
                        Color.primary.opacity(0.12)
                    )
                    .symbolRenderingMode(.palette)

                VStack(spacing: 6) {
                    Text(model.title)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(model.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 8)

                if !model.details.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(model.details.enumerated()), id: \.element.id) { index, row in
                            HStack {
                                Text(row.label)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(row.value)
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            if index < model.details.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                    }
                }
            }
            .padding(.horizontal, 22)

            Spacer(minLength: 12)

            Button(action: onDismiss) {
                Text("Done")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 22)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

#Preview {
    NavigationStack {
        RobustnessTestingView(watermarkService: WatermarkService(), settingsStore: UserSettingsStore())
    }
}
