//
//  RobustnessTestingViewModel.swift
//  PhantomStamp
//
//  State + orchestration for the internal robustness / limit-test page.
//

import Observation
import PhotosUI
import SwiftUI
import UIKit

@MainActor
@Observable
final class RobustnessTestingViewModel {
    enum ProgressPreviewMode: String, CaseIterable, Identifiable {
        case embedding = "Embed"
        case extraction = "Extract"

        var id: Self { self }

        var stages: [AppConstants.WatermarkStep] {
            switch self {
            case .embedding:
                return [
                    .preparation,
                    .colorConversion,
                    .processingStrips,
                    .reassembling,
                    .rgbRebuild,
                ]
            case .extraction:
                return [
                    .extractPreparation,
                    .extractConvertToYCbCr,
                    .extractDetectTransforms,
                    .extractOffsetScan,
                    .extractBitGrid,
                    .extractDecodeFEC,
                ]
            }
        }
    }

    enum ManipSaveFeedback: Equatable {
        case idle
        case success
    }

    enum ManipTool {
        case jpeg
        case resize
        case scribble
    }

    let settingsStore: UserSettingsStore
    let watermarkService: WatermarkService

    var isLoading = false
    var alertTitle = "Test Failed"
    var alertMessage = ""
    var showAlert = false
    var multiFileCount = 5
    var selectedProgressPreviewMode: ProgressPreviewMode = .embedding
    var progressPreviewRunning = false

    var manipPickerItem: PhotosPickerItem?
    var manipSourceImage: UIImage?
    var manipSourcePx: (w: Int, h: Int)?
    var manipSourceName: String?
    var manipLoadingImage = false

    var manipJpegQuality = 0.60
    var manipResizeScaleFactor = 1.0
    var manipScribbleStrokeCount = 2
    var manipScribbleWidthPercent = 0.60
    var manipJpegRunning = false
    var manipResizeRunning = false
    var manipScribbleRunning = false
    var manipJpegFeedback: ManipSaveFeedback = .idle
    var manipResizeFeedback: ManipSaveFeedback = .idle
    var manipScribbleFeedback: ManipSaveFeedback = .idle
    var manipJpegFeedbackTrigger = 0
    var manipResizeFeedbackTrigger = 0
    var manipScribbleFeedbackTrigger = 0
    var selectedCropKind: WatermarkCropAttackTests.CropKind = .right

    var currentSyncTemplateIntensity: Double { settingsStore.syncTemplateIntensity }

    init(settingsStore: UserSettingsStore, watermarkService: any WatermarkServiceProtocol) {
        self.settingsStore = settingsStore
        guard let svc = watermarkService as? WatermarkService else {
            fatalError("RobustnessTestingViewModel requires WatermarkService")
        }
        self.watermarkService = svc
    }

    var manipResizePreviewSize: (w: Int, h: Int)? {
        guard let px = manipSourcePx else { return nil }
        guard let out = ImageResizeUtils.previewOutputSize(
            sourceWidth: px.w,
            sourceHeight: px.h,
            scaleFactor: manipResizeScaleFactor
        ) else { return nil }
        return (w: out.width, h: out.height)
    }

    func dismissAlert() {
        showAlert = false
    }

    func clearManipSourceImage() {
        manipPickerItem = nil
        manipSourceImage = nil
        manipSourcePx = nil
        manipSourceName = nil
    }

