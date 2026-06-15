//
//  SyncTemplateGeometricAttackTests.swift
//  PhantomStamp
//
//  Manual / DEBUG validation focused EXCLUSIVELY on the geometric-detection module
//  (`detectGeometricTransforms`). The downstream bit-extraction pipeline (sync header scan,
//  majority voting, FEC decode) is intentionally NOT exercised here — those layers have their
//  own tests and can mask / amplify problems unrelated to the DFT sync template.
//
//  What we measure:
//      "Given a watermarked image that an attacker has rotated by θ degrees and isotropically
//       scaled by factor s, does `detectGeometricTransforms` return (angle ≈ θ, scale ≈ s)?"
//
//  Provided tests:
//
//    1. `runBasicSyncTemplateOnBundledTestImg`
//       - identity case (no attack): expects `detectGeometricTransforms` ≈ (0°, 1×)
//
//    2. `runRotationAndScaleLimitSweepOnBundledTestImg`
//       - Rotation sweep: applies a known θ, asks the detector to recover it.
//       - Scale sweep: same for s.
//       - For each case, records the detected (angle, scale) AND its absolute / relative error.
//       - Aggregates the largest attack still passing the per-axis tolerances.
//
//  Reports also include the strongest 4 raw peaks (radius, angle, raw row/col) so it's
//  immediately obvious whether the template peaks at radius=100 are actually being picked, or
//  whether image-content energy at other radii is winning the magnitude race.
//

import Foundation
import UIKit

enum SyncTemplateGeometricAttackTests {

    // ==========================================
    // MARK: - Tunables (pass thresholds)
    // ==========================================

    /// Angle error tolerance in degrees. With sub-pixel parabolic refinement of the FFT peak,
    /// a healthy detection should sit well below 0.5°. Larger errors mean either the wrong peak
    /// was picked (image content > template) or the FFT crop is too small to resolve the angle.
    static let angleToleranceDegrees: Double = 0.5

    /// Scale relative-error tolerance. `|detected/expected - 1| <= tol` ⇒ pass.
    static let scaleRelativeTolerance: Double = 0.02   // ±2 %

    // ==========================================
    // MARK: - Test Binding (mirrors WatermarkCompressionAttackTests pattern)
    // ==========================================

    /// Keeps `UserSettingsStore` alive while `WatermarkService.settingsStore` is `weak`.
    /// `textureVarianceThreshold = -1` forces every 8×8 tile to be embedded — irrelevant for the
    /// geometric module per se, but matches the historical compression/crop test posture so we
    /// don't accidentally introduce a confound when reusing this binding.
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

    /// Polar coords + raw FFT indices for one peak. Used purely for diagnostics — lets the user
    /// see whether the template peaks at radius=100 are even among the top candidates.
    struct PeakSnapshot: Sendable {
        var radius: Double
        var angleDegrees: Double
        var centeredX: Double
        var centeredY: Double
    }

    struct BasicReport: Sendable {
        var imageLoaded: Bool
        var embedSucceeded: Bool
        var detectionRan: Bool

        var detectedAngleDegrees: Double?
        var detectedScale: Double?

        /// True iff `|detectedAngle| ≤ angleToleranceDegrees` AND `|detectedScale - 1| ≤ scaleRelativeTolerance`.
        var detectedIdentity: Bool

        var topPeaks: [PeakSnapshot]   // up to 4, sorted by magnitude descending
        var watermarkedPx: (w: Int, h: Int)?
    }

    struct AttackCase: Sendable {
        enum Kind: String, Sendable { case rotation, scale }
        var kind: Kind

        /// Ground-truth attack parameter. Rotation: degrees. Scale: linear factor (1.0 = identity).
        var attackParam: Double

        /// Detector output for THIS attacked image.
        var detectedAngleDegrees: Double?
        var detectedScale: Double?

        /// |detected - expected|. For rotation kind: expectedAngle = attackParam, expectedScale = 1.
        /// For scale kind: expectedAngle = 0, expectedScale = attackParam.
        var angleErrorDegrees: Double?
        /// Relative scale error: `|detected/expected - 1|`. Bounded to [0, +∞).
        var scaleRelativeError: Double?

        var passed: Bool

