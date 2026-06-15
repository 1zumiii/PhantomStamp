//
//  WatermarkLocalDamageAttackTests.swift
//  PhantomStamp
//
//  Manual / DEBUG regression for the failure mode where a local high-contrast edit used to
//  hallucinate a global FFT transform and destroy every healthy DCT tile during deskew.
//

import UIKit

enum WatermarkLocalDamageAttackTests {
    struct Report: Sendable {
        var imageLoaded: Bool
        var embedSucceeded: Bool
        var identityCandidatePresent: Bool
        var extractSucceeded: Bool
        var extractedText: String?
    }

    struct RotationReport: Sendable {
        var imageLoaded: Bool
        var embedSucceeded: Bool
        var transformCandidatePresent: Bool
        var detectedAngleDegrees: Double?
        var extractSucceeded: Bool
        var extractedText: String?
    }

    struct DownscaledDamageReport: Sendable {
        var imageLoaded: Bool
        var embedSucceeded: Bool
        var rejectedFalsePositive: Bool
        var extractedText: String?
    }

    @MainActor
    static func runDiagonalScribbleOnBundledTestImg() async -> Report {
        guard let image = ImagePipelineTests.loadBundledTestUIImage() else {
            return Report(
                imageLoaded: false,
                embedSucceeded: false,
                identityCandidatePresent: false,
                extractSucceeded: false,
                extractedText: nil
            )
        }

        let suite = UserDefaults(
            suiteName: "phantomstamp.testing.local-damage.\(UUID().uuidString)"
        )!
        let settings = UserSettingsStore(defaults: suite)
        settings.textureVarianceThreshold = -1
        let service = WatermarkService()
        service.settingsStore = settings
        let expectedText = "Successful"

        guard let watermarked = try? await service.embedWatermarkSilently(
            into: image,
            text: expectedText
        ) else {
            return Report(
                imageLoaded: true,
                embedSucceeded: false,
                identityCandidatePresent: false,
                extractSucceeded: false,
                extractedText: nil
            )
        }

        let damaged = drawHighContrastScribble(on: watermarked)
        let identityPresent: Bool
        if let ycbcr = service.algorithms.convertToYCbCr(image: damaged) {
            identityPresent = service.algorithms.detectGeometricTransformCandidates(in: ycbcr.Y)
                .contains(where: \.isIdentity)
        } else {
            identityPresent = false
        }

        let extracted = try? await service.extractWatermarkSilently(from: damaged)
        return Report(
            imageLoaded: true,
            embedSucceeded: true,
            identityCandidatePresent: identityPresent,
            extractSucceeded: extracted == expectedText,
            extractedText: extracted
        )
    }

    @MainActor
    static func runAndPrint() async {
        #if DEBUG
        let report = await runDiagonalScribbleOnBundledTestImg()
        let passed = report.imageLoaded
            && report.embedSucceeded
            && report.identityCandidatePresent
            && report.extractSucceeded
        print(
            "[WatermarkLocalDamageAttackTests] \(passed ? "PASS" : "FAIL") "
                + "diagonal scribble: identityCandidate=\(report.identityCandidatePresent) "
                + "text=\(report.extractedText ?? "nil")"
        )
        #endif
    }

    @MainActor
    static func runRotationCandidateOnBundledTestImg(
        degrees: Double = 8
    ) async -> RotationReport {
        guard let image = ImagePipelineTests.loadBundledTestUIImage() else {
            return RotationReport(
                imageLoaded: false,
                embedSucceeded: false,
                transformCandidatePresent: false,
                detectedAngleDegrees: nil,
                extractSucceeded: false,
                extractedText: nil
            )
        }

        let suite = UserDefaults(
            suiteName: "phantomstamp.testing.geometry-candidate.\(UUID().uuidString)"
        )!
        let settings = UserSettingsStore(defaults: suite)
        settings.textureVarianceThreshold = -1
        let service = WatermarkService()
        service.settingsStore = settings
        let expectedText = "Successful"

        guard let watermarked = try? await service.embedWatermarkSilently(
            into: image,
            text: expectedText
        ) else {
            return RotationReport(
                imageLoaded: true,
                embedSucceeded: false,
                transformCandidatePresent: false,
                detectedAngleDegrees: nil,
                extractSucceeded: false,
                extractedText: nil
            )
        }

        let rotated = rotate(image: watermarked, degrees: degrees)
        let transformCandidate: GeometricTransformCandidate?
        if let ycbcr = service.algorithms.convertToYCbCr(image: rotated) {
            transformCandidate = service.algorithms.detectGeometricTransformCandidates(in: ycbcr.Y)
                .first(where: { !$0.isIdentity })
        } else {
            transformCandidate = nil
        }

        let extracted = try? await service.extractWatermarkSilently(from: rotated)
        return RotationReport(
            imageLoaded: true,
            embedSucceeded: true,
            transformCandidatePresent: transformCandidate != nil,
            detectedAngleDegrees: transformCandidate.map {
                Double($0.angle) * 180 / .pi
            },
            extractSucceeded: extracted == expectedText,
            extractedText: extracted
        )
    }

