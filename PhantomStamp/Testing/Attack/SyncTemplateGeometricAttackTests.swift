//
//  SyncTemplateGeometricAttackTests.swift
//  PhantomStamp
//
//  Manual / DEBUG validation for the DFT sync template + geometric correction stack.
//
//  Provides:
//    1. `runBasicSyncTemplateOnBundledTestImg`
//       - sanity check that embedding + extraction still round-trip when no attack happens,
//         AND that `detectGeometricTransforms` reports an effectively-identity transform on the
//         freshly-embedded image (no-op deskew expected).
//
//    2. `runRotationAndScaleLimitSweepOnBundledTestImg`
//       - sweeps rotation angles and isotropic scale factors around the embedded image and
//         measures the limit at which the extractor can still recover the original payload.
//       - reports detected (angle, scale) from `detectGeometricTransforms` for every case so
//           we can see how accurate the detector itself is independently of the bit recovery.
//       - best-effort saves the most-attacked PASS image and the first FAIL image after it to
//         the system photo library for visual inspection.
//
//  All tests use the bundled `TestImg` asset (see `ImagePipelineTests.loadBundledTestUIImage`).
//

import Foundation
import UIKit

enum SyncTemplateGeometricAttackTests {

    // ==========================================
    // MARK: - Test Binding (mirrors WatermarkCompressionAttackTests pattern)
    // ==========================================

    /// Keeps `UserSettingsStore` alive while `WatermarkService.settingsStore` is `weak`.
    /// `textureVarianceThreshold = -1` makes "variance < threshold" impossible for non-negative
    /// block variance, so every 8×8 tile is actually embedded (matches historical test behavior
    /// and isolates the geometry test from the texture-classifier).
    @MainActor
    private final class WatermarkServiceTestBinding {
        let settingsStore: UserSettingsStore
        let service: WatermarkService

        init(textureVarianceThreshold: Double, syncTemplateIntensity: Double) {
            let suite = UserDefaults(suiteName: "phantomstamp.testing.sync.\(UUID().uuidString)")!
            settingsStore = UserSettingsStore(defaults: suite)
            settingsStore.textureVarianceThreshold = textureVarianceThreshold
            settingsStore.syncTemplateIntensity = syncTemplateIntensity
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
        var extractSucceeded: Bool
        var textRoundTripPassed: Bool
        var noAttackDetectedIdentity: Bool

        var detectedAngleDegrees: Double?
        var detectedScale: Double?
        var extractedText: String?
        var watermarkedPx: (w: Int, h: Int)?

        // Sanity thresholds for the "no-attack" detection (loose enough to accommodate normal
        // FFT noise on natural images).
        static let identityAngleToleranceDegrees: Double = 0.5
        static let identityScaleTolerance: Double = 0.01
    }

    struct AttackCase: Sendable {
        enum Kind: String, Sendable { case rotation, scale }
        var kind: Kind
        /// For rotation: degrees applied by the attacker. For scale: linear factor (1.0 = identity).
        var attackParam: Double
        var attackedPx: (w: Int, h: Int)?

        var detectedAngleDegrees: Double?
        var detectedScale: Double?

        var extractSucceeded: Bool
        var textRoundTripPassed: Bool
        var extractedText: String?
    }

    struct SweepReport: Sendable {
        var imageLoaded: Bool
        var embedSucceeded: Bool

        var rotationCases: [AttackCase]
        var scaleCases: [AttackCase]

        /// Largest absolute rotation (degrees) that still produced a matching extract.
        var maxPassingAbsRotationDegrees: Double?
        /// Smallest scale factor below 1.0 that still passed; nil if none failed below 1.0.
        var minPassingScaleFactor: Double?
        /// Largest scale factor above 1.0 that still passed; nil if none failed above 1.0.
        var maxPassingScaleFactor: Double?
    }

    // ==========================================
    // MARK: - Test 1: Basic Round-Trip + Identity Detection
    // ==========================================