        var attackedPx: (w: Int, h: Int)?
        var topPeaks: [PeakSnapshot]
    }

    struct SweepReport: Sendable {
        var imageLoaded: Bool
        var embedSucceeded: Bool

        var rotationCases: [AttackCase]
        var scaleCases: [AttackCase]

        /// Largest |rotation degrees| whose detection PASSED both axes.
        var maxPassingAbsRotationDegrees: Double?
        /// Closest-to-1 PASS bounds for the scale axis.
        var minPassingScaleFactor: Double?
        var maxPassingScaleFactor: Double?
    }

    // ==========================================
    // MARK: - Test 1: Identity Detection (No Attack)
    // ==========================================

    /// Embeds → runs `detectGeometricTransforms` on the watermarked image (no attack).
    /// Expectations:
    ///   - detected angle within ±`angleToleranceDegrees` of 0°
    ///   - detected scale within ±`scaleRelativeTolerance` of 1.0
    ///   - top peaks should be the 4 template peaks at radius ≈ 100, angles ≈ ±π/4
    ///
    /// IMPORTANT: this test does NOT call `extractWatermark`; bit recovery / sync header scan
    /// failures are out of scope here.
    static func runBasicSyncTemplateOnBundledTestImg(
        syncTemplateIntensity: Double = AppConstants.SettingsDefault.syncTemplateIntensity
    ) async -> BasicReport {
        guard let img = ImagePipelineTests.loadBundledTestUIImage() else {
            return BasicReport(
                imageLoaded: false, embedSucceeded: false, detectionRan: false,
                detectedAngleDegrees: nil, detectedScale: nil, detectedIdentity: false,
                topPeaks: [], watermarkedPx: nil
            )
        }

        let binding = await MainActor.run {
            WatermarkServiceTestBinding(textureVarianceThreshold: -1, syncTemplateIntensity: syncTemplateIntensity)
        }
        let service = binding.service

        let watermarked: UIImage
        do {
            // Payload text is irrelevant for the geometric module — the sync template is added on
            // top of the Y channel regardless of which bits are encoded.
            watermarked = try await service.embedWatermarkSilently(into: img, text: "Successful")
        } catch {
            return BasicReport(
                imageLoaded: true, embedSucceeded: false, detectionRan: false,
                detectedAngleDegrees: nil, detectedScale: nil, detectedIdentity: false,
                topPeaks: [], watermarkedPx: nil
            )
        }

        let pxW = Int(watermarked.size.width * watermarked.scale)
        let pxH = Int(watermarked.size.height * watermarked.scale)

        // Best-effort: save the un-attacked watermarked image for visual inspection of the
        // template wave at the user-selected intensity.
        try? await PhotoLibraryExporter.saveToPhotoLibrary(watermarked)

        let probe = detectorProbe(service: service, image: watermarked)

        let detectedIdentity: Bool
        if let a = probe.angleDeg, let s = probe.scale {
            detectedIdentity = abs(a) <= angleToleranceDegrees
                && abs(s - 1.0) <= scaleRelativeTolerance
        } else {
            detectedIdentity = false
        }

        return BasicReport(
            imageLoaded: true,
            embedSucceeded: true,
            detectionRan: probe.angleDeg != nil,
            detectedAngleDegrees: probe.angleDeg,
            detectedScale: probe.scale,
            detectedIdentity: detectedIdentity,
            topPeaks: probe.topPeaks,
            watermarkedPx: (pxW, pxH)
        )
    }

    // ==========================================
    // MARK: - Test 2: Smart Boundary Scan (Rotation + Scale)
    // ==========================================

