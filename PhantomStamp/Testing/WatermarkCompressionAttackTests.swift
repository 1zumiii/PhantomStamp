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

        let clampedQ = min(max(quality, 0.05), 0.95)
        guard let jpeg = watermarked.jpegData(compressionQuality: clampedQ),
              let attacked = UIImage(data: jpeg) else {
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
                jpegBytes: jpeg.count,
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
                jpegBytes: jpeg.count,
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
        func testQuality(_ q0: Double) async -> (SweepCase, UIImage?) {
            let q = min(max(q0, 0.05), 0.95)
            guard let (attacked, jpegBytes) = recompressJpeg(image: watermarked, quality: q) else {
                return (
                    SweepCase(quality: q, jpegBytes: 0, saveSucceeded: false, extractSucceeded: false, textRoundTripPassed: false, extractedText: nil),
                    nil
                )
            }
            let extracted: String?
            do {
                extracted = try await service.extractWatermark(from: attacked)
            } catch {
                extracted = nil
            }
            let ok = (extracted == expectedText)
            return (
                SweepCase(
                    quality: q,
                    jpegBytes: jpegBytes,
                    saveSucceeded: false, // boundary images are saved later
                    extractSucceeded: (extracted != nil),
                    textRoundTripPassed: ok,
                    extractedText: extracted
                ),
                attacked
            )
        }

        var casesByQuality: [Double: SweepCase] = [:]
        var imageByQuality: [Double: UIImage] = [:]

        var lastPassQ: Double?
        var lastPassImage: UIImage?
        var firstFailQAfterPass: Double?
        var firstFailImageAfterPass: UIImage?

        // 1) Coarse sweep (user-visible list).
        for q0 in qualities {
            let (c, img) = await testQuality(q0)
            casesByQuality[c.quality] = c
            if let img { imageByQuality[c.quality] = img }
            if c.textRoundTripPassed {
                lastPassQ = c.quality
                lastPassImage = img
            } else if lastPassQ != nil, firstFailQAfterPass == nil {
                firstFailQAfterPass = c.quality
                firstFailImageAfterPass = img
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

                let (c, img) = await testQuality(midQ)
                casesByQuality[c.quality] = c
                if let img { imageByQuality[c.quality] = img }
                if c.textRoundTripPassed {
                    hi = c.quality
                    bestPassQ = c.quality
                    bestPassImg = img
                } else {
                    lo = c.quality
                    bestFailQ = c.quality
                    bestFailImg = img
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

private func recompressJpeg(image: UIImage, quality: Double) -> (UIImage, Int)? {
    let q = min(max(quality, 0.05), 0.95)
    guard let jpeg = image.jpegData(compressionQuality: q),
          let attacked = UIImage(data: jpeg) else { return nil }
    return (attacked, jpeg.count)
}