    func loadManipSourceImage(from item: PhotosPickerItem?) async {
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

    func runManipJpegCompress() async {
        guard let source = manipSourceImage else {
            presentManipFailure(title: "No source image", subtitle: "Pick a photo in Image tools before compressing.")
            return
        }

        manipJpegRunning = true
        isLoading = true
        let runStarted = ContinuousClock.now
        defer { isLoading = false }

        let q = ImageCompressionUtils.clampQuality(manipJpegQuality)
        guard let result = ImageCompressionUtils.recompressJPEG(image: source, quality: q) else {
            manipJpegRunning = false
            presentManipFailure(title: "Compression failed", subtitle: "JPEG re-encoding did not produce a valid image.")
            return
        }

        let outPx = pixelSize(of: result.image)
        do {
            try await saveManipResultToPhotos(result.image)
            print("[TestPage] ManipJPEG q=\(String(format: "%.2f", q)) bytes=\(result.jpegBytes) out=\(outPx.w)x\(outPx.h)")
            await finishManipSaveRun(.jpeg, started: runStarted)
        } catch {
            manipJpegRunning = false
            presentManipFailure(title: "Save failed", subtitle: error.localizedDescription)
        }
    }

    func runManipResize() async {
        guard let source = manipSourceImage else {
            presentManipFailure(title: "No source image", subtitle: "Pick a photo in Image tools before resizing.")
            return
        }
        guard let resized = ImageResizeUtils.resize(image: source, scaleFactor: manipResizeScaleFactor) else {
            presentManipFailure(title: "Resize failed", subtitle: "Could not scale the image with the current factor.")
            return
        }

        manipResizeRunning = true
        isLoading = true
        let runStarted = ContinuousClock.now
        defer { isLoading = false }

        let outPx = pixelSize(of: resized)
        do {
            try await saveManipResultToPhotos(resized)
            print("[TestPage] ManipResize scale=\(String(format: "%.2f", manipResizeScaleFactor)) out=\(outPx.w)x\(outPx.h)")
            await finishManipSaveRun(.resize, started: runStarted)
        } catch {
            manipResizeRunning = false
            presentManipFailure(title: "Save failed", subtitle: error.localizedDescription)
        }
    }

    func runManipRandomScribble() async {
        guard let source = manipSourceImage, let sourcePx = manipSourcePx else {
            presentManipFailure(title: "No source image", subtitle: "Pick a photo in Image tools before adding scribbles.")
            return
        }

        manipScribbleRunning = true
        isLoading = true
        let runStarted = ContinuousClock.now
        defer { isLoading = false }

        guard let result = RandomScribbleUtils.applyingRandomScribbles(
            to: source,
            strokeCount: manipScribbleStrokeCount,
            widthPercent: manipScribbleWidthPercent
        ) else {
            manipScribbleRunning = false
            presentManipFailure(title: "Scribble failed", subtitle: "Could not render the damaged image.")
            return
        }

        let outPx = pixelSize(of: result)
        guard outPx.w == sourcePx.w, outPx.h == sourcePx.h else {
            manipScribbleRunning = false
            presentManipFailure(
                title: "Size changed unexpectedly",
                subtitle: "Expected \(sourcePx.w) × \(sourcePx.h) px, got \(outPx.w) × \(outPx.h) px."
            )
            return
        }

        do {
            try await saveManipResultToPhotos(result)
            print(
                "[TestPage] ManipScribble strokes=\(manipScribbleStrokeCount) "
                    + "width=\(String(format: "%.2f%%", manipScribbleWidthPercent)) "
                    + "out=\(outPx.w)x\(outPx.h)"
            )
            await finishManipSaveRun(.scribble, started: runStarted)
        } catch {
            manipScribbleRunning = false
            presentManipFailure(title: "Save failed", subtitle: error.localizedDescription)
        }
    }

    func runProgressOverlayPreview() async {
        guard !isLoading, !progressPreviewRunning else { return }

        isLoading = true
        progressPreviewRunning = true
        let mode = selectedProgressPreviewMode
        let stages = mode.stages

        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkProgressOverlayDidStart,
            object: nil
        )

        defer {
            NotificationCenter.default.post(
                name: AppConstants.Notifications.watermarkProgressOverlayDidEnd,
                object: nil
            )
            progressPreviewRunning = false
            isLoading = false
        }

        // Give SwiftUI one frame to present the real production overlay before playback.
        try? await Task.sleep(for: .milliseconds(120))

        for (index, step) in stages.enumerated() {
            guard !Task.isCancelled else { return }

            // Keep the final stage below 100% during its one-second showcase.
            // The production overlay automatically begins completion as soon as 1.0 is queued.
            let percentage = Double(index + 1) / Double(stages.count + 1)
            postProgressPreview(step: step, percentage: percentage)
            try? await Task.sleep(for: .seconds(1))
        }

        guard !Task.isCancelled, let finalStep = stages.last else { return }
        postProgressPreview(step: finalStep, percentage: 1.0)
        try? await Task.sleep(for: .milliseconds(350))
    }