    /// Executes a smart, directional boundary scan to find the exact failure limits.
    ///
    /// It sweeps outward from the identity (0° or 1.0x). To bypass the "Bilinear Death Valley"
    /// (where small deformations temporarily fail due to interpolation blur), it requires
    /// TWO consecutive failures before it aborts the coarse sweep.
    /// Once aborted, it performs a fine-grained sweep starting from the highest passed value
    /// to locate the exact breakdown boundary.
    static func runRotationAndScaleLimitSweepOnBundledTestImg(
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

        let binding = await MainActor.run {
            WatermarkServiceTestBinding(textureVarianceThreshold: -1, syncTemplateIntensity: syncTemplateIntensity)
        }
        let service = binding.service

        let watermarked: UIImage
        do {
            watermarked = try await service.embedWatermarkSilently(into: img, text: "Successful")
        } catch {
            return SweepReport(
                imageLoaded: true, embedSucceeded: false,
                rotationCases: [], scaleCases: [],
                maxPassingAbsRotationDegrees: nil,
                minPassingScaleFactor: nil, maxPassingScaleFactor: nil
            )
        }

        try? await PhotoLibraryExporter.saveToPhotoLibrary(watermarked)

        // --- Core Evaluation Helper ---
        func evaluate(kind: AttackCase.Kind, param: Double) -> AttackCase {
            let attacked: UIImage?

            switch kind {
            case .rotation:
                attacked = rotate(image: watermarked, degrees: param)
            case .scale:
                attacked = scale(image: watermarked, factor: param)
            }

            guard let attackedImg = attacked else {
                return emptyCase(kind: kind, attackParam: param)
            }

            let probe = detectorProbe(service: service, image: attackedImg)
            
            let angleErr: Double? = probe.angleDeg.map {
                kind == .rotation ? abs($0 - param) : abs($0)
            }
            let scaleErr: Double? = probe.scale.map {
                kind == .scale ? abs($0 - param) / max(param, 1e-9) : abs($0 - 1.0)
            }
            
            let pass = (angleErr ?? .infinity) <= angleToleranceDegrees
                && (scaleErr ?? .infinity) <= scaleRelativeTolerance

            return AttackCase(
                kind: kind,
                attackParam: param,
                detectedAngleDegrees: probe.angleDeg,
                detectedScale: probe.scale,
                angleErrorDegrees: angleErr,
                scaleRelativeError: scaleErr,
                passed: pass,
                attackedPx: pixelSize(of: attackedImg),
                topPeaks: probe.topPeaks
            )
        }

        // --- Smart Directional Sweep Engine ---
        func sweepDirection(kind: AttackCase.Kind, coarseSteps: [Double], fineStep: Double) -> [AttackCase] {
            var results: [AttackCase] = []
            var consecutiveFails = 0
            var highestPassIndex = -1

            // 1. Coarse Sweep (Fast tracking)
            for (i, param) in coarseSteps.enumerated() {
                let res = evaluate(kind: kind, param: param)
                results.append(res)

                if res.passed {
                    consecutiveFails = 0
                    highestPassIndex = i
                } else {
                    consecutiveFails += 1
                    // Tolerate 1 death valley failure, stop at 2 consecutive failures
                    if consecutiveFails >= 2 { break }
                }
            }

            // 2. Fine Sweep (Drill down into the limit)
            if highestPassIndex >= 0 {
                let lastPassVal = coarseSteps[highestPassIndex]
                let direction = (coarseSteps.last! > coarseSteps.first!) ? 1.0 : -1.0
                
                var currentFine = lastPassVal + (fineStep * direction)
                var fineFails = 0

                while fineFails < 2 {
                    // Safety break to prevent infinite loops
                    if results.count > 100 { break }

                    // Check if we already evaluated this exact step in the coarse run
                    if let existing = results.first(where: { abs($0.attackParam - currentFine) < 1e-4 }) {
                        if existing.passed { fineFails = 0 } else { fineFails += 1 }
                    } else {
                        // Evaluate new fine-grained step
                        let res = evaluate(kind: kind, param: currentFine)
                        results.append(res)
                        if res.passed { fineFails = 0 } else { fineFails += 1 }
                    }
                    currentFine += (fineStep * direction)
                }
            }
            return results
        }

        // -----------------------
        // Execute Directional Sweeps
        // -----------------------
        // We define sequences pointing OUTWARD from the identity (0° or 1.0x).
        
        let rotPosCoarse = [0.0, 1.0, 2.0, 5.0, 10.0, 15.0, 20.0, 30.0, 45.0, 60.0]
        let rotNegCoarse = [-1.0, -2.0, -5.0, -10.0, -15.0, -20.0, -30.0, -45.0, -60.0]
        let scaleUpCoarse = [1.0, 1.02, 1.05, 1.10, 1.15, 1.20, 1.30, 1.50, 1.80, 2.00, 2.50, 3.00, 3.50]
        let scaleDownCoarse = [0.98, 0.95, 0.90, 0.85, 0.80, 0.70, 0.60, 0.50]

        var allRotCases: [AttackCase] = []
        allRotCases.append(contentsOf: sweepDirection(kind: .rotation, coarseSteps: rotPosCoarse, fineStep: 1.0))
        allRotCases.append(contentsOf: sweepDirection(kind: .rotation, coarseSteps: rotNegCoarse, fineStep: 1.0))
        
        var allScaleCases: [AttackCase] = []
        allScaleCases.append(contentsOf: sweepDirection(kind: .scale, coarseSteps: scaleUpCoarse, fineStep: 0.01))
        allScaleCases.append(contentsOf: sweepDirection(kind: .scale, coarseSteps: scaleDownCoarse, fineStep: 0.01))

        // Sort results cleanly for the final printout
        allRotCases.sort { $0.attackParam < $1.attackParam }
        allScaleCases.sort { $0.attackParam < $1.attackParam }

        // -----------------------
        // Aggregate Limits
        // -----------------------
        let passingAbsRotations = allRotCases.filter { $0.passed }.map { abs($0.attackParam) }
        let maxRot = passingAbsRotations.max()

        let passingScales = allScaleCases.filter { $0.passed }.map { $0.attackParam }
        let minPassScale = passingScales.filter { $0 <= 1.0 }.min()
        let maxPassScale = passingScales.filter { $0 >= 1.0 }.max()

        return SweepReport(
            imageLoaded: true,
            embedSucceeded: true,
            rotationCases: allRotCases,
            scaleCases: allScaleCases,
            maxPassingAbsRotationDegrees: maxRot,
            minPassingScaleFactor: minPassScale,
            maxPassingScaleFactor: maxPassScale
        )
    }