    /// Embeds → calls `detectGeometricTransforms` on the watermarked image → extracts.
    /// Expectations on a clean (un-attacked) image:
    ///   - extract returns the embedded text
    ///   - `detectGeometricTransforms` returns an angle within ±0.5° and a scale within ±1%
    ///     (the template peaks should sit very close to their nominal positions)
    static func runBasicSyncTemplateOnBundledTestImg(
        syncTemplateIntensity: Double = AppConstants.SettingsDefault.syncTemplateIntensity
    ) async -> BasicReport {
        guard let img = ImagePipelineTests.loadBundledTestUIImage() else {
            return BasicReport(
                imageLoaded: false, embedSucceeded: false, extractSucceeded: false,
                textRoundTripPassed: false, noAttackDetectedIdentity: false,
                detectedAngleDegrees: nil, detectedScale: nil, extractedText: nil, watermarkedPx: nil
            )
        }

        let text = "Successful"
        let binding = await MainActor.run {
            WatermarkServiceTestBinding(textureVarianceThreshold: -1, syncTemplateIntensity: syncTemplateIntensity)
        }
        let service = binding.service

        let watermarked: UIImage
        do {
            watermarked = try await service.embedWatermark(into: img, text: text)
        } catch {
            return BasicReport(
                imageLoaded: true, embedSucceeded: false, extractSucceeded: false,
                textRoundTripPassed: false, noAttackDetectedIdentity: false,
                detectedAngleDegrees: nil, detectedScale: nil, extractedText: nil, watermarkedPx: nil
            )
        }

        let pxW = Int(watermarked.size.width * watermarked.scale)
        let pxH = Int(watermarked.size.height * watermarked.scale)

        // Run the detector on the watermarked-but-unattacked image so we can see how close to
        // identity it lands. This call is OUTSIDE the normal extractWatermark flow, purely for
        // diagnostic reporting.
        let detectedAngleDeg: Double?
        let detectedScaleD: Double?
        if let ycbcr = service.convertToYCbCr(image: watermarked) {
            let t = service.detectGeometricTransforms(in: ycbcr.Y)
            detectedAngleDeg = Double(t.angle) * 180.0 / .pi
            detectedScaleD = Double(t.scale)
        } else {
            detectedAngleDeg = nil
            detectedScaleD = nil
        }

        let identityOk: Bool
        if let a = detectedAngleDeg, let s = detectedScaleD {
            identityOk = abs(a) <= BasicReport.identityAngleToleranceDegrees
                && abs(s - 1.0) <= BasicReport.identityScaleTolerance
        } else {
            identityOk = false
        }

        do {
            let extracted = try await service.extractWatermark(from: watermarked)
            return BasicReport(
                imageLoaded: true, embedSucceeded: true, extractSucceeded: true,
                textRoundTripPassed: (extracted == text), noAttackDetectedIdentity: identityOk,
                detectedAngleDegrees: detectedAngleDeg, detectedScale: detectedScaleD,
                extractedText: extracted, watermarkedPx: (pxW, pxH)
            )
        } catch {
            return BasicReport(
                imageLoaded: true, embedSucceeded: true, extractSucceeded: false,
                textRoundTripPassed: false, noAttackDetectedIdentity: identityOk,
                detectedAngleDegrees: detectedAngleDeg, detectedScale: detectedScaleD,
                extractedText: nil, watermarkedPx: (pxW, pxH)
            )
        }
    }

    // ==========================================
    // MARK: - Test 2: Rotation + Scale Limit Sweep
    // ==========================================

