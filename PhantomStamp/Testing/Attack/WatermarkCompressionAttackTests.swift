//
//  WatermarkCompressionAttackTests.swift
//  PhantomStamp
//
//  Manual / DEBUG validation:
//  - embed watermark into bundled TestImg
//  - JPEG recompress at varying qualities
//  - save boundary images to system photo library
//  - extract watermark from the recompressed image
//

import Foundation
import UIKit

enum WatermarkCompressionAttackTests {
    /// Keeps `UserSettingsStore` alive while `WatermarkService.settingsStore` is `weak`.
    /// Threshold `-1` makes `variance < threshold` impossible for non‑negative block variance, so every 8×8 tile is actually embedded (matches historical test behavior).
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

    struct Report: Sendable {
        var imageLoaded: Bool
        var embedSucceeded: Bool
        var recompressSucceeded: Bool
        var saveSucceeded: Bool
        var extractSucceeded: Bool
        var textRoundTripPassed: Bool

        var extractedText: String?
        var jpegBytes: Int?
        var attackedPx: (w: Int, h: Int)?
        var quality: Double
    }

    struct SweepCase: Sendable {
        var quality: Double
        var jpegBytes: Int
        var saveSucceeded: Bool
        var extractSucceeded: Bool
        var textRoundTripPassed: Bool
        var extractedText: String?
        var passed: Bool
    }

    struct SweepReport: Sendable {
        var imageLoaded: Bool
        var embedSucceeded: Bool
        var cases: [SweepCase]
        /// Lowest quality that still passes (if any).
        var lowestPassingQuality: Double?
        /// First failing quality after the last pass (if any).
        var firstFailingQuality: Double?
    }

    /// "Medium" JPEG quality recompression (default 0.6).
    static func runMediumJpegCompressionOnBundledTestImg(quality: Double = 0.60) async -> Report {
        guard let img = ImagePipelineTests.loadBundledTestUIImage() else {
            return Report(
                imageLoaded: false,
                embedSucceeded: false,
                recompressSucceeded: false,
                saveSucceeded: false,
                extractSucceeded: false,
                textRoundTripPassed: false,
                extractedText: nil,
                jpegBytes: nil,
                attackedPx: nil,
                quality: quality
            )
        }

        let text = "Successful"
        let binding = await MainActor.run { WatermarkServiceTestBinding(textureVarianceThreshold: -1) }
        let service = binding.service

        let watermarked: UIImage
        do {
            watermarked = try await service.embedWatermark(into: img, text: text)
        } catch {
            return Report(
                imageLoaded: true,
                embedSucceeded: false,
                recompressSucceeded: false,
                saveSucceeded: false,
                extractSucceeded: false,
                textRoundTripPassed: false,
                extractedText: nil,
                jpegBytes: nil,
                attackedPx: nil,
                quality: quality
            )
        }

        let clampedQ = ImageCompressionUtils.clampQuality(quality)
        guard let recompressed = ImageCompressionUtils.recompressJPEG(image: watermarked, quality: clampedQ) else {
            return Report(
                imageLoaded: true,
                embedSucceeded: true,
                recompressSucceeded: false,
                saveSucceeded: false,
                extractSucceeded: false,
                textRoundTripPassed: false,
                extractedText: nil,
                jpegBytes: nil,
                attackedPx: nil,
                quality: clampedQ
            )
        }
        let attacked = recompressed.image
        let jpegBytes = recompressed.jpegBytes

        let pxW = Int(attacked.size.width * attacked.scale)
        let pxH = Int(attacked.size.height * attacked.scale)

        var saveSucceeded = false
        do {
            try await PhotoLibraryExporter.saveToPhotoLibrary(attacked)
            saveSucceeded = true
        } catch {
            saveSucceeded = false
        }

        do {
            let extracted = try await service.extractWatermark(from: attacked)
            return Report(
                imageLoaded: true,
                embedSucceeded: true,
                recompressSucceeded: true,
                saveSucceeded: saveSucceeded,
                extractSucceeded: true,
                textRoundTripPassed: (extracted == text),
                extractedText: extracted,
                jpegBytes: jpegBytes,
                attackedPx: (pxW, pxH),
                quality: clampedQ
            )
        } catch {
            return Report(
                imageLoaded: true,
                embedSucceeded: true,
                recompressSucceeded: true,
                saveSucceeded: saveSucceeded,
                extractSucceeded: false,
                textRoundTripPassed: false,
                extractedText: nil,
                jpegBytes: jpegBytes,
                attackedPx: (pxW, pxH),
                quality: clampedQ
            )
        }
    }

