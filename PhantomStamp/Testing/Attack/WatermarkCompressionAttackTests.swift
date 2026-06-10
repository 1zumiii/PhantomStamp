//
//  WatermarkCompressionAttackTests.swift
//  PhantomStamp
//
//  Manual / DEBUG validation focused on JPEG recompression resistance.
//  Uses the app's live `WatermarkService` + `UserSettingsStore` (see harness).
//

import Foundation
import UIKit

enum WatermarkCompressionAttackTests {

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
        var identityExtractPassed: Bool
        var cases: [AttackCase]
        var lowestPassingQuality: Double?
        var firstFailingQuality: Double?
    }

  // MARK: - Test 1: Single-Point Compression

    static func runBasicJpegCompressionOnBundledTestImg(
        service: WatermarkService,
        settingsStore: UserSettingsStore,
        quality: Double = 0.90
    ) async -> BasicReport {
        guard let img = ImagePipelineTests.loadBundledTestUIImage() else {
            return BasicReport(
                imageLoaded: false, embedSucceeded: false, recompressSucceeded: false,
                extractSucceeded: false, textRoundTripPassed: false,
                extractedText: nil, jpegBytes: nil, attackedPx: nil, quality: quality
            )
        }

        let expectedText = "Successful"

        let watermarked: UIImage
        do {
            watermarked = try await WatermarkAttackTestHarness.embedForAttackTest(
                service: service, settingsStore: settingsStore, image: img, text: expectedText
            )
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
        let px = WatermarkAttackTestHarness.pixelSize(of: attacked)

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

    static func runMediumJpegCompressionOnBundledTestImg(
        service: WatermarkService,
        settingsStore: UserSettingsStore,
        quality: Double = 0.60
    ) async -> BasicReport {
        await runBasicJpegCompressionOnBundledTestImg(
            service: service, settingsStore: settingsStore, quality: quality
        )
    }

  // MARK: - Test 2: Smart Boundary Sweep

    static func runJpegQualityLimitSweepOnBundledTestImg(
        service: WatermarkService,
        settingsStore: UserSettingsStore,
        coarseQualities: [Double] = [0.95, 0.90, 0.85, 0.80, 0.70, 0.60, 0.50, 0.40, 0.35, 0.30, 0.25, 0.20, 0.15, 0.10, 0.05],
        fineStep: Double = 0.01
    ) async -> SweepReport {
        guard let img = ImagePipelineTests.loadBundledTestUIImage() else {
            return SweepReport(
                imageLoaded: false, embedSucceeded: false, identityExtractPassed: false,
                cases: [], lowestPassingQuality: nil, firstFailingQuality: nil
            )
        }

        let expectedText = "Successful"

        let watermarked: UIImage
        do {
            watermarked = try await WatermarkAttackTestHarness.embedForAttackTest(
                service: service, settingsStore: settingsStore, image: img, text: expectedText
            )
        } catch {
            return SweepReport(
                imageLoaded: true, embedSucceeded: false, identityExtractPassed: false,
                cases: [], lowestPassingQuality: nil, firstFailingQuality: nil
            )
        }

        try? await PhotoLibraryExporter.saveToPhotoLibrary(watermarked)

        let identityExtracted = try? await service.extractWatermarkSilently(from: watermarked)
        let identityPassed = (identityExtracted == expectedText)
        #if DEBUG
        print("[WatermarkCompressionAttackTests] identity extract \(identityPassed ? "PASS" : "FAIL") text=\(identityExtracted ?? "nil")")
        #endif

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
                attackedPx: WatermarkAttackTestHarness.pixelSize(of: attacked),
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
            identityExtractPassed: identityPassed,
            cases: sortedCases,
            lowestPassingQuality: lowestPassQ,
            firstFailingQuality: firstFailQ
        )
    }

  // MARK: - DEBUG print

    static func runBasicAndPrint(
        service: WatermarkService,
        settingsStore: UserSettingsStore,
        quality: Double = 0.90
    ) async {
        #if DEBUG
        let t0 = CFAbsoluteTimeGetCurrent()
        let r = await runBasicJpegCompressionOnBundledTestImg(
            service: service, settingsStore: settingsStore, quality: quality
        )
        let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000

        let overallPass = r.imageLoaded && r.embedSucceeded && r.recompressSucceeded
            && r.extractSucceeded && r.textRoundTripPassed
        print("[WatermarkCompressionAttackTests] \(overallPass ? "PASS" : "FAIL") Basic q=\(String(format: "%.2f", r.quality)) text=\(r.extractedText ?? "nil") (\(String(format: "%.2f", dtMs)) ms)")
        #endif
    }

    static func runLimitSweepAndPrint(
        service: WatermarkService,
        settingsStore: UserSettingsStore
    ) async {
        #if DEBUG
        let r = await runJpegQualityLimitSweepOnBundledTestImg(
            service: service, settingsStore: settingsStore
        )
        let lowest = r.lowestPassingQuality.map { String(format: "%.2f", $0) } ?? "none"
        print("[WatermarkCompressionAttackTests] LimitSweep identity=\(r.identityExtractPassed ? "PASS" : "FAIL") lowestPass=\(lowest) cases=\(r.cases.count)")
        for c in r.cases {
            print("  - q=\(String(format: "%.2f", c.quality)) \(c.passed ? "PASS" : "FAIL") extracted=\(c.extractedText ?? "nil")")
        }
        #endif
    }
}
