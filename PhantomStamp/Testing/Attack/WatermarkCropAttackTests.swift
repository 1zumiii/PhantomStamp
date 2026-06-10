//
//  WatermarkCropAttackTests.swift
//  PhantomStamp
//
//  Manual / DEBUG validation focused on edge-crop resistance.
//  Geometric detection, sync header scan, and FEC are exercised end-to-end via
//  `extractWatermarkSilently` — only the crop attack varies.
//
//  Other modules are held at maximum robustness:
//    - `textureVarianceThreshold = -1` (embed every 8×8 tile)
//    - `syncTemplateIntensity` / `embeddingStrength` left at app defaults
//

import Foundation
import UIKit

enum WatermarkCropAttackTests {

    enum CropKind: String, Sendable, CaseIterable, Identifiable {
        case top
        case bottom
        case left
        case right
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .top: "Top"
            case .bottom: "Bottom"
            case .left: "Left"
            case .right: "Right"
            case .topLeft: "Top left"
            case .topRight: "Top right"
            case .bottomLeft: "Bottom left"
            case .bottomRight: "Bottom right"
            }
        }
    }

    // ==========================================
    // MARK: - Test Binding
    // ==========================================

    @MainActor
    private final class WatermarkServiceTestBinding {
        let settingsStore: UserSettingsStore
        let service: WatermarkService

        init(textureVarianceThreshold: Double) {
            let suite = UserDefaults(suiteName: "phantomstamp.testing.crop.\(UUID().uuidString)")!
            settingsStore = UserSettingsStore(defaults: suite)
            settingsStore.textureVarianceThreshold = textureVarianceThreshold
            service = WatermarkService()
            service.settingsStore = settingsStore
        }
    }

    // ==========================================
    // MARK: - Report Types
    // ==========================================

    struct BasicReport: Sendable {
        var imageLoaded: Bool
        var embedSucceeded: Bool
        var cropSucceeded: Bool
        var extractSucceeded: Bool
        var textRoundTripPassed: Bool

        var kind: CropKind
        var cropPercent: Double
        var extractedText: String?
        var cropPx: (w: Int, h: Int)?
    }

    struct CaseReport: Sendable {
        var kind: CropKind
        var embedSucceeded: Bool
        var cropSucceeded: Bool
        var extractSucceeded: Bool
        var textRoundTripPassed: Bool
        var extractedText: String?
        var cropPx: (w: Int, h: Int)?
    }

    struct Report: Sendable {
        var imageLoaded: Bool
        var embedSucceeded: Bool
        var cases: [CaseReport]
    }

    struct AttackCase: Sendable {
        var kind: CropKind
        var cropPercent: Double
        var cropPx: (w: Int, h: Int)?
        var extractSucceeded: Bool
        var textRoundTripPassed: Bool
        var extractedText: String?
        var passed: Bool
    }

    struct SweepReport: Sendable {
        var imageLoaded: Bool
        var embedSucceeded: Bool
        var kind: CropKind
        var cases: [AttackCase]
        var maxPassingCropPercent: Double?
        var firstFailingCropPercent: Double?
    }

    /// Backward-compatible alias.
    typealias LimitCase = AttackCase
    typealias LimitSweepReport = SweepReport

    // ==========================================
    // MARK: - Test 1: Single-Point Crop (default right 10%)
    // ==========================================

    static func runBasicCropOnBundledTestImg(
        kind: CropKind = .right,
        percent: Double = 0.10
    ) async -> BasicReport {
        guard let img = ImagePipelineTests.loadBundledTestUIImage() else {
            return BasicReport(
                imageLoaded: false, embedSucceeded: false, cropSucceeded: false,
                extractSucceeded: false, textRoundTripPassed: false,
                kind: kind, cropPercent: percent, extractedText: nil, cropPx: nil
            )
        }

        let expectedText = "Successful"
        let binding = await MainActor.run {
            WatermarkServiceTestBinding(textureVarianceThreshold: -1)
        }
        let service = binding.service

        let watermarked: UIImage
        do {
            watermarked = try await service.embedWatermarkSilently(into: img, text: expectedText)
        } catch {
            return BasicReport(
                imageLoaded: true, embedSucceeded: false, cropSucceeded: false,
                extractSucceeded: false, textRoundTripPassed: false,
                kind: kind, cropPercent: percent, extractedText: nil, cropPx: nil
            )
        }

        guard let cropped = crop(image: watermarked, kind: kind, percent: percent) else {
            return BasicReport(
                imageLoaded: true, embedSucceeded: true, cropSucceeded: false,
                extractSucceeded: false, textRoundTripPassed: false,
                kind: kind, cropPercent: percent, extractedText: nil, cropPx: nil
            )
        }

        let px = pixelSize(of: cropped)

        do {
            let extracted = try await service.extractWatermarkSilently(from: cropped)
            return BasicReport(
                imageLoaded: true, embedSucceeded: true, cropSucceeded: true,
                extractSucceeded: true, textRoundTripPassed: (extracted == expectedText),
                kind: kind, cropPercent: percent, extractedText: extracted, cropPx: px
            )
        } catch {
            return BasicReport(
                imageLoaded: true, embedSucceeded: true, cropSucceeded: true,
                extractSucceeded: false, textRoundTripPassed: false,
                kind: kind, cropPercent: percent, extractedText: nil, cropPx: px
            )
        }
    }

    /// Backward-compatible alias.
    static func runRightCrop10PercentOnBundledTestImg() async -> CaseReport {
        let r = await runBasicCropOnBundledTestImg(kind: .right, percent: 0.10)
        return CaseReport(
            kind: r.kind,
            embedSucceeded: r.embedSucceeded,
            cropSucceeded: r.cropSucceeded,
            extractSucceeded: r.extractSucceeded,
            textRoundTripPassed: r.textRoundTripPassed,
            extractedText: r.extractedText,
            cropPx: r.cropPx
        )
    }

    // ==========================================
    // MARK: - Test 2: All Directions at 10%
    // ==========================================

    static func runAllCrop10PercentOnBundledTestImg() async -> Report {
        guard let img = ImagePipelineTests.loadBundledTestUIImage() else {
            return Report(imageLoaded: false, embedSucceeded: false, cases: [])
        }

        let expectedText = "Successful"
        let binding = await MainActor.run {
            WatermarkServiceTestBinding(textureVarianceThreshold: -1)
        }
        let service = binding.service

        let watermarked: UIImage
        do {
            watermarked = try await service.embedWatermarkSilently(into: img, text: expectedText)
        } catch {
            let failCases = CropKind.allCases.map {
                CaseReport(
                    kind: $0, embedSucceeded: false, cropSucceeded: false,
                    extractSucceeded: false, textRoundTripPassed: false,
                    extractedText: nil, cropPx: nil
                )
            }
            return Report(imageLoaded: true, embedSucceeded: false, cases: failCases)
        }

        var out: [CaseReport] = []
        out.reserveCapacity(CropKind.allCases.count)

        for kind in CropKind.allCases {
            guard let cropped = crop(image: watermarked, kind: kind, percent: 0.10) else {
                out.append(CaseReport(
                    kind: kind, embedSucceeded: true, cropSucceeded: false,
                    extractSucceeded: false, textRoundTripPassed: false,
                    extractedText: nil, cropPx: nil
                ))
                continue
            }

            let px = pixelSize(of: cropped)
            let extracted = try? await service.extractWatermarkSilently(from: cropped)
            out.append(CaseReport(
                kind: kind,
                embedSucceeded: true,
                cropSucceeded: true,
                extractSucceeded: (extracted != nil),
                textRoundTripPassed: (extracted == expectedText),
                extractedText: extracted,
                cropPx: px
            ))
        }

        return Report(imageLoaded: true, embedSucceeded: true, cases: out)
    }

    // ==========================================
    // MARK: - Test 3: Smart Boundary Scan (Crop %)
    // ==========================================

    /// Sweeps crop percentage from 0% outward. Tolerates one consecutive failure in the
    /// coarse phase, then fine-drills past the last pass to locate the breakdown boundary.
    static func runCropPercentLimitSweepOnBundledTestImg(
        kind: CropKind,
        coarsePercents: [Double] = [0.0, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.45, 0.50],
        fineStep: Double = 0.01
    ) async -> SweepReport {
        guard let img = ImagePipelineTests.loadBundledTestUIImage() else {
            return SweepReport(
                imageLoaded: false, embedSucceeded: false, kind: kind,
                cases: [], maxPassingCropPercent: nil, firstFailingCropPercent: nil
            )
        }

        let expectedText = "Successful"
        let binding = await MainActor.run {
            WatermarkServiceTestBinding(textureVarianceThreshold: -1)
        }
        let service = binding.service

        let watermarked: UIImage
        do {
            watermarked = try await service.embedWatermarkSilently(into: img, text: expectedText)
        } catch {
            return SweepReport(
                imageLoaded: true, embedSucceeded: false, kind: kind,
                cases: [], maxPassingCropPercent: nil, firstFailingCropPercent: nil
            )
        }

        try? await PhotoLibraryExporter.saveToPhotoLibrary(watermarked)

        func evaluate(percent: Double) async -> AttackCase {
            guard let cropped = crop(image: watermarked, kind: kind, percent: percent) else {
                return AttackCase(
                    kind: kind, cropPercent: percent, cropPx: nil,
                    extractSucceeded: false, textRoundTripPassed: false,
                    extractedText: nil, passed: false
                )
            }
            let extracted = try? await service.extractWatermarkSilently(from: cropped)
            let ok = (extracted == expectedText)
            return AttackCase(
                kind: kind,
                cropPercent: percent,
                cropPx: pixelSize(of: cropped),
                extractSucceeded: (extracted != nil),
                textRoundTripPassed: ok,
                extractedText: extracted,
                passed: ok
            )
        }

        func sweepDirection(coarseSteps: [Double], fineStep: Double) async -> [AttackCase] {
            var results: [AttackCase] = []
            var consecutiveFails = 0
            var highestPassIndex = -1

            for (i, pct) in coarseSteps.enumerated() {
                let res = await evaluate(percent: pct)
                results.append(res)

                if res.passed {
                    consecutiveFails = 0
                    highestPassIndex = i
                } else {
                    consecutiveFails += 1
                    if consecutiveFails >= 2 { break }
                }
            }

            if highestPassIndex >= 0 {
                let lastPassVal = coarseSteps[highestPassIndex]
                let direction = (coarseSteps.last! > coarseSteps.first!) ? 1.0 : -1.0
                var currentFine = lastPassVal + (fineStep * direction)
                var fineFails = 0

                while fineFails < 2 {
                    if results.count > 100 { break }

                    let pctKey = roundedPercent(currentFine)
                    if let existing = results.first(where: { abs($0.cropPercent - pctKey) < 1e-4 }) {
                        if existing.passed { fineFails = 0 } else { fineFails += 1 }
                    } else {
                        let res = await evaluate(percent: currentFine)
                        results.append(res)
                        if res.passed { fineFails = 0 } else { fineFails += 1 }
                    }
                    currentFine += (fineStep * direction)
                }
            }

            return results
        }

        let allCases = await sweepDirection(coarseSteps: coarsePercents, fineStep: fineStep)
        let sortedCases = allCases.sorted { $0.cropPercent > $1.cropPercent }

        let passingPercents = sortedCases.filter(\.passed).map(\.cropPercent)
        let maxPass = passingPercents.max()
        let firstFail: Double? = {
            guard let pass = maxPass else { return nil }
            return sortedCases
                .filter { $0.cropPercent > pass && !$0.passed }
                .map(\.cropPercent)
                .min()
        }()

        if let passPct = maxPass,
           let cropped = crop(image: watermarked, kind: kind, percent: passPct) {
            try? await PhotoLibraryExporter.saveToPhotoLibrary(cropped)
        }
        if let failPct = firstFail,
           let failImg = crop(image: watermarked, kind: kind, percent: failPct) {
            try? await PhotoLibraryExporter.saveToPhotoLibrary(failImg)
        }

        return SweepReport(
            imageLoaded: true,
            embedSucceeded: true,
            kind: kind,
            cases: sortedCases,
            maxPassingCropPercent: maxPass,
            firstFailingCropPercent: firstFail
        )
    }

    // ==========================================
    // MARK: - Attack Helpers
    // ==========================================

    /// Pixel-precise edge crop via `UIGraphicsImageRenderer` (scale=1). Uses `UIImage.draw`
    /// so EXIF orientation is respected — matches how photos are typically re-saved after edit.
    private static func crop(image: UIImage, kind: CropKind, percent: Double) -> UIImage? {
        guard percent >= 0, percent < 1 else {
            if percent == 0 { return normalizedScaleOne(image) }
            return nil
        }

        let px = pixelSize(of: image)
        guard px.w > 0, px.h > 0 else { return nil }

        let cutW = max(0, Int(Double(px.w) * percent))
        let cutH = max(0, Int(Double(px.h) * percent))

        let destW: Int
        let destH: Int
        let drawOrigin: CGPoint

        switch kind {
        case .right:
            destW = max(1, px.w - cutW)
            destH = px.h
            drawOrigin = .zero
        case .left:
            destW = max(1, px.w - cutW)
            destH = px.h
            drawOrigin = CGPoint(x: -cutW, y: 0)
        case .bottom:
            destW = px.w
            destH = max(1, px.h - cutH)
            drawOrigin = .zero
        case .top:
            destW = px.w
            destH = max(1, px.h - cutH)
            drawOrigin = CGPoint(x: 0, y: -cutH)
        case .topLeft:
            destW = max(1, px.w - cutW)
            destH = max(1, px.h - cutH)
            drawOrigin = CGPoint(x: -cutW, y: -cutH)
        case .topRight:
            destW = max(1, px.w - cutW)
            destH = max(1, px.h - cutH)
            drawOrigin = CGPoint(x: 0, y: -cutH)
        case .bottomLeft:
            destW = max(1, px.w - cutW)
            destH = max(1, px.h - cutH)
            drawOrigin = CGPoint(x: -cutW, y: 0)
        case .bottomRight:
            destW = max(1, px.w - cutW)
            destH = max(1, px.h - cutH)
            drawOrigin = .zero
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let size = CGSize(width: destW, height: destH)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(
                x: drawOrigin.x, y: drawOrigin.y,
                width: CGFloat(px.w), height: CGFloat(px.h)
            ))
        }
    }

    /// Re-render at scale=1 so pixel dimensions match `pixelSize(of:)`.
    private static func normalizedScaleOne(_ image: UIImage) -> UIImage? {
        let px = pixelSize(of: image)
        guard px.w > 0, px.h > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: px.w, height: px.h),
            format: format
        )
        return renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: px.w, height: px.h))
        }
    }

    private static func roundedPercent(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

    private static func pixelSize(of image: UIImage) -> (w: Int, h: Int) {
        (Int(image.size.width * image.scale), Int(image.size.height * image.scale))
    }

    // ==========================================
    // MARK: - DEBUG print entry points
    // ==========================================

    static func runBasicAndPrint(kind: CropKind = .right, percent: Double = 0.10) async {
        #if DEBUG
        let t0 = CFAbsoluteTimeGetCurrent()
        let r = await runBasicCropOnBundledTestImg(kind: kind, percent: percent)
        let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000

        let overallPass = r.imageLoaded && r.embedSucceeded && r.cropSucceeded
            && r.extractSucceeded && r.textRoundTripPassed
        let status = overallPass ? "PASS" : "FAIL"
        print("[WatermarkCropAttackTests] \(status) Basic — \(kind.displayName) crop \(String(format: "%.0f%%", percent * 100))")
        let px = r.cropPx.map { "\($0.w)x\($0.h)px" } ?? "nil"
        print("  - imageLoaded:      \(r.imageLoaded ? "PASS" : "FAIL")")
        print("  - embed:            \(r.embedSucceeded ? "PASS" : "FAIL")")
        print("  - crop:             \(r.cropSucceeded ? "PASS" : "FAIL")  px=\(px)")
        print("  - extract:          \(r.extractSucceeded ? "PASS" : "FAIL")  text=\(r.extractedText ?? "nil")")
        print("  - round-trip:       \(r.textRoundTripPassed ? "PASS" : "FAIL")")
        print("  - elapsed:          \(String(format: "%.2f", dtMs)) ms")
        #endif
    }

    static func runLimitSweepAndPrint(kind: CropKind = .right) async {
        #if DEBUG
        let t0 = CFAbsoluteTimeGetCurrent()
        let r = await runCropPercentLimitSweepOnBundledTestImg(kind: kind)
        let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000

        let overallOk = r.imageLoaded && r.embedSucceeded
        let status = overallOk ? "RAN" : "FAIL"
        let maxPass = r.maxPassingCropPercent.map { String(format: "%.1f%%", $0 * 100) } ?? "none"
        let firstFail = r.firstFailingCropPercent.map { String(format: "%.1f%%", $0 * 100) } ?? "none"
        print("[WatermarkCropAttackTests] \(status) LimitSweep — \(kind.displayName) edge crop tolerance")
        print("  - max pass crop:    \(maxPass)")
        print("  - first fail crop:  \(firstFail)")
        print("  - cases:")
        for c in r.cases {
            let mark = c.passed ? "PASS" : "FAIL"
            let px = c.cropPx.map { "\($0.w)x\($0.h)" } ?? "nil"
            print("      \(mark)  crop=\(String(format: "%.1f%%", c.cropPercent * 100))  px=\(px)  extracted=\(c.extractedText ?? "nil")")
        }
        print("  - elapsed:          \(String(format: "%.2f", dtMs)) ms")
        #endif
    }
}
