//
//  TestPage.swift
//  PhantomStamp
//
//  Internal tools page: runs manual/DEBUG watermark tests.
//

import SwiftUI
import UIKit

struct RobustnessTestingView: View {
    let watermarkService: any WatermarkServiceProtocol
    @Bindable var settingsStore: UserSettingsStore

    @State private var isLoading = false
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var multiFileCount: Int = 5

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
                Spacer(minLength: 18)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Test Page")
        .navigationBarTitleDisplayMode(.large)
        .alert("Test Failed", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
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
                    title: "Basic round-trip + identity detect",
                    subtitle: "Embed → extract on TestImg, plus `detectGeometricTransforms` on the un-attacked image (expects angle≈0, scale≈1).",
                    runTitle: "Run",
                    style: .prominent
                ) {
                    Task { await runSyncTemplateBasicTest() }
                }

                Divider().opacity(0.25)

                testRow(
                    title: "Rotation + scale limit sweep",
                    subtitle: "Sweeps rotation ±15° and scale 0.85×–1.15×. Reports the largest still-passing attack and saves boundary images.",
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

    private func present(_ message: String) {
        alertMessage = message
        showAlert = true
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

    /// Basic functional check: embed → extract → confirm `detectGeometricTransforms` returns
    /// (≈0°, ≈1×) on the un-attacked watermarked image.
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
        let ok = r.imageLoaded && r.embedSucceeded && r.extractSucceeded
            && r.textRoundTripPassed && r.noAttackDetectedIdentity
        let status = ok ? "PASS" : "FAIL"
        let detAng = r.detectedAngleDegrees.map { String(format: "%.4f°", $0) } ?? "nil"
        let detSc = r.detectedScale.map { String(format: "%.6f", $0) } ?? "nil"
        let px = r.watermarkedPx.map { "\($0.w)x\($0.h)px" } ?? "nil"
        print("[TestPage] SyncTemplateBasic \(status) intensity=\(String(format: "%.2f", intensity)) px=\(px) detected(angle=\(detAng), scale=\(detSc)) extracted=\(r.extractedText ?? "nil") identity=\(r.noAttackDetectedIdentity ? "PASS" : "FAIL")")

        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkProgress,
            object: nil,
            userInfo: ["payload": ProgressPayload(step: .reassembling, percentage: 1)]
        )
        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)

        if !ok {
            present("Sync template basic test failed. extracted=\(r.extractedText ?? "nil") detected(angle=\(detAng), scale=\(detSc))")
        }
    }

    /// Rotation + isotropic-scale sweep. Reports the largest still-passing attack on both axes
    /// and saves the boundary images to the photo library (via the test helper).
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
        print("[TestPage] SyncTemplateSweep \(status) intensity=\(String(format: "%.2f", intensity)) rotationLimit=\(rotLimit) scaleRange=[\(minSc), \(maxSc)] rotCases=\(r.rotationCases.count) scaleCases=\(r.scaleCases.count)")
        // Per-case detail to make tuning iterations easier from the console.
        for c in r.rotationCases {
            let detAng = c.detectedAngleDegrees.map { String(format: "%.3f°", $0) } ?? "nil"
            let detSc = c.detectedScale.map { String(format: "%.4f", $0) } ?? "nil"
            let pass = c.textRoundTripPassed ? "PASS" : "FAIL"
            print("  - rotation \(String(format: "%+6.2f°", c.attackParam)) \(pass) detected(angle=\(detAng), scale=\(detSc)) extracted=\(c.extractedText ?? "nil")")
        }
        for c in r.scaleCases {
            let detAng = c.detectedAngleDegrees.map { String(format: "%.3f°", $0) } ?? "nil"
            let detSc = c.detectedScale.map { String(format: "%.4f", $0) } ?? "nil"
            let pass = c.textRoundTripPassed ? "PASS" : "FAIL"
            print("  - scale    \(String(format: "%5.3fx", c.attackParam)) \(pass) detected(angle=\(detAng), scale=\(detSc)) extracted=\(c.extractedText ?? "nil")")
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

