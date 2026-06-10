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
    struct ManipResultSheetModel: Identifiable {
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

    let settingsStore: UserSettingsStore

    var isLoading = false
    var alertTitle = "Test Failed"
    var alertMessage = ""
    var showAlert = false
    var multiFileCount = 5

    var manipPickerItem: PhotosPickerItem?
    var manipSourceImage: UIImage?
    var manipSourcePx: (w: Int, h: Int)?
    var manipSourceName: String?
    var manipLoadingImage = false

    var manipJpegQuality = 0.60
    var manipResizeScaleFactor = 1.0
    var manipResultSheet: ManipResultSheetModel?
    var selectedCropKind: WatermarkCropAttackTests.CropKind = .right

    var currentSyncTemplateIntensity: Double { settingsStore.syncTemplateIntensity }

    init(settingsStore: UserSettingsStore) {
        self.settingsStore = settingsStore
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

    func dismissManipResultSheet() {
        manipResultSheet = nil
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

    func runManipResize() async {
        guard let source = manipSourceImage else {
            presentManipFailure(title: "No source image", subtitle: "Pick a photo in Image tools before resizing.")
            return
        }
        guard let resized = ImageResizeUtils.resize(image: source, scaleFactor: manipResizeScaleFactor) else {
            presentManipFailure(title: "Resize failed", subtitle: "Could not scale the image with the current factor.")
            return
        }

        let outPx = pixelSize(of: resized)
        do {
            try await saveManipResultToPhotos(resized)
            print("[TestPage] ManipResize scale=\(String(format: "%.2f", manipResizeScaleFactor)) out=\(outPx.w)x\(outPx.h)")
            presentManipSuccess(
                title: "Saved to Photos",
                subtitle: "Proportional resize finished successfully.",
                details: [
                    ("Scale", String(format: "%.2fx", manipResizeScaleFactor)),
                    ("Output", "\(outPx.w) × \(outPx.h) px"),
                ]
            )
        } catch {
            presentManipFailure(title: "Save failed", subtitle: error.localizedDescription)
        }
    }

    func runCompressionLimitSweep() async {
        await runTest(kind: .compressionLimit) {
            RobustnessTestProgress.post(.compressionLimit, phase: "Embedding reference image…", percentage: 0.08)
            let r = await WatermarkCompressionAttackTests.runJpegQualityLimitSweepOnBundledTestImg()
            RobustnessTestProgress.post(.compressionLimit, phase: "Analyzing sweep results…", percentage: 0.92)

            let ok = r.imageLoaded && r.embedSucceeded && (r.lowestPassingQuality != nil)
            let status = ok ? "PASS" : "FAIL"
            let lowest = r.lowestPassingQuality.map { String(format: "%.2f", $0) } ?? "nil"
            let firstFail = r.firstFailingQuality.map { String(format: "%.2f", $0) } ?? "nil"
            print("[TestPage] CompressionSweep \(status) lowestPass=\(lowest) firstFail=\(firstFail) cases=\(r.cases.count)")
            for c in r.cases {
                let mark = c.passed ? "PASS" : "FAIL"
                print("  - q=\(String(format: "%.2f", c.quality)) \(mark) extracted=\(c.extractedText ?? "nil") bytes=\(c.jpegBytes)")
            }

            if !ok {
                present("Compression sweep failed. lowestPass=\(lowest)")
            }
        }
    }

    func runCropLimitSweep() async {
        await runTest(kind: .cropLimit) {
            RobustnessTestProgress.post(.cropLimit, phase: "Embedding reference image…", percentage: 0.08)
            let r = await WatermarkCropAttackTests.runCropPercentLimitSweepOnBundledTestImg(kind: selectedCropKind)
            RobustnessTestProgress.post(.cropLimit, phase: "Analyzing \(selectedCropKind.displayName) edge…", percentage: 0.92)

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

            if !ok {
                present("Crop limit sweep failed to run (image load or embed failure).")
            }
        }
    }

    func runMultiFileEmbedTest(fileCount: Int) async {
        await runTest(kind: .multiFileEmbed) {
            RobustnessTestProgress.post(.multiFileEmbed, phase: "Preparing \(fileCount) images…", percentage: 0.05)
            let r = await WatermarkMultiFileTests.runMultiFileEmbedOnBundledTestImg(text: "Batch watermark OK", fileCount: fileCount)
            RobustnessTestProgress.post(.multiFileEmbed, phase: "Finalizing batch…", percentage: 0.95)

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
    }

    func runSyncTemplateBasicTest() async {
        let intensity = currentSyncTemplateIntensity
        await runTest(kind: .syncTemplateBasic) {
            RobustnessTestProgress.post(.syncTemplateBasic, phase: "Embedding with template intensity \(String(format: "%.1f", intensity))…", percentage: 0.15)
            let r = await SyncTemplateGeometricAttackTests.runBasicSyncTemplateOnBundledTestImg(syncTemplateIntensity: intensity)
            RobustnessTestProgress.post(.syncTemplateBasic, phase: "Running identity detector…", percentage: 0.85)

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

            if !ok {
                present("Sync template basic test failed. detected(angle=\(detAng), scale=\(detSc)). Top peak r=\(r.topPeaks.first.map { String(format: "%.1f", $0.radius) } ?? "nil").")
            }
        }
    }

    func runSyncTemplateLimitSweep() async {
        let intensity = currentSyncTemplateIntensity
        await runTest(kind: .syncTemplateSweep) {
            RobustnessTestProgress.post(.syncTemplateSweep, phase: "Embedding reference image…", percentage: 0.06)
            let r = await SyncTemplateGeometricAttackTests.runRotationAndScaleLimitSweepOnBundledTestImg(syncTemplateIntensity: intensity)
            RobustnessTestProgress.post(.syncTemplateSweep, phase: "Aggregating rotation & scale limits…", percentage: 0.94)

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

            if !ok {
                present("Sync template limit sweep failed to run (embed or image load failure).")
            }
        }
    }

    // MARK: - Private

    private func runTest(kind: RobustnessTestProgressPayload.Kind, operation: () async -> Void) async {
        isLoading = true
        defer { isLoading = false }

        RobustnessTestProgress.start(kind)
        defer { RobustnessTestProgress.end() }

        await operation()
        RobustnessTestProgress.post(kind, phase: "Complete", percentage: 1.0)
    }

    private func present(_ message: String, title: String = "Test Failed") {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    private func presentManipSuccess(title: String, subtitle: String, details: [(label: String, value: String)]) {
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
