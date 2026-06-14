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
        if let ycbcr = service.convertToYCbCr(image: damaged) {
            identityPresent = service.detectGeometricTransformCandidates(in: ycbcr.Y)
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
        if let ycbcr = service.convertToYCbCr(image: rotated) {
            transformCandidate = service.detectGeometricTransformCandidates(in: ycbcr.Y)
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
}
