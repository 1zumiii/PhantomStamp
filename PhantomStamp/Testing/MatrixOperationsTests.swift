//
//  MatrixOperationsTests.swift
//  PhantomStamp
//
//  Lightweight validation helpers for 8×8 variance + DCT/IDCT.
//  (This is not XCTest; it is intended for manual/DEBUG smoke checks.)
//

import Foundation

/// Manual / DEBUG-entry validation for ``WatermarkService`` DSP primitives:
/// - ``WatermarkService/calculateVariance(_:)``
/// - ``WatermarkService/performDCT(_:)``
/// - ``WatermarkService/performIDCT(_:)``
enum MatrixOperationsTests {

    struct Report: Sendable {
        var varianceConstantPassed: Bool
        var varianceRampPassed: Bool
        var dctConstantDcOnlyPassed: Bool
        var dctIdctRoundTripPassed: Bool
        var sliceImagePassed: Bool

        var varianceConstant: Float
        var varianceRamp: Float
        var dctConstantMaxNonDCAbs: Float
        var roundTripMaxAbsError: Float
        var roundTripMAE: Float
        var sliceImageCheckCount: Int
    }

    /// Runs all validations and returns a metrics report.
    static func runAll() -> Report {
        let service = WatermarkService()

        // 1) Variance: constant block must be 0.
        let constantValue: Float = 42
        let constant = Matrix8x8(values: [Float](repeating: constantValue, count: Matrix8x8.elementCount))
        let vConst = service.calculateVariance(constant)
        let varianceConstantPassed = approxEqual(vConst, 0, eps: 1e-6)

        // 2) Variance: ramp 0..63 has a known population variance.
        // For 0..(n-1), population variance is (n^2 - 1) / 12.
        // Here n = 64 => (4096 - 1) / 12 = 341.25
        let ramp = Matrix8x8(values: (0..<Matrix8x8.elementCount).map { Float($0) })
        let vRamp = service.calculateVariance(ramp)
        let varianceRampPassed = approxEqual(vRamp, 341.25, eps: 1e-4)

        // 3) DCT: constant block should have energy only in the DC coefficient (0,0).
        let freqConst = service.performDCT(constant)
        var maxNonDCAbs: Float = 0
        for u in 0..<Matrix8x8.side {
            for v in 0..<Matrix8x8.side {
                if u == 0 && v == 0 { continue }
                maxNonDCAbs = max(maxNonDCAbs, abs(freqConst[u, v]))
            }
        }
        // vDSP should make non-DC terms extremely small for an exact constant input.
        let dctConstantDcOnlyPassed = maxNonDCAbs <= 1e-3

        // 4) Round-trip: IDCT(DCT(x)) ~= x (within floating-point error).
        let randomBlock = Matrix8x8(values: makeDeterministicBlock(seed: 0xC0FFEE))
        let roundTripped = service.performIDCT(service.performDCT(randomBlock))
        let (maxAbsError, mae) = errorMetrics(a: randomBlock.values, b: roundTripped.values)
        let dctIdctRoundTripPassed = maxAbsError <= 1e-2 && mae <= 5e-3

        // 5) Embed/extract should be self-consistent on frequency blocks.
        var freqForEmbed = service.performDCT(randomBlock)
        service.embedBitIntoFrequencies(&freqForEmbed, bit: 1)
        let extracted1 = service.extractBitFromFrequencies(freqForEmbed)
        service.embedBitIntoFrequencies(&freqForEmbed, bit: 0)
        let extracted0 = service.extractBitFromFrequencies(freqForEmbed)
        let embedExtractPassed = (extracted1 == 1) && (extracted0 == 0)

        // 6) Pipeline realism: embed in freq, go back to pixels, forward DCT again, then extract.
        // This simulates the embed path where IDCT quantization/rounding happens on write-back.
        var freqPipe = service.performDCT(randomBlock)
        service.embedBitIntoFrequencies(&freqPipe, bit: 1)
        let pixelsAfter = service.performIDCT(freqPipe)
        let freqAfter = service.performDCT(pixelsAfter)
        let extractedAfter = service.extractBitFromFrequencies(freqAfter)
        let embedPipelinePassed = (extractedAfter == 1)

        // 7) sliceImage: basic correctness (8-aligned crop + strip sizing + pixel mapping).
        let sliceResult = validateSliceImage(service: service)


        return Report(
            varianceConstantPassed: varianceConstantPassed,
            varianceRampPassed: varianceRampPassed,
            dctConstantDcOnlyPassed: dctConstantDcOnlyPassed,
            dctIdctRoundTripPassed: dctIdctRoundTripPassed && embedExtractPassed && embedPipelinePassed,
            sliceImagePassed: sliceResult.passed,
            varianceConstant: vConst,
            varianceRamp: vRamp,
            dctConstantMaxNonDCAbs: maxNonDCAbs,
            roundTripMaxAbsError: maxAbsError,
            roundTripMAE: mae,
            sliceImageCheckCount: sliceResult.checkCount
        )
    }