    @MainActor
    static func runRotationAndPrint(degrees: Double = 8) async {
        #if DEBUG
        let report = await runRotationCandidateOnBundledTestImg(degrees: degrees)
        let angleAccurate = report.detectedAngleDegrees.map {
            abs($0 - degrees) <= 0.5
        } ?? false
        let passed = report.imageLoaded
            && report.embedSucceeded
            && report.transformCandidatePresent
            && angleAccurate
            && report.extractSucceeded
        print(
            "[WatermarkLocalDamageAttackTests] \(passed ? "PASS" : "FAIL") "
                + "rotation \(degrees)deg: candidate="
                + "\(report.detectedAngleDegrees.map { String(format: "%.4f", $0) } ?? "nil")deg "
                + "text=\(report.extractedText ?? "nil")"
        )
        #endif
    }

    @MainActor
    static func runExpandedRotationAndPrint(
        degrees: Double,
        padding: ImageRotationPadding
    ) async {
        #if DEBUG
        guard let image = ImagePipelineTests.loadBundledTestUIImage() else {
            print("[WatermarkLocalDamageAttackTests] FAIL expanded rotation: bundled image missing")
            return
        }

        let suite = UserDefaults(
            suiteName: "phantomstamp.testing.expanded-rotation.\(UUID().uuidString)"
        )!
        let settings = UserSettingsStore(defaults: suite)
        settings.textureVarianceThreshold = -1
        let service = WatermarkService()
        service.settingsStore = settings
        let expectedText = "Successful"

        guard let watermarked = try? await service.embedWatermarkSilently(
            into: image,
            text: expectedText
        ), let rotated = ImageRotationUtils.rotateExpandingCanvas(
            image: watermarked,
            degrees: degrees,
            padding: padding
        ) else {
            print("[WatermarkLocalDamageAttackTests] FAIL expanded rotation: preparation failed")
            return
        }

        let started = CFAbsoluteTimeGetCurrent()
        let extracted = try? await service.extractWatermarkSilently(from: rotated)
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        let pixels = WatermarkAttackTestHarness.pixelSize(of: rotated)
        let passed = extracted == expectedText
        print(
            "[WatermarkLocalDamageAttackTests] \(passed ? "PASS" : "FAIL") "
                + "expanded rotation \(degrees)deg padding=\(padding.rawValue) "
                + "pixels=\(pixels.w)x\(pixels.h) "
                + "elapsed=\(String(format: "%.3f", elapsed))s "
                + "text=\(extracted ?? "nil")"
        )
        #endif
    }