    // ==========================================
    // MARK: - Attack Helpers
    // ==========================================

    /// Center-pivot rotation into a SAME-SIZE canvas. Corners that fall outside the canvas are
    /// clipped (transparent → black after rasterization in the YCbCr pipeline). Matches the
    /// typical "attacker rotates then re-saves" workflow where the file dimensions don't change.
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

    /// Isotropic resize to `floor(w·factor) × floor(h·factor)` pixels. Returned image has scale=1.
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
    // MARK: - Detector Probe (diagnostic snapshot)
    // ==========================================

    /// Runs the geometric detector once and also harvests the top-K peaks from `findSyncPeaks`
    /// for diagnostic output. Returns `nil` fields when the YCbCr conversion fails.
    private static func detectorProbe(
        service: WatermarkService,
        image: UIImage
    ) -> (angleDeg: Double?, scale: Double?, topPeaks: [PeakSnapshot]) {
        guard let ycbcr = service.algorithms.convertToYCbCr(image: image) else {
            return (nil, nil, [])
        }

        let yChannel = ycbcr.Y
        let t = service.algorithms.detectGeometricTransforms(in: yChannel)

        // Re-run only the early stages so we can read the top peaks for diagnostics. The
        // duplication is intentional — we want exactly the same FFT + peak set the detector saw.
        let N = WatermarkAlgorithmCore.syncTemplateAnalysisFFTSize
        var complexMatrix = service.algorithms.extractAndRemoveDC(from: yChannel, targetSize: N)
        service.algorithms.performForwardFFT(matrix: &complexMatrix)
        let peaks = service.algorithms.findSyncPeaks(in: complexMatrix)

        let topPeaks: [PeakSnapshot] = peaks.prefix(4).map { p in
            let r = sqrt(Double(p.x) * Double(p.x) + Double(p.y) * Double(p.y))
            let ang = atan2(Double(p.y), Double(p.x)) * 180.0 / .pi
            return PeakSnapshot(radius: r, angleDegrees: ang, centeredX: Double(p.x), centeredY: Double(p.y))
        }

        return (
            angleDeg: Double(t.angle) * 180.0 / .pi,
            scale: Double(t.scale),
            topPeaks: topPeaks
        )
    }