    /// Runs all validations and prints a single summary line (DEBUG only).
    static func runAllAndPrint() {
        #if DEBUG
        let r = runAll()
        let passed = r.varianceConstantPassed && r.varianceRampPassed && r.dctConstantDcOnlyPassed && r.dctIdctRoundTripPassed && r.sliceImagePassed
        let status = passed ? "PASS" : "FAIL"
        print("[MatrixOperationsTests] \(status) DSP / DCT / Slice")
        print("  - variance (constant→0):    \(r.varianceConstantPassed ? "PASS" : "FAIL")  value=\(String(format: "%.6f", r.varianceConstant))")
        print("  - variance (ramp→341.25):   \(r.varianceRampPassed ? "PASS" : "FAIL")  value=\(String(format: "%.6f", r.varianceRamp))")
        print("  - DCT constant (non-DC≈0):  \(r.dctConstantDcOnlyPassed ? "PASS" : "FAIL")  maxNonDC=\(String(format: "%.6f", r.dctConstantMaxNonDCAbs))")
        print("  - DCT↔IDCT round-trip:      \(r.dctIdctRoundTripPassed ? "PASS" : "FAIL")  max=\(String(format: "%.6f", r.roundTripMaxAbsError)) mae=\(String(format: "%.6f", r.roundTripMAE))")
        print("  - sliceImage:               \(r.sliceImagePassed ? "PASS" : "FAIL")  checks=\(r.sliceImageCheckCount)")
        #endif
    }

    // MARK: - Helpers

    private static func approxEqual(_ a: Float, _ b: Float, eps: Float) -> Bool {
        abs(a - b) <= eps
    }

    private static func errorMetrics(a: [Float], b: [Float]) -> (maxAbs: Float, mae: Float) {
        precondition(a.count == b.count)
        var maxAbs: Float = 0
        var sum: Float = 0
        for i in 0..<a.count {
            let d = abs(a[i] - b[i])
            maxAbs = max(maxAbs, d)
            sum += d
        }
        return (maxAbs, sum / Float(a.count))
    }

    /// Generates a deterministic 8×8 block in a roughly image-like range.
    private static func makeDeterministicBlock(seed: UInt64) -> [Float] {
        var rng = SplitMix64(state: seed)
        var out = [Float]()
        out.reserveCapacity(Matrix8x8.elementCount)
        for _ in 0..<Matrix8x8.elementCount {
            // 0...255-ish, with fractional parts to stress the transform.
            let u = rng.nextUnitFloat()
            out.append(u * 255.0)
        }
        return out
    }

    /// Small, fast, deterministic PRNG suitable for tests.
    private struct SplitMix64 {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }

        mutating func nextUnitFloat() -> Float {
            // Take the top 24 bits for a stable mantissa in Float.
            let x = next() >> 40
            return Float(x) / Float(1 << 24) // [0, 1)
        }
    }

    // MARK: - sliceImage validation

    /// Returns (passed, checkCount) so the report can surface how many invariants we checked.
    private static func validateSliceImage(service: WatermarkService) -> (passed: Bool, checkCount: Int) {
        // Make a small matrix with dimensions not divisible by 8 to ensure cropping is applied.
        // width=19 => validWidth=16, height=26 => validHeight=24
        var m = Matrix(width: 19, height: 26, data: [])
        m.data = [UInt8](repeating: 0, count: m.width * m.height)

        // Fill with a deterministic, row-major pattern so we can validate mapping precisely.
        // value = (y * width + x) % 251 (keep within UInt8 range and avoid simple 256 wrap symmetry)
        for y in 0..<m.height {
            for x in 0..<m.width {
                m.data[y * m.width + x] = UInt8((y * m.width + x) % 251)
            }
        }

        let strips = service.sliceImage(m, heightPerStrip: 10) // safeStripHeight should round down to 8

        var checks = 0
        func check(_ cond: Bool) -> Bool { checks += 1; return cond }

        // Expect validHeight=24 sliced by 8 => 3 strips
        guard check(strips.count == 3) else { return (false, checks) }

        // Each strip should be width=16, height=8, offsets 0/8/16 and pixel count = 128
        for (i, s) in strips.enumerated() {
            let expectedYOffset = i * 8
            guard check(s.width == 16) else { return (false, checks) }
            guard check(s.height == 8) else { return (false, checks) }
            guard check(s.globalXOffset == 0) else { return (false, checks) }
            guard check(s.globalYOffset == expectedYOffset) else { return (false, checks) }
            guard check(s.pixels.count == 16 * 8) else { return (false, checks) }
        }

        // Verify a few sample points per strip map back to original matrix exactly (within cropped area).
        // We only check inside validWidth (0..15) and validHeight (0..23).
        let sampleXs = [0, 7, 15]
        let sampleYsInStrip = [0, 3, 7]
        for s in strips {
            for sy in sampleYsInStrip {
                for sx in sampleXs {
                    let globalY = s.globalYOffset + sy
                    let expected = m.data[globalY * m.width + sx]
                    let actual = s.pixels[sy * s.width + sx]
                    guard check(actual == expected) else { return (false, checks) }
                }
            }
        }

        // Verify cropping: the original x=16..18 columns must NOT exist in strips.
        // So the last pixel in each strip row should correspond to original x=15.
        for s in strips {
            for sy in 0..<s.height {
                let globalY = s.globalYOffset + sy
                let expectedLast = m.data[globalY * m.width + 15]
                let actualLast = s.pixels[sy * s.width + 15]
                guard check(actualLast == expectedLast) else { return (false, checks) }
            }
        }

        return (true, checks)
    }
}

