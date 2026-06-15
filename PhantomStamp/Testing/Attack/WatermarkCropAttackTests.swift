//
//  WatermarkCropAttackTests.swift
//  PhantomStamp
//
//  Manual / DEBUG validation focused on edge-crop resistance.
//  Uses the app's live `WatermarkService` + `UserSettingsStore` (see harness).
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
        var identityExtractPassed: Bool
        var kind: CropKind
        var cases: [AttackCase]
        var maxPassingCropPercent: Double?
        var firstFailingCropPercent: Double?
    }

    typealias LimitCase = AttackCase
    typealias LimitSweepReport = SweepReport

  // MARK: - Test 1: Single-Point Crop

    static func runBasicCropOnBundledTestImg(
        service: WatermarkService,
        settingsStore: UserSettingsStore,
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

        let expectedText = WatermarkAttackTestHarness.referencePayload

        let watermarked: UIImage
        do {
            watermarked = try await WatermarkAttackTestHarness.embedForAttackTest(
                service: service, settingsStore: settingsStore, image: img, text: expectedText
            )
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

        let px = WatermarkAttackTestHarness.pixelSize(of: cropped)

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

    static func runRightCrop10PercentOnBundledTestImg(
        service: WatermarkService,
        settingsStore: UserSettingsStore
    ) async -> CaseReport {
        let r = await runBasicCropOnBundledTestImg(
            service: service, settingsStore: settingsStore, kind: .right, percent: 0.10
        )
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

  // MARK: - Test 2: All Directions at 10%

    static func runAllCrop10PercentOnBundledTestImg(
        service: WatermarkService,
        settingsStore: UserSettingsStore
    ) async -> Report {
        guard let img = ImagePipelineTests.loadBundledTestUIImage() else {
            return Report(imageLoaded: false, embedSucceeded: false, cases: [])
        }

        let expectedText = WatermarkAttackTestHarness.referencePayload

        let watermarked: UIImage
        do {
            watermarked = try await WatermarkAttackTestHarness.embedForAttackTest(
                service: service, settingsStore: settingsStore, image: img, text: expectedText
            )
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

            let px = WatermarkAttackTestHarness.pixelSize(of: cropped)
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

  // MARK: - Test 3: Smart Boundary Sweep

    static func runCropPercentLimitSweepOnBundledTestImg(
        service: WatermarkService,
        settingsStore: UserSettingsStore,
        kind: CropKind,
        coarsePercents: [Double] = [0.0, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.45, 0.50],
        fineStep: Double = 0.01
    ) async -> SweepReport {
        guard let img = ImagePipelineTests.loadBundledTestUIImage() else {
            return SweepReport(
                imageLoaded: false, embedSucceeded: false, identityExtractPassed: false,
                kind: kind, cases: [], maxPassingCropPercent: nil, firstFailingCropPercent: nil
            )
        }

        let expectedText = WatermarkAttackTestHarness.referencePayload

        let watermarked: UIImage
        do {
            watermarked = try await WatermarkAttackTestHarness.embedForAttackTest(
                service: service, settingsStore: settingsStore, image: img, text: expectedText
            )
        } catch {
            return SweepReport(
                imageLoaded: true, embedSucceeded: false, identityExtractPassed: false,
                kind: kind, cases: [], maxPassingCropPercent: nil, firstFailingCropPercent: nil
            )
        }

        try? await PhotoLibraryExporter.saveToPhotoLibrary(watermarked)

        let identityExtracted = try? await service.extractWatermarkSilently(from: watermarked)
        let identityPassed = (identityExtracted == expectedText)
        #if DEBUG
        print("[WatermarkCropAttackTests] identity extract \(identityPassed ? "PASS" : "FAIL") text=\(identityExtracted ?? "nil")")
        #endif

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
                cropPx: WatermarkAttackTestHarness.pixelSize(of: cropped),
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
            identityExtractPassed: identityPassed,
            kind: kind,
            cases: sortedCases,
            maxPassingCropPercent: maxPass,
            firstFailingCropPercent: firstFail
        )
    }

  // MARK: - Attack Helpers

    /// Pixel-exact `cgImage` crop. `percent == 0` returns the image unchanged (no re-render).
    private static func crop(image: UIImage, kind: CropKind, percent: Double) -> UIImage? {
        if percent == 0 { return image }
        guard percent > 0, percent < 1 else { return nil }
        guard let cg = image.cgImage else { return nil }

        let w = cg.width
        let h = cg.height
        let cutW = max(0, Int(Double(w) * percent))
        let cutH = max(0, Int(Double(h) * percent))

        let rect: CGRect
        switch kind {
        case .right:
            rect = CGRect(x: 0, y: 0, width: max(1, w - cutW), height: h)
        case .left:
            rect = CGRect(x: cutW, y: 0, width: max(1, w - cutW), height: h)
        case .top:
            rect = CGRect(x: 0, y: cutH, width: w, height: max(1, h - cutH))
        case .bottom:
            rect = CGRect(x: 0, y: 0, width: w, height: max(1, h - cutH))
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
        return UIImage(cgImage: croppedCG, scale: 1.0, orientation: .up)
    }

    private static func roundedPercent(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

  // MARK: - DEBUG print

    static func runBasicAndPrint(
        service: WatermarkService,
        settingsStore: UserSettingsStore,
        kind: CropKind = .right,
        percent: Double = 0.10
    ) async {
        #if DEBUG
        let r = await runBasicCropOnBundledTestImg(
            service: service, settingsStore: settingsStore, kind: kind, percent: percent
        )
        let ok = r.imageLoaded && r.embedSucceeded && r.cropSucceeded
            && r.extractSucceeded && r.textRoundTripPassed
        print("[WatermarkCropAttackTests] \(ok ? "PASS" : "FAIL") \(kind.displayName) \(String(format: "%.0f%%", percent * 100)) text=\(r.extractedText ?? "nil")")
        #endif
    }

    static func runLimitSweepAndPrint(
        service: WatermarkService,
        settingsStore: UserSettingsStore,
        kind: CropKind = .right
    ) async {
        #if DEBUG
        let r = await runCropPercentLimitSweepOnBundledTestImg(
            service: service, settingsStore: settingsStore, kind: kind
        )
        let maxPass = r.maxPassingCropPercent.map { String(format: "%.1f%%", $0 * 100) } ?? "none"
        print("[WatermarkCropAttackTests] LimitSweep identity=\(r.identityExtractPassed ? "PASS" : "FAIL") \(kind.displayName) maxPass=\(maxPass) cases=\(r.cases.count)")
        for c in r.cases {
            print("  - crop=\(String(format: "%.1f%%", c.cropPercent * 100)) \(c.passed ? "PASS" : "FAIL") extracted=\(c.extractedText ?? "nil")")
        }
        #endif
    }
}
