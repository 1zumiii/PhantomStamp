//
//  WatermarkCropAttackTests.swift
//  PhantomStamp
//
//  Manual / DEBUG validation:
//  - embed watermark into bundled TestImg
//  - crop away edges at varying percentages
//  - save boundary images to system photo library
//  - extract watermark from the cropped image
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

    struct LimitCase: Sendable {
        var kind: CropKind
        var cropPercent: Double
        var cropPx: (w: Int, h: Int)?
        var extractSucceeded: Bool
        var textRoundTripPassed: Bool
        var extractedText: String?
        var passed: Bool
    }

    struct LimitSweepReport: Sendable {
        var imageLoaded: Bool
        var embedSucceeded: Bool
        var kind: CropKind
        var cases: [LimitCase]
        /// Largest crop percentage that still passes extraction for the selected edge.
        var maxPassingCropPercent: Double?
        /// First failing percentage above `maxPassingCropPercent` (if any).
        var firstFailingCropPercent: Double?
    }

    /// Keeps `UserSettingsStore` alive while `WatermarkService.settingsStore` is `weak`.
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

    /// Runs crop-attack cases at 10% for every direction.
    static func runAllCrop10PercentOnBundledTestImg() async -> Report {
        guard let img = ImagePipelineTests.loadBundledTestUIImage() else {
            return Report(imageLoaded: false, cases: [])
        }

        let text = "Successful"
        let service = WatermarkService()

        let watermarked: UIImage
        do {
            watermarked = try await service.embedWatermarkSilently(into: img, text: text)
        } catch {
            let failCases = CropKind.allCases.map {
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
        out.reserveCapacity(CropKind.allCases.count)

        let kinds = CropKind.allCases
        var croppedImages: [UIImage?] = []
        croppedImages.reserveCapacity(kinds.count)
        var saveSucceededByKind: [CropKind: Bool] = [:]
        var cropPxByKind: [CropKind: (w: Int, h: Int)] = [:]

        for kind in kinds {
            guard let cropped = crop(image: watermarked, kind: kind, percent: 0.10) else {
                croppedImages.append(nil)
                continue
            }
            croppedImages.append(cropped)

            let pxW = Int(cropped.size.width * cropped.scale)
            let pxH = Int(cropped.size.height * cropped.scale)
            cropPxByKind[kind] = (pxW, pxH)

            var saveSucceeded = false
            do {
                try await PhotoLibraryExporter.saveToPhotoLibrary(cropped)
                saveSucceeded = true
            } catch {
                saveSucceeded = false
            }
            saveSucceededByKind[kind] = saveSucceeded
        }

        let imagesForBatch = croppedImages.compactMap { $0 }
        let extractedBatch = await service.extractWatermarkBestEffort(from: imagesForBatch)
        var extractedIter = extractedBatch.makeIterator()

        for kind in kinds {
            if croppedImages[kinds.firstIndex(of: kind) ?? 0] != nil {
                let extracted = extractedIter.next() ?? nil
                let saveOk = saveSucceededByKind[kind] ?? false
                let cropPx = cropPxByKind[kind]
                out.append(
                    CaseReport(
                        kind: kind,
                        embedSucceeded: true,
                        cropSucceeded: true,
                        saveSucceeded: saveOk,
                        extractSucceeded: (extracted != nil),
                        textRoundTripPassed: (extracted == text),
                        extractedText: extracted,
                        cropPx: cropPx
                    )
                )
            } else {
                out.append(
                    CaseReport(
                        kind: kind,
                        embedSucceeded: true,
                        cropSucceeded: false,
                        saveSucceeded: false,
                        extractSucceeded: false,
                        textRoundTripPassed: false,
                        extractedText: nil,
                        cropPx: nil
                    )
                )
            }
        }

        return Report(imageLoaded: true, cases: out)
    }

    /// Backward-compatible entry for the previous single-case test.
    static func runRightCrop10PercentOnBundledTestImg() async -> CaseReport {
        let r = await runAllCrop10PercentOnBundledTestImg()
        return r.cases.first(where: { $0.kind == .right })
            ?? CaseReport(kind: .right, embedSucceeded: false, cropSucceeded: false, saveSucceeded: false, extractSucceeded: false, textRoundTripPassed: false, extractedText: nil, cropPx: nil)
    }

    /// Boundary scan for one crop direction.
    ///
    /// Phase 1 — coarse sweep **large → small** (default 50% → 0% in 10% steps) to bracket the
    /// breakdown. Phase 2 — fine drill **upward** from the last coarse pass with a 1% step until
    /// two consecutive failures.
    static func runCropPercentLimitSweepOnBundledTestImg(
        kind: CropKind,
        coarseStep: Double = 0.10,
        fineStep: Double = 0.01
    ) async -> LimitSweepReport {
        guard let img = ImagePipelineTests.loadBundledTestUIImage() else {
            return LimitSweepReport(
                imageLoaded: false, embedSucceeded: false, kind: kind,
                cases: [], maxPassingCropPercent: nil, firstFailingCropPercent: nil
            )
        }

        let expectedText = "Successful"
        let binding = await MainActor.run { WatermarkServiceTestBinding(textureVarianceThreshold: -1) }
        let service = binding.service

        let watermarked: UIImage
        do {
            watermarked = try await service.embedWatermarkSilently(into: img, text: expectedText)
        } catch {
            return LimitSweepReport(
                imageLoaded: true, embedSucceeded: false, kind: kind,
                cases: [], maxPassingCropPercent: nil, firstFailingCropPercent: nil
            )
        }

        func evaluate(percent: Double) async -> LimitCase {
            guard let cropped = crop(image: watermarked, kind: kind, percent: percent) else {
                return LimitCase(
                    kind: kind, cropPercent: percent, cropPx: nil,
                    extractSucceeded: false, textRoundTripPassed: false,
                    extractedText: nil, passed: false
                )
            }
            let px = pixelSize(of: cropped)
            let extracted = try? await service.extractWatermarkSilently(from: cropped)
            let ok = (extracted == expectedText)
            return LimitCase(
                kind: kind,
                cropPercent: percent,
                cropPx: px,
                extractSucceeded: (extracted != nil),
                textRoundTripPassed: ok,
                extractedText: extracted,
                passed: ok
            )
        }

        func roundedPercent(_ value: Double) -> Double {
            (value * 1000).rounded() / 1000
        }

        var results: [LimitCase] = []

        // --- Phase 1: coarse descending (large crop % → small) ---
        var coarsePercents: [Double] = []
        var p = 0.50
        while p >= 0 {
            coarsePercents.append(roundedPercent(p))
            p -= coarseStep
        }

        for pct in coarsePercents {
            results.append(await evaluate(percent: pct))
        }

        var maxPass = results.filter(\.passed).map(\.cropPercent).max()
        var minFailAbovePass = results
            .filter { !$0.passed && ($0.cropPercent > (maxPass ?? -1)) }
            .map(\.cropPercent)
            .min()

        // If every coarse step passed, probe upward in coarse steps.
        if minFailAbovePass == nil, maxPass != nil {
            var probe = roundedPercent((maxPass ?? 0.50) + coarseStep)
            while probe < 0.95 {
                let res = await evaluate(percent: probe)
                results.append(res)
                if res.passed {
                    maxPass = probe
                    probe = roundedPercent(probe + coarseStep)
                } else {
                    minFailAbovePass = probe
                    break
                }
            }
        }

        // --- Phase 2: fine drill upward from the coarse pass bracket ---
        if let pass = maxPass {
            let upperBound = minFailAbovePass ?? roundedPercent(pass + coarseStep)
            var current = roundedPercent(pass + fineStep)
            var fineFails = 0

            while current < upperBound - 1e-6, fineFails < 2, results.count < 120 {
                if results.contains(where: { abs($0.cropPercent - current) < 1e-4 }) {
                    current = roundedPercent(current + fineStep)
                    continue
                }
                let res = await evaluate(percent: current)
                results.append(res)
                if res.passed {
                    maxPass = current
                    fineFails = 0
                } else {
                    if minFailAbovePass == nil || current < minFailAbovePass! {
                        minFailAbovePass = current
                    }
                    fineFails += 1
                }
                current = roundedPercent(current + fineStep)
            }
        }

        let sortedCases = results.sorted { $0.cropPercent > $1.cropPercent }
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

        return LimitSweepReport(
            imageLoaded: true,
            embedSucceeded: true,
            kind: kind,
            cases: sortedCases,
            maxPassingCropPercent: maxPass,
            firstFailingCropPercent: firstFail
        )
    }

    /// Crop image using pixel-precise `cgImage` cropping.
    private static func crop(image: UIImage, kind: CropKind, percent: Double) -> UIImage? {
        guard percent >= 0, percent < 1 else {
            if percent == 0 { return image }
            return nil
        }
        guard let cg = image.cgImage else { return nil }

        let w = cg.width
        let h = cg.height
        let cutW = max(0, Int(Double(w) * percent))
        let cutH = max(0, Int(Double(h) * percent))

        let rect: CGRect
        switch kind {
        case .right:
            let newW = max(1, w - cutW)
            rect = CGRect(x: 0, y: 0, width: newW, height: h)
        case .left:
            let newW = max(1, w - cutW)
            rect = CGRect(x: cutW, y: 0, width: newW, height: h)
        case .top:
            let newH = max(1, h - cutH)
            rect = CGRect(x: 0, y: cutH, width: w, height: newH)
        case .bottom:
            let newH = max(1, h - cutH)
            rect = CGRect(x: 0, y: 0, width: w, height: newH)
        case .topLeft:
            rect = CGRect(x: cutW, y: cutH, width: max(1, w - cutW), height: max(1, h - cutH))
        case .topRight:
            rect = CGRect(x: 0, y: cutH, width: max(1, w - cutW), height: max(1, h - cutH))
        case .bottomLeft:
            rect = CGRect(x: cutW, y: 0, width: max(1, w - cutW), height: max(1, h - cutH))
        case .bottomRight:
            rect = CGRect(x: 0, y: 0, width: max(1, w - cutW), height: max(1, h - cutH))
        }

        guard let croppedCG = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: croppedCG, scale: image.scale, orientation: image.imageOrientation)
    }

    private static func pixelSize(of image: UIImage) -> (w: Int, h: Int) {
        (Int(image.size.width * image.scale), Int(image.size.height * image.scale))
    }
}
