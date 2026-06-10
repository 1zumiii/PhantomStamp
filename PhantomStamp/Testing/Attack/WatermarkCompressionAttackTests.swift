//
//  WatermarkCompressionAttackTests.swift
//  PhantomStamp
//
//  Manual / DEBUG validation focused on JPEG recompression resistance.
//  Geometric detection, sync header scan, and FEC are exercised end-to-end via
//  `extractWatermarkSilently` — only the compression attack varies.
//
//  Other modules are held at maximum robustness:
//    - `textureVarianceThreshold = -1` (embed every 8×8 tile)
//    - `syncTemplateIntensity` / `embeddingStrength` left at app defaults
//

import Foundation
import UIKit

enum WatermarkCompressionAttackTests {

    // ==========================================
    // MARK: - Test Binding
    // ==========================================

    /// Keeps `UserSettingsStore` alive while `WatermarkService.settingsStore` is `weak`.
    @MainActor
    private final class WatermarkServiceTestBinding {
        let settingsStore: UserSettingsStore
        let service: WatermarkService

        init(textureVarianceThreshold: Double) {
            let suite = UserDefaults(suiteName: "phantomstamp.testing.compression.\(UUID().uuidString)")!
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
        var recompressSucceeded: Bool
        var extractSucceeded: Bool
        var textRoundTripPassed: Bool

        var extractedText: String?
        var jpegBytes: Int?
        var attackedPx: (w: Int, h: Int)?
        var quality: Double
    }

    struct AttackCase: Sendable {
        var quality: Double
        var jpegBytes: Int
        var attackedPx: (w: Int, h: Int)?

        var extractSucceeded: Bool
        var textRoundTripPassed: Bool
        var extractedText: String?
        var passed: Bool
    }

    struct SweepReport: Sendable {
        var imageLoaded: Bool
        var embedSucceeded: Bool
        var cases: [AttackCase]
        /// Lowest JPEG quality that still passes (worst compression still recoverable).
        var lowestPassingQuality: Double?
        /// Highest quality that fails among cases below `lowestPassingQuality` (if any).
        var firstFailingQuality: Double?
    }

    // ==========================================
    // MARK: - Test 1: Single-Point Compression (default q=0.90)
    // ==========================================

    static func runBasicJpegCompressionOnBundledTestImg(quality: Double = 0.90) async -> BasicReport {
        guard let img = ImagePipelineTests.loadBundledTestUIImage() else {
            return BasicReport(
                imageLoaded: false, embedSucceeded: false, recompressSucceeded: false,
                extractSucceeded: false, textRoundTripPassed: false,
                extractedText: nil, jpegBytes: nil, attackedPx: nil, quality: quality
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
                imageLoaded: true, embedSucceeded: false, recompressSucceeded: false,
                extractSucceeded: false, textRoundTripPassed: false,
                extractedText: nil, jpegBytes: nil, attackedPx: nil, quality: quality
            )
        }

        let q = ImageCompressionUtils.clampQuality(quality)
        guard let recompressed = ImageCompressionUtils.recompressJPEG(image: watermarked, quality: q) else {
            return BasicReport(
                imageLoaded: true, embedSucceeded: true, recompressSucceeded: false,
                extractSucceeded: false, textRoundTripPassed: false,
                extractedText: nil, jpegBytes: nil, attackedPx: nil, quality: q
            )
        }

        let attacked = recompressed.image
        let px = pixelSize(of: attacked)

        do {
            let extracted = try await service.extractWatermarkSilently(from: attacked)
            return BasicReport(
                imageLoaded: true, embedSucceeded: true, recompressSucceeded: true,
                extractSucceeded: true, textRoundTripPassed: (extracted == expectedText),
                extractedText: extracted, jpegBytes: recompressed.jpegBytes,
                attackedPx: px, quality: q
            )
        } catch {
            return BasicReport(
                imageLoaded: true, embedSucceeded: true, recompressSucceeded: true,
                extractSucceeded: false, textRoundTripPassed: false,
                extractedText: nil, jpegBytes: recompressed.jpegBytes,
                attackedPx: px, quality: q
            )
        }
    }

    /// Backward-compatible alias.
    static func runMediumJpegCompressionOnBundledTestImg(quality: Double = 0.60) async -> BasicReport {
        await runBasicJpegCompressionOnBundledTestImg(quality: quality)
    }

    // ==========================================
    // MARK: - Test 2: Smart Boundary Scan (JPEG Quality)
    // ==========================================