    /// Sweeps rotation angles and scale factors, recording the boundary between PASS and FAIL.
    ///
    /// Default sweeps:
    ///   - rotation degrees: [-15, -10, -5, -2, -1, 0, 1, 2, 5, 10, 15]
    ///   - scale factors:    [0.85, 0.90, 0.95, 0.98, 1.00, 1.02, 1.05, 1.10, 1.15]
    ///
    /// PASS = `extractWatermark` returns and the recovered text equals the embedded text.
    ///
    /// Saves the strongest passing rotation/scale attack image and the first failing one after
    /// it to the photo library (best-effort) so they can be inspected visually.
    static func runRotationAndScaleLimitSweepOnBundledTestImg(
        rotationDegrees: [Double] = [-15, -10, -5, -2, -1, 0, 1, 2, 5, 10, 15],
        scaleFactors: [Double] = [0.85, 0.90, 0.95, 0.98, 1.00, 1.02, 1.05, 1.10, 1.15],
        syncTemplateIntensity: Double = AppConstants.SettingsDefault.syncTemplateIntensity
    ) async -> SweepReport {
        guard let img = ImagePipelineTests.loadBundledTestUIImage() else {
            return SweepReport(
                imageLoaded: false, embedSucceeded: false,
                rotationCases: [], scaleCases: [],
                maxPassingAbsRotationDegrees: nil,
                minPassingScaleFactor: nil, maxPassingScaleFactor: nil
            )
        }

        let text = "Successful"
        let binding = await MainActor.run {
            WatermarkServiceTestBinding(textureVarianceThreshold: -1, syncTemplateIntensity: syncTemplateIntensity)
        }
        let service = binding.service

        let watermarked: UIImage
        do {
            watermarked = try await service.embedWatermark(into: img, text: text)
        } catch {
            return SweepReport(
                imageLoaded: true, embedSucceeded: false,
                rotationCases: [], scaleCases: [],
                maxPassingAbsRotationDegrees: nil,
                minPassingScaleFactor: nil, maxPassingScaleFactor: nil
            )
        }

        // -----------------------
        // Rotation sweep
        // -----------------------
        var rotationCases: [AttackCase] = []
        rotationCases.reserveCapacity(rotationDegrees.count)
        var rotationAttackedImages: [Double: UIImage] = [:]

        for deg in rotationDegrees {
            guard let attacked = rotate(image: watermarked, degrees: deg) else {
                rotationCases.append(AttackCase(
                    kind: .rotation, attackParam: deg, attackedPx: nil,
                    detectedAngleDegrees: nil, detectedScale: nil,
                    extractSucceeded: false, textRoundTripPassed: false, extractedText: nil
                ))
                continue
            }
            rotationAttackedImages[deg] = attacked

            let attackedPx = pixelSize(of: attacked)
            let (detectAngle, detectScale) = detectorOutputDegreesScale(service: service, image: attacked)

            let recovered = try? await service.extractWatermark(from: attacked)
            let passed = (recovered == text)
            rotationCases.append(AttackCase(
                kind: .rotation,
                attackParam: deg,
                attackedPx: attackedPx,
                detectedAngleDegrees: detectAngle,
                detectedScale: detectScale,
                extractSucceeded: (recovered != nil),
                textRoundTripPassed: passed,
                extractedText: recovered
            ))
        }

        // -----------------------
        // Scale sweep
        // -----------------------
        var scaleCases: [AttackCase] = []
        scaleCases.reserveCapacity(scaleFactors.count)
        var scaleAttackedImages: [Double: UIImage] = [:]

        for factor in scaleFactors {
            guard let attacked = scale(image: watermarked, factor: factor) else {
                scaleCases.append(AttackCase(
                    kind: .scale, attackParam: factor, attackedPx: nil,
                    detectedAngleDegrees: nil, detectedScale: nil,
                    extractSucceeded: false, textRoundTripPassed: false, extractedText: nil
                ))
                continue
            }
            scaleAttackedImages[factor] = attacked

            let attackedPx = pixelSize(of: attacked)
            let (detectAngle, detectScale) = detectorOutputDegreesScale(service: service, image: attacked)

            let recovered = try? await service.extractWatermark(from: attacked)
            let passed = (recovered == text)
            scaleCases.append(AttackCase(
                kind: .scale,
                attackParam: factor,
                attackedPx: attackedPx,
                detectedAngleDegrees: detectAngle,
                detectedScale: detectScale,
                extractSucceeded: (recovered != nil),
                textRoundTripPassed: passed,
                extractedText: recovered
            ))
        }

        // -----------------------
        // Aggregate the limits
        // -----------------------

        // Maximum |rotation| that still passed → robust angular tolerance.
        let passingAbsRotations = rotationCases.filter { $0.textRoundTripPassed }.map { abs($0.attackParam) }
        let maxRot = passingAbsRotations.max()

        // Scale extremes that still passed (smallest below 1.0 and largest above 1.0).
        let passingScales = scaleCases.filter { $0.textRoundTripPassed }.map { $0.attackParam }
        let minPassScale = passingScales.filter { $0 <= 1.0 }.min()
        let maxPassScale = passingScales.filter { $0 >= 1.0 }.max()

        // -----------------------
        // Photo Library snapshots (best effort): hardest passing + first failing-after-pass.
        // -----------------------
        if let rotPassDeg = passingAbsRotations.sorted(by: { $0 > $1 }).first {
            // Pick the case whose absolute rotation equals rotPassDeg (favor the one closer to 0
            // among ties — typically there's at most one entry per ±deg anyway).
            if let matched = rotationCases.first(where: {
                $0.textRoundTripPassed && abs($0.attackParam) == rotPassDeg
            }), let img = rotationAttackedImages[matched.attackParam] {
                try? await PhotoLibraryExporter.saveToPhotoLibrary(img)
            }
        }
        // First failing rotation > maxRot (if any). Look in increasing |deg| order.
        if let failed = rotationCases
            .filter({ !$0.textRoundTripPassed })
            .sorted(by: { abs($0.attackParam) < abs($1.attackParam) })
            .first(where: { (maxRot ?? -1) < abs($0.attackParam) }),
           let img = rotationAttackedImages[failed.attackParam] {
            try? await PhotoLibraryExporter.saveToPhotoLibrary(img)
        }
        if let maxScale = maxPassScale, let img = scaleAttackedImages[maxScale] {
            try? await PhotoLibraryExporter.saveToPhotoLibrary(img)
        }
        if let minScale = minPassScale, let img = scaleAttackedImages[minScale] {
            try? await PhotoLibraryExporter.saveToPhotoLibrary(img)
        }

        return SweepReport(
            imageLoaded: true,
            embedSucceeded: true,
            rotationCases: rotationCases,
            scaleCases: scaleCases,
            maxPassingAbsRotationDegrees: maxRot,
            minPassingScaleFactor: minPassScale,
            maxPassingScaleFactor: maxPassScale
        )
    }

