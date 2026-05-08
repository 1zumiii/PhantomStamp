//
//  WatermarkCompressionAttackTests.swift
//  PhantomStamp
//
//  Manual / DEBUG validation:
//  - embed watermark into bundled TestImg
//  - JPEG recompress at a "medium" quality
//  - save the recompressed (attacked) image to system photo library
//  - extract watermark from the recompressed image
//

import Foundation
import UIKit

enum WatermarkCompressionAttackTests {
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
        let service = WatermarkService()

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

    /// Sweeps multiple JPEG qualities (from high to low) and finds the extraction limit.
    ///
    /// - Saves to Photo Library:
    ///   - the lowest passing attacked image (if any)
    ///   - the first failing attacked image after the last pass (if any)
    static func runJpegQualityLimitSweepOnBundledTestImg(
        qualities: [Double] = [0.90, 0.80, 0.70, 0.60, 0.50, 0.40, 0.35, 0.30, 0.25, 0.20, 0.15, 0.10]
    ) async -> SweepReport {
        guard let img = ImagePipelineTests.loadBundledTestUIImage() else {
            return SweepReport(imageLoaded: false, embedSucceeded: false, cases: [], lowestPassingQuality: nil, firstFailingQuality: nil)
        }

        let expectedText = "Successful"
        let service = WatermarkService()

        let watermarked: UIImage
        do {
            watermarked = try await service.embedWatermark(into: img, text: expectedText)
        } catch {
            return SweepReport(imageLoaded: true, embedSucceeded: false, cases: [], lowestPassingQuality: nil, firstFailingQuality: nil)
        }

        // Helper to test a single quality. Returns (case, attackedImage?).
        func testQuality(_ q0: Double) async -> (quality: Double, jpegBytes: Int, attacked: UIImage?) {
            let q = ImageCompressionUtils.clampQuality(q0)
            guard let recompressed = ImageCompressionUtils.recompressJPEG(image: watermarked, quality: q) else {
                return (quality: q, jpegBytes: 0, attacked: nil)
            }
            let attacked = recompressed.image
            let jpegBytes = recompressed.jpegBytes
            return (quality: q, jpegBytes: jpegBytes, attacked: attacked)
        }

        var casesByQuality: [Double: SweepCase] = [:]
        var imageByQuality: [Double: UIImage] = [:]

        var lastPassQ: Double?
        var lastPassImage: UIImage?
        var firstFailQAfterPass: Double?
        var firstFailImageAfterPass: UIImage?

        // 1) Coarse sweep (user-visible list).
        for q0 in qualities {
            let r = await testQuality(q0)
            if let img = r.attacked {
                imageByQuality[r.quality] = img
            }
            casesByQuality[r.quality] = SweepCase(
                quality: r.quality,
                jpegBytes: r.jpegBytes,
                saveSucceeded: false, // boundary images are saved later
                extractSucceeded: false,
                textRoundTripPassed: false,
                extractedText: nil
            )
        }

        // Batch extract (best effort) for the coarse sweep.
        let orderedQualities = qualities.map(ImageCompressionUtils.clampQuality)
        let orderedImages: [UIImage] = orderedQualities.compactMap { imageByQuality[$0] }
        let extractedBatch = await service.extractWatermarkBestEffort(from: orderedImages)
        var extractedIter = extractedBatch.makeIterator()

        for q in orderedQualities {
            guard imageByQuality[q] != nil else { continue }
            let extracted = extractedIter.next() ?? nil
            let ok = (extracted == expectedText)
            casesByQuality[q] = SweepCase(
                quality: q,
                jpegBytes: casesByQuality[q]?.jpegBytes ?? 0,
                saveSucceeded: false,
                extractSucceeded: (extracted != nil),
                textRoundTripPassed: ok,
                extractedText: extracted
            )
            if ok {
                lastPassQ = q
                lastPassImage = imageByQuality[q]
            } else if lastPassQ != nil, firstFailQAfterPass == nil {
                firstFailQAfterPass = q
                firstFailImageAfterPass = imageByQuality[q]
            }
        }

        // 2) Refine between the last passing and first failing quality using binary search.
        //
        // Example: pass=0.60, fail=0.50 -> probe 0.55, 0.575, ...
        if let passQ = lastPassQ, let failQ = firstFailQAfterPass, failQ < passQ {
            var hi = passQ
            var lo = failQ
            var bestPassQ = passQ
            var bestPassImg = lastPassImage
            var bestFailQ = failQ
            var bestFailImg = firstFailImageAfterPass

            let targetResolution: Double = 0.01
            var iter = 0
            while (hi - lo) > targetResolution, iter < 12 {
                iter += 1
                let mid = (hi + lo) / 2.0
                // Round to 3 decimals to reduce duplicate encoder rounding noise.
                let midQ = (mid * 1000).rounded() / 1000
                if casesByQuality[midQ] != nil {
                    // Already tested this exact value.
                    if casesByQuality[midQ]?.textRoundTripPassed == true {
                        hi = midQ
                        bestPassQ = midQ
                        bestPassImg = imageByQuality[midQ]
                    } else {
                        lo = midQ
                        bestFailQ = midQ
                        bestFailImg = imageByQuality[midQ]
                    }
                    continue
                }

                let r = await testQuality(midQ)
                if let img = r.attacked { imageByQuality[r.quality] = img }

                // Keep refine step simple: single extract is fine for just a few probes.
                let extracted: String?
                if let img = r.attacked {
                    extracted = try? await service.extractWatermark(from: img)
                } else {
                    extracted = nil
                }
                let ok = (extracted == expectedText)
                casesByQuality[r.quality] = SweepCase(
                    quality: r.quality,
                    jpegBytes: r.jpegBytes,
                    saveSucceeded: false,
                    extractSucceeded: (extracted != nil),
                    textRoundTripPassed: ok,
                    extractedText: extracted
                )

                if ok {
                    hi = r.quality
                    bestPassQ = r.quality
                    bestPassImg = r.attacked
                } else {
                    lo = r.quality
                    bestFailQ = r.quality
                    bestFailImg = r.attacked
                }
            }

            lastPassQ = bestPassQ
            lastPassImage = bestPassImg
            firstFailQAfterPass = bestFailQ
            firstFailImageAfterPass = bestFailImg
        }

        // Save boundary images (best effort).
        if let img = lastPassImage {
            try? await PhotoLibraryExporter.saveToPhotoLibrary(img)
        }
        if let img = firstFailImageAfterPass {
            try? await PhotoLibraryExporter.saveToPhotoLibrary(img)
        }

        let orderedCases = casesByQuality.values.sorted { $0.quality > $1.quality }
        return SweepReport(
            imageLoaded: true,
            embedSucceeded: true,
            cases: orderedCases,
            lowestPassingQuality: lastPassQ,
            firstFailingQuality: firstFailQAfterPass
        )
    }
}
