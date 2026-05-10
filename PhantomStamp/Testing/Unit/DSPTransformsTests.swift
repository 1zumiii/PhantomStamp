//
//  DSPTransformsTests.swift
//  PhantomStamp
//
//  Manual / DEBUG validations for:
//  - variance
//  - DCT/IDCT round-trip
//  - embed/extract consistency on frequency blocks
//

import Foundation

enum DSPTransformsTests {
    struct Report: Sendable {
        var varianceConstantPassed: Bool
        var varianceRampPassed: Bool
        var dctConstantDcOnlyPassed: Bool
        var dctIdctRoundTripPassed: Bool

        var varianceConstant: Float
        var varianceRamp: Float
        var dctConstantMaxNonDCAbs: Float
        var roundTripMaxAbsError: Float
        var roundTripMAE: Float
    }

    static func runAll() -> Report {
        let service = WatermarkService()

        let constantValue: Float = 42
        let constant = Matrix8x8(values: [Float](repeating: constantValue, count: Matrix8x8.elementCount))
        let vConst = service.calculateVariance(constant)
        let varianceConstantPassed = WatermarkTestUtils.approxEqual(vConst, 0, eps: 1e-6)

        let ramp = Matrix8x8(values: (0..<Matrix8x8.elementCount).map { Float($0) })
        let vRamp = service.calculateVariance(ramp)
        let varianceRampPassed = WatermarkTestUtils.approxEqual(vRamp, 341.25, eps: 1e-4)

        let freqConst = service.performDCT(constant)
        var maxNonDCAbs: Float = 0
        for u in 0..<Matrix8x8.side {
            for v in 0..<Matrix8x8.side {
                if u == 0 && v == 0 { continue }
                maxNonDCAbs = max(maxNonDCAbs, abs(freqConst[u, v]))
            }
        }
        let dctConstantDcOnlyPassed = maxNonDCAbs <= 1e-3

        let randomBlock = Matrix8x8(values: WatermarkTestUtils.makeDeterministicBlock(seed: 0xC0FFEE))
        let roundTripped = service.performIDCT(service.performDCT(randomBlock))
        let (maxAbsError, mae) = WatermarkTestUtils.errorMetrics(a: randomBlock.values, b: roundTripped.values)
        let dctIdctRoundTripPassed = maxAbsError <= 1e-2 && mae <= 5e-3

        // Embed/extract sanity (frequency-domain + pipeline)
        var freqForEmbed = service.performDCT(randomBlock)
        service.embedBitIntoFrequencies(&freqForEmbed, bit: 1)
        let extracted1 = service.extractBitFromFrequencies(freqForEmbed)
        service.embedBitIntoFrequencies(&freqForEmbed, bit: 0)
        let extracted0 = service.extractBitFromFrequencies(freqForEmbed)
        let embedExtractPassed = (extracted1 == 1) && (extracted0 == 0)

        var freqPipe = service.performDCT(randomBlock)
        service.embedBitIntoFrequencies(&freqPipe, bit: 1)
        let pixelsAfter = service.performIDCT(freqPipe)
        let freqAfter = service.performDCT(pixelsAfter)
        let extractedAfter = service.extractBitFromFrequencies(freqAfter)
        let embedPipelinePassed = (extractedAfter == 1)

        return Report(
            varianceConstantPassed: varianceConstantPassed,
            varianceRampPassed: varianceRampPassed,
            dctConstantDcOnlyPassed: dctConstantDcOnlyPassed,
            dctIdctRoundTripPassed: dctIdctRoundTripPassed && embedExtractPassed && embedPipelinePassed,
            varianceConstant: vConst,
            varianceRamp: vRamp,
            dctConstantMaxNonDCAbs: maxNonDCAbs,
            roundTripMaxAbsError: maxAbsError,
            roundTripMAE: mae
        )
    }

    static func runAllAndPrint() {
        #if DEBUG
        let r = runAll()
        let passed = r.varianceConstantPassed && r.varianceRampPassed && r.dctConstantDcOnlyPassed && r.dctIdctRoundTripPassed
        let status = passed ? "PASS" : "FAIL"
        print("[DSPTransformsTests] \(status) Variance / DCT")
        print("  - variance (constant→0):    \(r.varianceConstantPassed ? "PASS" : "FAIL")  value=\(String(format: "%.6f", r.varianceConstant))")
        print("  - variance (ramp→341.25):   \(r.varianceRampPassed ? "PASS" : "FAIL")  value=\(String(format: "%.6f", r.varianceRamp))")
        print("  - DCT constant (non-DC≈0):  \(r.dctConstantDcOnlyPassed ? "PASS" : "FAIL")  maxNonDC=\(String(format: "%.6f", r.dctConstantMaxNonDCAbs))")
        print("  - DCT↔IDCT round-trip:      \(r.dctIdctRoundTripPassed ? "PASS" : "FAIL")  max=\(String(format: "%.6f", r.roundTripMaxAbsError)) mae=\(String(format: "%.6f", r.roundTripMAE))")
        #endif
    }
}