    private static func emptyCase(kind: AttackCase.Kind, attackParam: Double) -> AttackCase {
        AttackCase(
            kind: kind, attackParam: attackParam,
            detectedAngleDegrees: nil, detectedScale: nil,
            angleErrorDegrees: nil, scaleRelativeError: nil,
            passed: false, attackedPx: nil, topPeaks: []
        )
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

        let overallPass = r.imageLoaded && r.embedSucceeded && r.detectedIdentity
        let status = overallPass ? "PASS" : "FAIL"
        print("[SyncTemplateGeometricAttackTests] \(status) Basic — identity detection on un-attacked image")
        let px = r.watermarkedPx.map { "\($0.w)x\($0.h)px" } ?? "nil"
        let detAng = r.detectedAngleDegrees.map { String(format: "%.4f°", $0) } ?? "nil"
        let detSc = r.detectedScale.map { String(format: "%.6f", $0) } ?? "nil"
        print("  - imageLoaded:      \(r.imageLoaded ? "PASS" : "FAIL")")
        print("  - embed:            \(r.embedSucceeded ? "PASS" : "FAIL")  px=\(px)")
        print("  - detector ran:     \(r.detectionRan ? "PASS" : "FAIL")")
        print("  - identity detect:  \(r.detectedIdentity ? "PASS" : "FAIL")  angle=\(detAng) scale=\(detSc)")
        print("  - tolerances:       |angle|≤\(String(format: "%.2f°", angleToleranceDegrees))  |scale-1|≤\(String(format: "%.2f", scaleRelativeTolerance))")
        printTopPeaks(r.topPeaks, indent: "  ")
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
        print("[SyncTemplateGeometricAttackTests] \(status) LimitSweep — rotation & scale detector tolerance")
        let rotLimit = r.maxPassingAbsRotationDegrees.map { String(format: "±%.2f°", $0) } ?? "none"
        let minSc = r.minPassingScaleFactor.map { String(format: "%.3f", $0) } ?? "none"
        let maxSc = r.maxPassingScaleFactor.map { String(format: "%.3f", $0) } ?? "none"
        print("  - rotation limit:   \(rotLimit)")
        print("  - scale range:      [\(minSc), \(maxSc)]")
        print("  - tolerances:       |angle err|≤\(String(format: "%.2f°", angleToleranceDegrees))  |scale rel err|≤\(String(format: "%.2f", scaleRelativeTolerance))")

        print("  - rotation cases:")
        for c in r.rotationCases { printAttackCase(c, indent: "      ") }
        print("  - scale cases:")
        for c in r.scaleCases { printAttackCase(c, indent: "      ") }

        print("  - elapsed:          \(String(format: "%.2f", dtMs)) ms")
        #endif
    }

    #if DEBUG
    private static func printAttackCase(_ c: AttackCase, indent: String) {
        let detAng = c.detectedAngleDegrees.map { String(format: "%.3f°", $0) } ?? "nil"
        let detSc = c.detectedScale.map { String(format: "%.4f", $0) } ?? "nil"
        let angErr = c.angleErrorDegrees.map { String(format: "%.3f°", $0) } ?? "nil"
        let scErr = c.scaleRelativeError.map { String(format: "%.4f", $0) } ?? "nil"
        let pass = c.passed ? "PASS" : "FAIL"
        let paramStr: String
        switch c.kind {
        case .rotation: paramStr = String(format: "%+6.2f°", c.attackParam)
        case .scale:    paramStr = String(format: "%5.3fx", c.attackParam)
        }
        let pxStr = c.attackedPx.map { "\($0.w)x\($0.h)" } ?? "nil"
        print("\(indent)\(pass)  attack=\(paramStr)  px=\(pxStr)  detected(angle=\(detAng), scale=\(detSc))  err(angle=\(angErr), scaleRel=\(scErr))")
        printTopPeaks(c.topPeaks, indent: indent + "    ")
    }

    private static func printTopPeaks(_ peaks: [PeakSnapshot], indent: String) {
        guard !peaks.isEmpty else { return }
        print("\(indent)topPeaks (sorted by magnitude desc):")
        for (i, p) in peaks.enumerated() {
            print("\(indent)  [\(i)] r=\(String(format: "%6.2f", p.radius))  θ=\(String(format: "%+7.2f°", p.angleDegrees))  (x=\(String(format: "%+6.2f", p.centeredX)), y=\(String(format: "%+6.2f", p.centeredY)))")
        }
    }
    #endif
}