    /// Sweeps JPEG quality from near-lossless → heavy compression. Tolerates one consecutive
    /// failure in the coarse phase, then fine-drills past the last pass to locate the breakdown.
    static func runJpegQualityLimitSweepOnBundledTestImg(
        coarseQualities: [Double] = [1.0, 0.95, 0.90, 0.85, 0.80, 0.70, 0.60, 0.50, 0.40, 0.35, 0.30, 0.25, 0.20, 0.15, 0.10, 0.05],
        fineStep: Double = 0.01
    ) async -> SweepReport {
        guard let img = ImagePipelineTests.loadBundledTestUIImage() else {
            return SweepReport(
                imageLoaded: false, embedSucceeded: false,
                cases: [], lowestPassingQuality: nil, firstFailingQuality: nil
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
                imageLoaded: true, embedSucceeded: false,
                cases: [], lowestPassingQuality: nil, firstFailingQuality: nil
            )
        }

        try? await PhotoLibraryExporter.saveToPhotoLibrary(watermarked)

        func evaluate(quality q0: Double) async -> AttackCase {
            let q = ImageCompressionUtils.clampQuality(q0)
            guard let recompressed = ImageCompressionUtils.recompressJPEG(image: watermarked, quality: q) else {
                return AttackCase(
                    quality: q, jpegBytes: 0, attackedPx: nil,
                    extractSucceeded: false, textRoundTripPassed: false,
                    extractedText: nil, passed: false
                )
            }
            let attacked = recompressed.image
            let extracted = try? await service.extractWatermarkSilently(from: attacked)
            let ok = (extracted == expectedText)
            return AttackCase(
                quality: q,
                jpegBytes: recompressed.jpegBytes,
                attackedPx: pixelSize(of: attacked),
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

            for (i, q0) in coarseSteps.enumerated() {
                let res = await evaluate(quality: q0)
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

                    let qKey = ImageCompressionUtils.clampQuality(currentFine)
                    if let existing = results.first(where: { abs($0.quality - qKey) < 1e-4 }) {
                        if existing.passed { fineFails = 0 } else { fineFails += 1 }
                    } else {
                        let res = await evaluate(quality: currentFine)
                        results.append(res)
                        if res.passed { fineFails = 0 } else { fineFails += 1 }
                    }
                    currentFine += (fineStep * direction)
                }
            }

            return results
        }

        let allCases = await sweepDirection(coarseSteps: coarseQualities, fineStep: fineStep)
        let sortedCases = allCases.sorted { $0.quality > $1.quality }

        let passingQualities = sortedCases.filter(\.passed).map(\.quality)
        let lowestPassQ = passingQualities.min()
        let firstFailQ: Double? = {
            guard let lowest = lowestPassQ else { return nil }
            return sortedCases
                .filter { $0.quality < lowest && !$0.passed }
                .map(\.quality)
                .max()
        }()

        if let passQ = lowestPassQ,
           let recompressed = ImageCompressionUtils.recompressJPEG(image: watermarked, quality: passQ) {
            try? await PhotoLibraryExporter.saveToPhotoLibrary(recompressed.image)
        }
        if let failQ = firstFailQ,
           let recompressed = ImageCompressionUtils.recompressJPEG(image: watermarked, quality: failQ) {
            try? await PhotoLibraryExporter.saveToPhotoLibrary(recompressed.image)
        }

        return SweepReport(
            imageLoaded: true,
            embedSucceeded: true,
            cases: sortedCases,
            lowestPassingQuality: lowestPassQ,
            firstFailingQuality: firstFailQ
        )
    }

    // ==========================================
    // MARK: - Helpers
    // ==========================================

    private static func pixelSize(of image: UIImage) -> (w: Int, h: Int) {
        (Int(image.size.width * image.scale), Int(image.size.height * image.scale))
    }

    // ==========================================
    // MARK: - DEBUG print entry points
    // ==========================================

    static func runBasicAndPrint(quality: Double = 0.90) async {
        #if DEBUG
        let t0 = CFAbsoluteTimeGetCurrent()
        let r = await runBasicJpegCompressionOnBundledTestImg(quality: quality)
        let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000

        let overallPass = r.imageLoaded && r.embedSucceeded && r.recompressSucceeded
            && r.extractSucceeded && r.textRoundTripPassed
        let status = overallPass ? "PASS" : "FAIL"
        print("[WatermarkCompressionAttackTests] \(status) Basic — JPEG q=\(String(format: "%.2f", r.quality))")
        let px = r.attackedPx.map { "\($0.w)x\($0.h)px" } ?? "nil"
        print("  - imageLoaded:      \(r.imageLoaded ? "PASS" : "FAIL")")
        print("  - embed:            \(r.embedSucceeded ? "PASS" : "FAIL")")
        print("  - recompress:       \(r.recompressSucceeded ? "PASS" : "FAIL")  px=\(px) bytes=\(r.jpegBytes.map(String.init) ?? "nil")")
        print("  - extract:          \(r.extractSucceeded ? "PASS" : "FAIL")  text=\(r.extractedText ?? "nil")")
        print("  - round-trip:       \(r.textRoundTripPassed ? "PASS" : "FAIL")")
        print("  - elapsed:          \(String(format: "%.2f", dtMs)) ms")
        #endif
    }

    static func runLimitSweepAndPrint() async {
        #if DEBUG
        let t0 = CFAbsoluteTimeGetCurrent()
        let r = await runJpegQualityLimitSweepOnBundledTestImg()
        let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000

        let overallOk = r.imageLoaded && r.embedSucceeded
        let status = overallOk ? "RAN" : "FAIL"
        let lowest = r.lowestPassingQuality.map { String(format: "%.2f", $0) } ?? "none"
        let firstFail = r.firstFailingQuality.map { String(format: "%.2f", $0) } ?? "none"
        print("[WatermarkCompressionAttackTests] \(status) LimitSweep — JPEG quality tolerance")
        print("  - lowest pass q:    \(lowest)")
        print("  - first fail q:     \(firstFail)")
        print("  - cases:")
        for c in r.cases {
            let mark = c.passed ? "PASS" : "FAIL"
            let px = c.attackedPx.map { "\($0.w)x\($0.h)" } ?? "nil"
            print("      \(mark)  q=\(String(format: "%.2f", c.quality))  px=\(px)  bytes=\(c.jpegBytes)  extracted=\(c.extractedText ?? "nil")")
        }
        print("  - elapsed:          \(String(format: "%.2f", dtMs)) ms")
        #endif
    }
}