    func runCompressionLimitSweep() async {
        await runTest(kind: .compressionLimit) {
            RobustnessTestProgress.post(.compressionLimit, phase: "Embedding reference image…", percentage: 0.08)
            let r = await WatermarkCompressionAttackTests.runJpegQualityLimitSweepOnBundledTestImg(
                service: watermarkService,
                settingsStore: settingsStore
            )
            RobustnessTestProgress.post(.compressionLimit, phase: "Analyzing sweep results…", percentage: 0.92)

            let ok = r.imageLoaded && r.embedSucceeded && r.identityExtractPassed && (r.lowestPassingQuality != nil)
            let lowest = r.lowestPassingQuality.map { String(format: "%.2f", $0) } ?? "none"
            let firstFail = r.firstFailingQuality.map { String(format: "%.2f", $0) } ?? "none"
            print("[TestPage] CompressionSweep \(ok ? "PASS" : "FAIL") identity=\(r.identityExtractPassed ? "PASS" : "FAIL") lowestPass=\(lowest) firstFail=\(firstFail) cases=\(r.cases.count)")
            for c in r.cases {
                let mark = c.passed ? "PASS" : "FAIL"
                print("  - q=\(String(format: "%.2f", c.quality)) \(mark) extracted=\(c.extractedText ?? "nil") bytes=\(c.jpegBytes)")
            }

            if !ok {
                present("Compression sweep failed. lowestPass=\(lowest)")
            }
            return TestRunResult(
                success: ok,
                summary: "Lowest pass q=\(lowest), first fail q=\(firstFail) (\(r.cases.count) cases)."
            )
        }
    }

    func runCropLimitSweep() async {
        await runTest(kind: .cropLimit) {
            RobustnessTestProgress.post(.cropLimit, phase: "Embedding reference image…", percentage: 0.08)
            let r = await WatermarkCropAttackTests.runCropPercentLimitSweepOnBundledTestImg(
                service: watermarkService,
                settingsStore: settingsStore,
                kind: selectedCropKind
            )
            RobustnessTestProgress.post(.cropLimit, phase: "Analyzing \(selectedCropKind.displayName) edge…", percentage: 0.92)

            let ok = r.imageLoaded && r.embedSucceeded && r.identityExtractPassed
            let maxPass = r.maxPassingCropPercent.map { String(format: "%.1f%%", $0 * 100) } ?? "none"
            let firstFail = r.firstFailingCropPercent.map { String(format: "%.1f%%", $0 * 100) } ?? "none"
            print("[TestPage] CropSweep \(ok ? "PASS" : "FAIL") identity=\(r.identityExtractPassed ? "PASS" : "FAIL") kind=\(r.kind.displayName) maxPass=\(maxPass) firstFail=\(firstFail) cases=\(r.cases.count)")
            for c in r.cases {
                let mark = c.passed ? "PASS" : "FAIL"
                let px = c.cropPx.map { "\($0.w)x\($0.h)" } ?? "nil"
                print("  - crop=\(String(format: "%.1f%%", c.cropPercent * 100)) \(mark) px=\(px) extracted=\(c.extractedText ?? "nil")")
            }

            if !ok {
                present("Crop limit sweep failed to run (image load or embed failure).")
            }
            return TestRunResult(
                success: ok,
                summary: "\(selectedCropKind.displayName): max pass \(maxPass), first fail \(firstFail)."
            )
        }
    }

    func runMultiFileEmbedTest(fileCount: Int) async {
        await runTest(kind: .multiFileEmbed) {
            RobustnessTestProgress.post(.multiFileEmbed, phase: "Preparing \(fileCount) images…", percentage: 0.05)
            let r = await WatermarkMultiFileTests.runMultiFileEmbedOnBundledTestImg(text: "Batch watermark OK", fileCount: fileCount)
            RobustnessTestProgress.post(.multiFileEmbed, phase: "Finalizing batch…", percentage: 0.95)

            let ok = r.imageLoaded && r.embedSucceeded
            print("[TestPage] MultiFileEmbed \(ok ? "PASS" : "FAIL") files=\(r.fileCount) totalMs=\(String(format: "%.2f", r.totalMs))")            
            if let outs = r.outputImages {
                if let first = outs.first { await saveToSystemPhotoAlbumIfPossible(first) }
                if outs.count > 1, let last = outs.last { await saveToSystemPhotoAlbumIfPossible(last) }
            }

            if !ok {
                present("Multi-file embed failed.")
            }
            return TestRunResult(
                success: ok,
                summary: "Embedded \(r.fileCount) file(s) in \(String(format: "%.1f", r.totalMs)) ms."
            )
        }
    }