    /// Smart boundary scan: coarse sweep from high → low quality, then fine drill-down.
    ///
    /// Mirrors `SyncTemplateGeometricAttackTests.sweepDirection`: tolerates one consecutive
    /// failure in the coarse phase (encoder / interpolation noise), then steps outward with a
    /// small quality decrement to locate the exact breakdown boundary.
    ///
    /// Saves to Photo Library:
    ///   - the lowest passing attacked image (if any)
    ///   - the first failing attacked image after the last pass (if any)
    static func runJpegQualityLimitSweepOnBundledTestImg(
        coarseQualities: [Double] = [0.95, 0.90, 0.80, 0.70, 0.60, 0.50, 0.40, 0.35, 0.30, 0.25, 0.20, 0.15, 0.10, 0.05],
        fineStep: Double = 0.01
    ) async -> SweepReport {
        guard let img = ImagePipelineTests.loadBundledTestUIImage() else {
            return SweepReport(imageLoaded: false, embedSucceeded: false, cases: [], lowestPassingQuality: nil, firstFailingQuality: nil)
        }

        let expectedText = "Successful"
        let binding = await MainActor.run { WatermarkServiceTestBinding(textureVarianceThreshold: -1) }
        let service = binding.service

        let watermarked: UIImage
        do {
            watermarked = try await service.embedWatermark(into: img, text: expectedText)
        } catch {
            return SweepReport(imageLoaded: true, embedSucceeded: false, cases: [], lowestPassingQuality: nil, firstFailingQuality: nil)
        }

        func evaluate(quality q0: Double) async -> (case: SweepCase, attacked: UIImage?) {
            let q = ImageCompressionUtils.clampQuality(q0)
            guard let recompressed = ImageCompressionUtils.recompressJPEG(image: watermarked, quality: q) else {
                let failCase = SweepCase(
                    quality: q, jpegBytes: 0, saveSucceeded: false,
                    extractSucceeded: false, textRoundTripPassed: false,
                    extractedText: nil, passed: false
                )
                return (failCase, nil)
            }
            let attacked = recompressed.image
            let extracted = try? await service.extractWatermark(from: attacked)
            let ok = (extracted == expectedText)
            let sweepCase = SweepCase(
                quality: q,
                jpegBytes: recompressed.jpegBytes,
                saveSucceeded: false,
                extractSucceeded: (extracted != nil),
                textRoundTripPassed: ok,
                extractedText: extracted,
                passed: ok
            )
            return (sweepCase, attacked)
        }

        func sweepDirection(coarseSteps: [Double], fineStep: Double) async -> [SweepCase] {
            var results: [SweepCase] = []
            var imageByQuality: [Double: UIImage] = [:]
            var consecutiveFails = 0
            var highestPassIndex = -1

            // 1. Coarse sweep (high → low quality).
            for (i, q0) in coarseSteps.enumerated() {
                let r = await evaluate(quality: q0)
                results.append(r.case)
                if let img = r.attacked { imageByQuality[r.case.quality] = img }

                if r.case.passed {
                    consecutiveFails = 0
                    highestPassIndex = i
                } else {
                    consecutiveFails += 1
                    if consecutiveFails >= 2 { break }
                }
            }

            // 2. Fine sweep (drill down past the last pass).
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
                        let r = await evaluate(quality: currentFine)
                        results.append(r.case)
                        if let img = r.attacked { imageByQuality[r.case.quality] = img }
                        if r.case.passed { fineFails = 0 } else { fineFails += 1 }
                    }
                    currentFine += (fineStep * direction)
                }
            }

            return results
        }

        let allCases = await sweepDirection(coarseSteps: coarseQualities, fineStep: fineStep)
        let sortedCases = allCases.sorted { $0.quality > $1.quality }

        let passingCases = sortedCases.filter(\.passed)
        let lowestPassQ = passingCases.map(\.quality).min()
        let firstFailQ: Double? = {
            guard let lowest = lowestPassQ else { return nil }
            return sortedCases
                .filter { $0.quality < lowest && !$0.passed }
                .map(\.quality)
                .max()
        }()

        // Save boundary images (best effort).
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
}