    @MainActor
    static func runBatchExtractionAndPrint(fileCount: Int = 3) async {
        #if DEBUG
        guard let image = ImagePipelineTests.loadBundledTestUIImage() else {
            print("[WatermarkLocalDamageAttackTests] FAIL batch extraction: bundled image missing")
            return
        }

        let suite = UserDefaults(
            suiteName: "phantomstamp.testing.batch-extraction.\(UUID().uuidString)"
        )!
        let settings = UserSettingsStore(defaults: suite)
        settings.textureVarianceThreshold = -1
        settings.autoLogWatermarkEmbedToHistory = false
        let service = WatermarkService()
        service.settingsStore = settings
        let expectedText = "Batch OK"

        guard let watermarked = try? await service.embedWatermarkSilently(
            into: image,
            text: expectedText
        ) else {
            print("[WatermarkLocalDamageAttackTests] FAIL batch extraction: embedding failed")
            return
        }

        let count = max(2, fileCount)
        let started = CFAbsoluteTimeGetCurrent()
        let results = await service.extractWatermarkBestEffortWithDiagnostics(
            from: Array(repeating: watermarked, count: count),
            sourceImageNames: (0..<count).map { "Batch-\($0 + 1).png" }
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        let passed = results.allSatisfy { $0?.text == expectedText }
        print(
            "[WatermarkLocalDamageAttackTests] \(passed ? "PASS" : "FAIL") "
                + "batch extraction files=\(count) "
                + "elapsed=\(String(format: "%.3f", elapsed))s "
                + "success=\(results.compactMap { $0 }.count)/\(count)"
        )
        #endif
    }

    @MainActor
    static func runDownscaledScribbleOnBundledTestImg(
        scale: CGFloat = 0.518
    ) async -> DownscaledDamageReport {
        guard let image = ImagePipelineTests.loadBundledTestUIImage() else {
            return DownscaledDamageReport(
                imageLoaded: false,
                embedSucceeded: false,
                rejectedFalsePositive: false,
                extractedText: nil
            )
        }

        let suite = UserDefaults(
            suiteName: "phantomstamp.testing.downscaled-local-damage.\(UUID().uuidString)"
        )!
        let settings = UserSettingsStore(defaults: suite)
        settings.textureVarianceThreshold = -1
        let service = WatermarkService()
        service.settingsStore = settings
        let expectedText = "Successful"

        guard let watermarked = try? await service.embedWatermarkSilently(
            into: image,
            text: expectedText
        ) else {
            return DownscaledDamageReport(
                imageLoaded: true,
                embedSucceeded: false,
                rejectedFalsePositive: false,
                extractedText: nil
            )
        }

        let resized = resize(image: watermarked, scale: scale)
        let damaged = drawHighContrastScribble(on: resized)
        let extracted = try? await service.extractWatermarkSilently(from: damaged)
        return DownscaledDamageReport(
            imageLoaded: true,
            embedSucceeded: true,
            rejectedFalsePositive: extracted == nil || extracted == expectedText,
            extractedText: extracted
        )
    }

    @MainActor
    static func runDownscaledScribbleAndPrint(scale: CGFloat = 0.518) async {
        #if DEBUG
        let report = await runDownscaledScribbleOnBundledTestImg(scale: scale)
        let passed = report.imageLoaded
            && report.embedSucceeded
            && report.rejectedFalsePositive
        let disposition: String
        if report.extractedText == "Successful" {
            disposition = "correct extraction"
        } else if report.extractedText == nil {
            disposition = "safe rejection"
        } else {
            disposition = "FALSE POSITIVE"
        }
        print(
            "[WatermarkLocalDamageAttackTests] \(passed ? "PASS" : "FAIL") "
                + "downscaled scribble scale=\(String(format: "%.3f", scale)): "
                + "\(disposition), text=\(report.extractedText ?? "nil")"
        )
        #endif
    }

    private static func drawHighContrastScribble(on image: UIImage) -> UIImage {
        let pixelSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { context in
            image.draw(in: CGRect(origin: .zero, size: pixelSize))

            let cg = context.cgContext
            let lineWidth = max(18, min(pixelSize.width, pixelSize.height) * 0.025)
            cg.setLineCap(.round)

            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(lineWidth * 1.8)
            cg.move(to: CGPoint(x: pixelSize.width * 0.08, y: pixelSize.height * 0.12))
            cg.addLine(to: CGPoint(x: pixelSize.width * 0.92, y: pixelSize.height * 0.88))
            cg.strokePath()

            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(lineWidth)
            cg.move(to: CGPoint(x: pixelSize.width * 0.08, y: pixelSize.height * 0.12))
            cg.addLine(to: CGPoint(x: pixelSize.width * 0.92, y: pixelSize.height * 0.88))
            cg.strokePath()
        }
    }

    private static func rotate(image: UIImage, degrees: Double) -> UIImage {
        let pixelSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(origin: .zero, size: pixelSize))
            cg.translateBy(x: pixelSize.width / 2, y: pixelSize.height / 2)
            cg.rotate(by: CGFloat(degrees) * .pi / 180)
            image.draw(
                in: CGRect(
                    x: -pixelSize.width / 2,
                    y: -pixelSize.height / 2,
                    width: pixelSize.width,
                    height: pixelSize.height
                )
            )
        }
    }

    private static func resize(image: UIImage, scale: CGFloat) -> UIImage {
        let sourceSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let targetSize = CGSize(
            width: max(1, (sourceSize.width * scale).rounded()),
            height: max(1, (sourceSize.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
