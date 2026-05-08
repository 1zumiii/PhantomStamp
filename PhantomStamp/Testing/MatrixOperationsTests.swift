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
        var stripUpdateAndReassemblePassed: Bool
        var gridOffsetAndSyncMarkerPassed: Bool

        var varianceConstant: Float
        var varianceRamp: Float
        var dctConstantMaxNonDCAbs: Float
        var roundTripMaxAbsError: Float
        var roundTripMAE: Float
        var sliceImageCheckCount: Int
        var stripUpdateAndReassembleCheckCount: Int
        var gridOffsetAndSyncMarkerCheckCount: Int
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

        // 8) updateStripInPlace + reassembleStrips: correct overwrite, preserve cropped margins.
        let stripWriteBackResult = validateStripUpdateAndReassemble(service: service)

        // 9) findGridOffsetAndSyncMarker: 64 offsets + sliding window + unknown W enum.
        let gridOffsetResult = validateFindGridOffsetAndSyncMarker(service: service)

        return Report(
            varianceConstantPassed: varianceConstantPassed,
            varianceRampPassed: varianceRampPassed,
            dctConstantDcOnlyPassed: dctConstantDcOnlyPassed,
            dctIdctRoundTripPassed: dctIdctRoundTripPassed && embedExtractPassed && embedPipelinePassed,
            sliceImagePassed: sliceResult.passed,
            stripUpdateAndReassemblePassed: stripWriteBackResult.passed,
            gridOffsetAndSyncMarkerPassed: gridOffsetResult.passed,
            varianceConstant: vConst,
            varianceRamp: vRamp,
            dctConstantMaxNonDCAbs: maxNonDCAbs,
            roundTripMaxAbsError: maxAbsError,
            roundTripMAE: mae,
            sliceImageCheckCount: sliceResult.checkCount,
            stripUpdateAndReassembleCheckCount: stripWriteBackResult.checkCount,
            gridOffsetAndSyncMarkerCheckCount: gridOffsetResult.checkCount
        )
    }

    /// Runs all validations and prints a single summary line (DEBUG only).
    static func runAllAndPrint() {
        #if DEBUG
        let r = runAll()
        let passed =
            r.varianceConstantPassed
            && r.varianceRampPassed
            && r.dctConstantDcOnlyPassed
            && r.dctIdctRoundTripPassed
            && r.sliceImagePassed
            && r.stripUpdateAndReassemblePassed
            && r.gridOffsetAndSyncMarkerPassed
        let status = passed ? "PASS" : "FAIL"
        print("[MatrixOperationsTests] \(status) DSP / DCT / Slice")
        print("  - variance (constant→0):    \(r.varianceConstantPassed ? "PASS" : "FAIL")  value=\(String(format: "%.6f", r.varianceConstant))")
        print("  - variance (ramp→341.25):   \(r.varianceRampPassed ? "PASS" : "FAIL")  value=\(String(format: "%.6f", r.varianceRamp))")
        print("  - DCT constant (non-DC≈0):  \(r.dctConstantDcOnlyPassed ? "PASS" : "FAIL")  maxNonDC=\(String(format: "%.6f", r.dctConstantMaxNonDCAbs))")
        print("  - DCT↔IDCT round-trip:      \(r.dctIdctRoundTripPassed ? "PASS" : "FAIL")  max=\(String(format: "%.6f", r.roundTripMaxAbsError)) mae=\(String(format: "%.6f", r.roundTripMAE))")
        print("  - sliceImage:               \(r.sliceImagePassed ? "PASS" : "FAIL")  checks=\(r.sliceImageCheckCount)")
        print("  - strip write-back:         \(r.stripUpdateAndReassemblePassed ? "PASS" : "FAIL")  checks=\(r.stripUpdateAndReassembleCheckCount)")
        print("  - grid offset + sync scan:  \(r.gridOffsetAndSyncMarkerPassed ? "PASS" : "FAIL")  checks=\(r.gridOffsetAndSyncMarkerCheckCount)")
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

    private static func validateStripUpdateAndReassemble(service: WatermarkService) -> (passed: Bool, checkCount: Int) {
        // Use non-8-aligned matrix to verify that right/bottom margins are preserved.
        // width=19 => validWidth=16, height=26 => validHeight=24
        var original = Matrix(width: 19, height: 26, data: [])
        original.data = [UInt8](repeating: 0, count: original.width * original.height)

        // Fill with a deterministic pattern, and make margins distinct so we can detect accidental overwrites.
        // - Core area (potentially overwritten by strips): (y*width+x)%251
        // - Right margin columns x=16..18: 240
        // - Bottom margin rows y=24..25: 241
        for y in 0..<original.height {
            for x in 0..<original.width {
                if y >= 24 {
                    original.data[y * original.width + x] = 241
                } else if x >= 16 {
                    original.data[y * original.width + x] = 240
                } else {
                    original.data[y * original.width + x] = UInt8((y * original.width + x) % 251)
                }
            }
        }

        let validWidth = (original.width / 8) * 8
        let validHeight = (original.height / 8) * 8

        // Slice and then "process" strips by setting their pixels to a known marker per strip.
        var strips = service.sliceImage(original, heightPerStrip: 10) // safeStripHeight=8 => 3 strips

        var checks = 0
        func check(_ cond: Bool) -> Bool { checks += 1; return cond }

        guard check(strips.count == validHeight / 8) else { return (false, checks) }

        // Simulate async processing order reversal and ensure updateStripInPlace still writes correct strip.
        let processed = strips.enumerated().map { (i, s) -> ImageStrip in
            var out = s
            let marker = UInt8(10 + i) // 10,11,12...
            out.pixels = [UInt8](repeating: marker, count: s.width * s.height)
            return out
        }.reversed()

        for p in processed {
            service.updateStripInPlace(&strips, with: p)
        }

        // Reassemble into a copy of the original.
        var reassembled = original
        service.reassembleStrips(strips, into: &reassembled)

        // 1) Core area [0..<validWidth, 0..<validHeight] must be overwritten by markers.
        // Verify a couple of points per strip.
        for (i, s) in strips.enumerated() {
            let expected = UInt8(10 + i)
            let samplePoints = [(x: 0, y: 0), (x: 7, y: 3), (x: validWidth - 1, y: 7)]
            for sp in samplePoints {
                let globalY = s.globalYOffset + sp.y
                let idx = globalY * reassembled.width + sp.x
                guard check(reassembled.data[idx] == expected) else { return (false, checks) }
            }
        }

        // 2) Right margin x in [validWidth..<width) for y < validHeight must stay at 240.
        if validWidth < original.width {
            for y in 0..<validHeight {
                for x in validWidth..<original.width {
                    let idx = y * original.width + x
                    guard check(reassembled.data[idx] == 240) else { return (false, checks) }
                }
            }
        }

        // 3) Bottom margin y in [validHeight..<height) must stay at 241 (all columns).
        if validHeight < original.height {
            for y in validHeight..<original.height {
                for x in 0..<original.width {
                    let idx = y * original.width + x
                    guard check(reassembled.data[idx] == 241) else { return (false, checks) }
                }
            }
        }

        return (true, checks)
    }

    private static func validateFindGridOffsetAndSyncMarker(service: WatermarkService) -> (passed: Bool, checkCount: Int) {
        let sync = getSyncMarkerBits()
        var checks = 0
        func check(_ cond: Bool) -> Bool { checks += 1; return cond }
        
        struct Case: Sendable {
            var name: String
            var expectedOffsetX: Int
            var expectedOffsetY: Int
            var bx: Int
            var by: Int
            var w: Int
            var blockCount: Int
            var seed: UInt64
            var mismatchedBits: Set<Int> // indices 0..<32 to flip (simulate extraction noise)
        }
        
        let cases: [Case] = [
            Case(name: "offset(3,5) w=13 bx/by=7/6", expectedOffsetX: 3, expectedOffsetY: 5, bx: 7, by: 6, w: 13, blockCount: 30, seed: 0xD00D_F00D, mismatchedBits: []),
            Case(name: "offset(0,0) w=8  bx/by=0/0", expectedOffsetX: 0, expectedOffsetY: 0, bx: 0, by: 0, w: 8, blockCount: 30, seed: 0xBADC0FFE, mismatchedBits: []),
            Case(name: "offset(7,7) w=18 bx/by=9/11", expectedOffsetX: 7, expectedOffsetY: 7, bx: 9, by: 11, w: 18, blockCount: 30, seed: 0xA11CE5E, mismatchedBits: []),
            // Tolerance=4: flip 3 bits and it should still pass.
            Case(name: "offset(2,6) w=11 bx/by=5/8 (3 bit flips)", expectedOffsetX: 2, expectedOffsetY: 6, bx: 5, by: 8, w: 11, blockCount: 30, seed: 0xC001D00D, mismatchedBits: [1, 9, 27]),
        ]
        
        for tc in cases {
            let width = tc.expectedOffsetX + tc.blockCount * Matrix8x8.side + 8
            let height = tc.expectedOffsetY + tc.blockCount * Matrix8x8.side + 8
            
            var m = Matrix(width: width, height: height, data: [])
            m.data = [UInt8](repeating: 0, count: width * height)
            var rng = SplitMix64(state: tc.seed)
            for i in 0..<m.data.count {
                let u = rng.nextUnitFloat()
                m.data[i] = UInt8(clamping: Int((u * 90.0 + 80.0).rounded())) // 80..170
            }
            
            for i in 0..<32 {
                let r = tc.by + (i / tc.w)
                let c = tc.bx + (i % tc.w)
                let px = tc.expectedOffsetX + c * Matrix8x8.side
                let py = tc.expectedOffsetY + r * Matrix8x8.side
                
                let stampedBit = tc.mismatchedBits.contains(i) ? (1 - sync[i]) : sync[i]
                let spatial = makeSpatialBlockForEmbeddedBit(service: service, bit: stampedBit, seed: UInt64(0xABC000 + i) ^ tc.seed)
                writeSpatialBlock(&m, spatial, x: px, y: py)
            }
            
            #if DEBUG
            print("[MatrixOperationsTests] DEBUG gridOffset case: \(tc.name)")
            debugPrintMatrixWindow(
                m,
                x: max(0, tc.expectedOffsetX + tc.bx * 8 - 4),
                y: max(0, tc.expectedOffsetY + tc.by * 8 - 4),
                w: 16,
                h: 16,
                label: "pixel window near sync start"
            )
            #endif
            
            let got = service.findGridOffsetAndSyncMarker(in: m)
            guard check(got != nil) else { return (false, checks) }
            guard let p = got else { return (false, checks) }
            if Int(p.x) != tc.expectedOffsetX || Int(p.y) != tc.expectedOffsetY {
                #if DEBUG
                print("[MatrixOperationsTests] DEBUG gridOffset case mismatch: got (\(Int(p.x)),\(Int(p.y))) expected (\(tc.expectedOffsetX),\(tc.expectedOffsetY))")
                #endif
                return (false, checks)
            }
            guard check(Int(p.x) == tc.expectedOffsetX) else { return (false, checks) }
            guard check(Int(p.y) == tc.expectedOffsetY) else { return (false, checks) }
        }
        
        return (true, checks)
    }

    private static func makeSpatialBlockForEmbeddedBit(service: WatermarkService, bit: Int, seed: UInt64) -> Matrix8x8 {
        // Generate a deterministic textured spatial block, then run the real embed path:
        // spatial -> DCT -> embedBitIntoFrequencies -> IDCT.
        // This prevents "ghost matches" where synthetic symmetric frequency blocks can decode under wrong offsets.
        var rng = SplitMix64(state: seed)
        var spatial = Matrix8x8(values: [Float](repeating: 0, count: Matrix8x8.elementCount))
        for i in 0..<spatial.values.count {
            // Roughly image-like luma range with texture.
            spatial.values[i] = rng.nextUnitFloat() * 160.0 + 40.0 // 40..200
        }

        var freq = service.performDCT(spatial)
        service.embedBitIntoFrequencies(&freq, bit: bit)
        spatial = service.performIDCT(freq)
        return spatial
    }

    private static func writeSpatialBlock(_ matrix: inout Matrix, _ block: Matrix8x8, x: Int, y: Int) {
        precondition(x >= 0 && y >= 0)
        precondition(x + Matrix8x8.side <= matrix.width && y + Matrix8x8.side <= matrix.height)
        for row in 0..<Matrix8x8.side {
            for col in 0..<Matrix8x8.side {
                let v = Int(block[row, col].rounded())
                matrix.data[(y + row) * matrix.width + (x + col)] = UInt8(clamping: v)
            }
        }
    }
    
    #if DEBUG
    private static func debugPrintMatrixWindow(_ matrix: Matrix, x: Int, y: Int, w: Int, h: Int, label: String) {
        let x0 = max(0, min(x, matrix.width))
        let y0 = max(0, min(y, matrix.height))
        let x1 = max(0, min(x0 + w, matrix.width))
        let y1 = max(0, min(y0 + h, matrix.height))
        print("[MatrixOperationsTests] DEBUG matrix \(label): x=\(x0)..<\(x1) y=\(y0)..<\(y1)")
        for yy in y0..<y1 {
            var row = ""
            row.reserveCapacity((x1 - x0) * 3)
            for xx in x0..<x1 {
                let v = matrix.data[yy * matrix.width + xx]
                row += String(format: "%03d ", v)
            }
            print("  \(row)")
        }
    }
    #endif
}