    // ==========================================
    // MARK: - Attack Helpers
    // ==========================================

    /// Center-pivot rotation into a SAME-SIZE canvas. Corners that fall outside the canvas are
    /// clipped (filled with the default UIGraphicsImageRenderer background, i.e. transparent →
    /// black after rasterization in the YCbCr pipeline). Matches the typical "attacker rotates
    /// then re-saves" workflow where the file dimensions don't change.
    private static func rotate(image: UIImage, degrees: Double) -> UIImage? {
        let pxSize = pixelSize(of: image)
        guard pxSize.w > 0, pxSize.h > 0 else { return nil }

        let radians = CGFloat(degrees) * .pi / 180.0
        let size = CGSize(width: pxSize.w, height: pxSize.h)

        // scale=1 keeps the renderer in raw pixel units so we get exactly w×h output.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let cg = context.cgContext
            cg.translateBy(x: size.width / 2.0, y: size.height / 2.0)
            cg.rotate(by: radians)
            cg.translateBy(x: -size.width / 2.0, y: -size.height / 2.0)
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Isotropic resize to `floor(w·factor) × floor(h·factor)` pixels. Simulates an attacker who
    /// saved the image at a different resolution. Returned image has `scale = 1`.
    private static func scale(image: UIImage, factor: Double) -> UIImage? {
        let pxSize = pixelSize(of: image)
        let newW = max(1, Int(Double(pxSize.w) * factor))
        let newH = max(1, Int(Double(pxSize.h) * factor))
        let size = CGSize(width: newW, height: newH)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // ==========================================
    // MARK: - Diagnostic Helpers
    // ==========================================

    /// Runs `detectGeometricTransforms` once for diagnostic reporting. Does NOT affect the
    /// subsequent `extractWatermark` call (which runs its own detection internally).
    private static func detectorOutputDegreesScale(service: WatermarkService, image: UIImage) -> (deg: Double?, scale: Double?) {
        guard let ycbcr = service.convertToYCbCr(image: image) else {
            return (nil, nil)
        }
        let t = service.detectGeometricTransforms(in: ycbcr.Y)
        return (Double(t.angle) * 180.0 / .pi, Double(t.scale))
    }

    private static func pixelSize(of image: UIImage) -> (w: Int, h: Int) {
        (Int(image.size.width * image.scale), Int(image.size.height * image.scale))
    }

    // ==========================================
    // MARK: - DEBUG print entry points
    // ==========================================

    static func runBasicAndPrint(
        syncTemplateIntensity: Double = AppConstants.SettingsDefault.syncTemplateIntensity
    ) async {
        #if DEBUG
        let t0 = CFAbsoluteTimeGetCurrent()
        let r = await runBasicSyncTemplateOnBundledTestImg(syncTemplateIntensity: syncTemplateIntensity)
        let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000

        let overallPass = r.imageLoaded && r.embedSucceeded && r.extractSucceeded
            && r.textRoundTripPassed && r.noAttackDetectedIdentity
        let status = overallPass ? "PASS" : "FAIL"
        print("[SyncTemplateGeometricAttackTests] \(status) Basic — no-attack round-trip + identity detection")
        let px = r.watermarkedPx.map { "\($0.w)x\($0.h)px" } ?? "nil"
        let detAng = r.detectedAngleDegrees.map { String(format: "%.4f°", $0) } ?? "nil"
        let detSc = r.detectedScale.map { String(format: "%.6f", $0) } ?? "nil"
        print("  - imageLoaded:      \(r.imageLoaded ? "PASS" : "FAIL")")
        print("  - embed:            \(r.embedSucceeded ? "PASS" : "FAIL")  px=\(px)")
        print("  - extract:          \(r.extractSucceeded ? "PASS" : "FAIL")")
        print("  - text round-trip:  \(r.textRoundTripPassed ? "PASS" : "FAIL")  extracted=\(r.extractedText ?? "nil")")
        print("  - identity detect:  \(r.noAttackDetectedIdentity ? "PASS" : "FAIL")  angle=\(detAng) scale=\(detSc)")
        print("  - elapsed:          \(String(format: "%.2f", dtMs)) ms")
        #endif
    }

    static func runLimitSweepAndPrint(
        syncTemplateIntensity: Double = AppConstants.SettingsDefault.syncTemplateIntensity
    ) async {
        #if DEBUG
        let t0 = CFAbsoluteTimeGetCurrent()
        let r = await runRotationAndScaleLimitSweepOnBundledTestImg(syncTemplateIntensity: syncTemplateIntensity)
        let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000

        let overallOk = r.imageLoaded && r.embedSucceeded
        let status = overallOk ? "RAN" : "FAIL"
        print("[SyncTemplateGeometricAttackTests] \(status) LimitSweep — rotation & scale tolerance")
        let rotLimit = r.maxPassingAbsRotationDegrees.map { String(format: "±%.2f°", $0) } ?? "none"
        let minSc = r.minPassingScaleFactor.map { String(format: "%.3f", $0) } ?? "none"
        let maxSc = r.maxPassingScaleFactor.map { String(format: "%.3f", $0) } ?? "none"
        print("  - rotation limit:   \(rotLimit)")
        print("  - scale range:      [\(minSc), \(maxSc)]")

        print("  - rotation cases:")
        for c in r.rotationCases {
            let detAng = c.detectedAngleDegrees.map { String(format: "%.3f°", $0) } ?? "nil"
            let detSc = c.detectedScale.map { String(format: "%.4f", $0) } ?? "nil"
            let pxStr = c.attackedPx.map { "\($0.w)x\($0.h)" } ?? "nil"
            let pass = c.textRoundTripPassed ? "PASS" : "FAIL"
            let extracted = c.extractedText ?? "nil"
            print("      \(pass)  attack=\(String(format: "%+6.2f°", c.attackParam))  px=\(pxStr)  detected(angle=\(detAng), scale=\(detSc))  extracted=\(extracted)")
        }
        print("  - scale cases:")
        for c in r.scaleCases {
            let detAng = c.detectedAngleDegrees.map { String(format: "%.3f°", $0) } ?? "nil"
            let detSc = c.detectedScale.map { String(format: "%.4f", $0) } ?? "nil"
            let pxStr = c.attackedPx.map { "\($0.w)x\($0.h)" } ?? "nil"
            let pass = c.textRoundTripPassed ? "PASS" : "FAIL"
            let extracted = c.extractedText ?? "nil"
            print("      \(pass)  attack=\(String(format: "%5.3fx", c.attackParam))  px=\(pxStr)  detected(angle=\(detAng), scale=\(detSc))  extracted=\(extracted)")
        }
        print("  - elapsed:          \(String(format: "%.2f", dtMs)) ms")
        #endif
    }
}
