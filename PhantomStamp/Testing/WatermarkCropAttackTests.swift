//
//  WatermarkCropAttackTests.swift
//  PhantomStamp
//
//  Manual / DEBUG validation:
//  - embed watermark into bundled TestImg
//  - crop away right 10% of the watermarked image
//  - save the cropped (attacked) image to system photo library
//  - extract watermark from the cropped image
//

import Foundation
import UIKit

enum WatermarkCropAttackTests {
    enum CropKind: String, Sendable {
        case right10 = "right10%"
        case left10 = "left10%"
        case top10 = "top10%"
    }

    struct CaseReport: Sendable {
        var kind: CropKind
        var embedSucceeded: Bool
        var cropSucceeded: Bool
        var saveSucceeded: Bool
        var extractSucceeded: Bool
        var textRoundTripPassed: Bool

        var extractedText: String?
        var cropPx: (w: Int, h: Int)?
    }

    struct Report: Sendable {
        var imageLoaded: Bool
        var cases: [CaseReport]
    }

    /// Runs 3 crop-attack cases:
    /// - crop away right 10%
    /// - crop away left 10%
    /// - crop away top 10%
    ///
    /// Each case saves the attacked image to Photo Library (best-effort), then extracts watermark.
    static func runAllCrop10PercentOnBundledTestImg() async -> Report {
        guard let img = ImagePipelineTests.loadBundledTestUIImage() else {
            return Report(imageLoaded: false, cases: [])
        }

        let text = "水印OK"
        let service = WatermarkService()

        // Embed once, reuse the watermarked image for all crop cases.
        let watermarked: UIImage
        do {
            watermarked = try await service.embedWatermark(into: img, text: text)
        } catch {
            let failCases = [CropKind.right10, .left10, .top10].map {
                CaseReport(
                    kind: $0,
                    embedSucceeded: false,
                    cropSucceeded: false,
                    saveSucceeded: false,
                    extractSucceeded: false,
                    textRoundTripPassed: false,
                    extractedText: nil,
                    cropPx: nil
                )
            }
            return Report(imageLoaded: true, cases: failCases)
        }

        var out: [CaseReport] = []
        out.reserveCapacity(3)

        for kind in [CropKind.right10, .left10, .top10] {
            out.append(await runSingleCropCase(kind: kind, percent: 0.10, watermarked: watermarked, expectedText: text, service: service))
        }

        return Report(imageLoaded: true, cases: out)
    }

    /// Backward-compatible entry for the previous single-case test.
    static func runRightCrop10PercentOnBundledTestImg() async -> CaseReport {
        let r = await runAllCrop10PercentOnBundledTestImg()
        return r.cases.first(where: { $0.kind == .right10 })
            ?? CaseReport(kind: .right10, embedSucceeded: false, cropSucceeded: false, saveSucceeded: false, extractSucceeded: false, textRoundTripPassed: false, extractedText: nil, cropPx: nil)
    }

    private static func runSingleCropCase(
        kind: CropKind,
        percent: Double,
        watermarked: UIImage,
        expectedText: String,
        service: WatermarkService
    ) async -> CaseReport {
        guard let cropped = crop(image: watermarked, kind: kind, percent: percent) else {
            return CaseReport(
                kind: kind,
                embedSucceeded: true,
                cropSucceeded: false,
                saveSucceeded: false,
                extractSucceeded: false,
                textRoundTripPassed: false,
                extractedText: nil,
                cropPx: nil
            )
        }

        let pxW = Int(cropped.size.width * cropped.scale)
        let pxH = Int(cropped.size.height * cropped.scale)

        var saveSucceeded = false
        do {
            try await PhotoLibraryExporter.saveToPhotoLibrary(cropped)
            saveSucceeded = true
        } catch {
            saveSucceeded = false
        }

        do {
            let extracted = try await service.extractWatermark(from: cropped)
            return CaseReport(
                kind: kind,
                embedSucceeded: true,
                cropSucceeded: true,
                saveSucceeded: saveSucceeded,
                extractSucceeded: true,
                textRoundTripPassed: (extracted == expectedText),
                extractedText: extracted,
                cropPx: (pxW, pxH)
            )
        } catch {
            return CaseReport(
                kind: kind,
                embedSucceeded: true,
                cropSucceeded: true,
                saveSucceeded: saveSucceeded,
                extractSucceeded: false,
                textRoundTripPassed: false,
                extractedText: nil,
                cropPx: (pxW, pxH)
            )
        }
    }

    /// Crop image using pixel-precise `cgImage` cropping.
    private static func crop(image: UIImage, kind: CropKind, percent: Double) -> UIImage? {
        guard percent > 0, percent < 1 else { return image }
        guard let cg = image.cgImage else { return nil }

        // `cgImage` dimensions are already in pixels.
        let w = cg.width
        let h = cg.height

        let rect: CGRect
        switch kind {
        case .right10:
            let newW = max(1, Int(Double(w) * (1.0 - percent)))
            rect = CGRect(x: 0, y: 0, width: newW, height: h)
        case .left10:
            let cut = max(0, Int(Double(w) * percent))
            let newW = max(1, w - cut)
            rect = CGRect(x: cut, y: 0, width: newW, height: h)
        case .top10:
            let cut = max(0, Int(Double(h) * percent))
            let newH = max(1, h - cut)
            // `cgImage.cropping` uses pixel coordinates with origin at top-left for the image data buffer,
            // so cropping "top" means shifting `y` down and keeping the lower portion.
            rect = CGRect(x: 0, y: cut, width: w, height: newH)
        }

        guard let croppedCG = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: croppedCG, scale: image.scale, orientation: image.imageOrientation)
    }
}