    func runSyncTemplateBasicTest() async {
        let intensity = currentSyncTemplateIntensity
        await runTest(kind: .syncTemplateBasic) {
            RobustnessTestProgress.post(.syncTemplateBasic, phase: "Embedding with template intensity \(String(format: "%.1f", intensity))…", percentage: 0.15)
            let r = await SyncTemplateGeometricAttackTests.runBasicSyncTemplateOnBundledTestImg(syncTemplateIntensity: intensity)
            RobustnessTestProgress.post(.syncTemplateBasic, phase: "Running identity detector…", percentage: 0.85)

            let ok = r.imageLoaded && r.embedSucceeded && r.detectionRan && r.detectedIdentity
            let detAng = r.detectedAngleDegrees.map { String(format: "%.4f°", $0) } ?? "nil"
            let detSc = r.detectedScale.map { String(format: "%.6f", $0) } ?? "nil"
            print("[TestPage] SyncTemplateBasic \(ok ? "PASS" : "FAIL") intensity=\(String(format: "%.2f", intensity)) detected(angle=\(detAng), scale=\(detSc))")     
            for (i, p) in r.topPeaks.enumerated() {
                print("  - peak[\(i)] r=\(String(format: "%6.2f", p.radius)) θ=\(String(format: "%+7.2f°", p.angleDegrees))")
            }

            if !ok {
                present("Sync template basic test failed. detected(angle=\(detAng), scale=\(detSc)).")
            }
            return TestRunResult(
                success: ok,
                summary: "Detected angle=\(detAng), scale=\(detSc) at ±\(String(format: "%.1f", intensity)) LSB."
            )
        }
    }

    func runSyncTemplateLimitSweep() async {
        let intensity = currentSyncTemplateIntensity
        await runTest(kind: .syncTemplateSweep) {
            RobustnessTestProgress.post(.syncTemplateSweep, phase: "Embedding reference image…", percentage: 0.06)
            let r = await SyncTemplateGeometricAttackTests.runRotationAndScaleLimitSweepOnBundledTestImg(syncTemplateIntensity: intensity)
            RobustnessTestProgress.post(.syncTemplateSweep, phase: "Aggregating rotation & scale limits…", percentage: 0.94)

            let ok = r.imageLoaded && r.embedSucceeded
            let rotLimit = r.maxPassingAbsRotationDegrees.map { String(format: "±%.2f°", $0) } ?? "none"
            let minSc = r.minPassingScaleFactor.map { String(format: "%.3f", $0) } ?? "none"
            let maxSc = r.maxPassingScaleFactor.map { String(format: "%.3f", $0) } ?? "none"
            print("[TestPage] SyncTemplateSweep \(ok ? "RAN" : "FAIL") rotationLimit=\(rotLimit) scaleRange=[\(minSc), \(maxSc)]")            
            for c in r.rotationCases {
                let pass = c.passed ? "PASS" : "FAIL"
                print("  - rotation \(String(format: "%+6.2f°", c.attackParam)) \(pass)")
            }
            for c in r.scaleCases {
                let pass = c.passed ? "PASS" : "FAIL"
                print("  - scale \(String(format: "%5.3fx", c.attackParam)) \(pass)")
            }
            if !ok {
            present("Sync template limit sweep failed to run (embed or image load failure).")
            }
                        return TestRunResult(
                success: ok,
                summary: "Rotation \(rotLimit), scale [\(minSc), \(maxSc)]."
            )
        }
    }

    // MARK: - Private

    private struct TestRunResult {
        var success: Bool
        var summary: String
    }
    private func runTest(
        kind: RobustnessTestProgressPayload.Kind,
        operation: () async -> TestRunResult
    ) async {
        isLoading = true
        defer { isLoading = false }

        RobustnessTestProgress.start(kind)
        defer { RobustnessTestProgress.end() }

        let result = await operation()
        RobustnessTestProgress.post(kind, phase: "Complete", percentage: 1.0)
        await deliverTestResultNotificationIfAllowed(kind: kind, result: result)
    }

    private func deliverTestResultNotificationIfAllowed(
        kind: RobustnessTestProgressPayload.Kind,
        result: TestRunResult
    ) async {
        guard settingsStore.watermarkOperationNotificationsEnabled else { return }
        await WatermarkOperationNotificationService.notifyRobustnessTestFinished(
            testName: kind.rawValue,
            success: result.success,
            summary: result.summary
        )
    }


    private func present(_ message: String, title: String = "Test Failed") {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    private func postProgressPreview(step: AppConstants.WatermarkStep, percentage: Double) {
        let payload = ProgressPayload(
            step: step,
            percentage: min(max(percentage, 0), 1)
        )
        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkProgress,
            object: nil,
            userInfo: ["payload": payload]
        )
    }

    private static let manipSaveMinRunningDuration: Duration = .milliseconds(500)

    private func finishManipSaveRun(_ tool: ManipTool, started: ContinuousClock.Instant) async {
        let elapsed = started.duration(to: .now)
        if elapsed < Self.manipSaveMinRunningDuration {
            try? await Task.sleep(for: Self.manipSaveMinRunningDuration - elapsed)
        }

        switch tool {
        case .jpeg: manipJpegRunning = false
        case .resize: manipResizeRunning = false
        case .scribble: manipScribbleRunning = false
        }
        flashManipSaveSuccess(tool)
    }

    private func flashManipSaveSuccess(_ tool: ManipTool) {
        switch tool {
        case .jpeg:
            manipJpegFeedback = .success
            manipJpegFeedbackTrigger += 1
        case .resize:
            manipResizeFeedback = .success
            manipResizeFeedbackTrigger += 1
        case .scribble:
            manipScribbleFeedback = .success
            manipScribbleFeedbackTrigger += 1
        }

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            switch tool {
            case .jpeg where manipJpegFeedback == .success:
                manipJpegFeedback = .idle
            case .resize where manipResizeFeedback == .success:
                manipResizeFeedback = .idle
            case .scribble where manipScribbleFeedback == .success:
                manipScribbleFeedback = .idle
            default:
                break
            }
        }
    }

    private func presentManipFailure(title: String, subtitle: String) {
        present(subtitle, title: title)
    }

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

    private func saveManipResultToPhotos(_ image: UIImage) async throws {
        await PhotoLibraryExporter.preflightAddOnlyAuthorizationIfNeeded()
        try await PhotoLibraryExporter.saveToPhotoLibrary(image)
    }

    private func pixelSize(of image: UIImage) -> (w: Int, h: Int) {
        (Int(image.size.width * image.scale), Int(image.size.height * image.scale))
    }
}

// MARK: - Test progress notifications

enum RobustnessTestProgress {
    static func start(_ kind: RobustnessTestProgressPayload.Kind) {
        post(kind, phase: "Starting…", percentage: 0)
        NotificationCenter.default.post(
            name: AppConstants.Notifications.robustnessTestProgressOverlayDidStart,
            object: nil,
            userInfo: ["payload": RobustnessTestProgressPayload(kind: kind, phase: "Starting…", percentage: 0)]
        )
    }

    static func post(_ kind: RobustnessTestProgressPayload.Kind, phase: String, percentage: Double) {
        let payload = RobustnessTestProgressPayload(
            kind: kind,
            phase: phase,
            percentage: min(max(percentage, 0), 1)
        )
        NotificationCenter.default.post(
            name: AppConstants.Notifications.robustnessTestProgressDidUpdate,
            object: nil,
            userInfo: ["payload": payload]
        )
    }

    static func end() {
        NotificationCenter.default.post(name: AppConstants.Notifications.robustnessTestProgressOverlayDidEnd, object: nil)
    }
}
