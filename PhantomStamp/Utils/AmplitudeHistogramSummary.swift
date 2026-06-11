//
//  AmplitudeHistogramSummary.swift
//  PhantomStamp
//
//  Per-block embed-amplitude distribution for Advanced Mode intensity UI.
//

import Foundation

struct AmplitudeHistogramSummary: Sendable {
    static let binCount = 50

    let totalBlocks: Int
    let binCounts: [Int]
    let amplitudeMax: Double
    let binWidth: Double
    private let sortedAmplitudes: [Float]

    var maxBinCount: Int { binCounts.max() ?? 0 }

    static func build(
        baseQ: MacroblockBaseQuantizationCache,
        variance: MacroblockVarianceCache,
        varianceGainCurve: VarianceGainCurve,
        embeddingIntensity: Float
    ) -> AmplitudeHistogramSummary {
        var amplitudes = [Float]()
        amplitudes.reserveCapacity(baseQ.maxBlocksX * baseQ.maxBlocksY)

        for blockY in 0..<baseQ.maxBlocksY {
            for blockX in 0..<baseQ.maxBlocksX {
                let amp = BlockEmbedAmplitude.targetAmplitude(
                    baseAdaptiveQ: baseQ.baseQ(blockX: blockX, blockY: blockY),
                    variance: variance.variance(blockX: blockX, blockY: blockY),
                    embeddingIntensity: embeddingIntensity,
                    varianceGainCurve: varianceGainCurve
                )
                amplitudes.append(amp)
            }
        }

        let maxAmp = Double(amplitudes.max() ?? 1)
        let amplitudeMax = max(1.0, maxAmp)
        let binWidth = amplitudeMax / Double(binCount)
        var bins = [Int](repeating: 0, count: binCount)

        for amp in amplitudes {
            let bin = min(binCount - 1, max(0, Int(Double(amp) / binWidth)))
            bins[bin] += 1
        }

        amplitudes.sort()
        return AmplitudeHistogramSummary(
            totalBlocks: amplitudes.count,
            binCounts: bins,
            amplitudeMax: amplitudeMax,
            binWidth: binWidth,
            sortedAmplitudes: amplitudes
        )
    }

    func attenuatedBlockCount(variance: MacroblockVarianceCache, curve: VarianceGainCurve) -> Int {
        guard !sortedAmplitudes.isEmpty else { return 0 }
        var count = 0
        for blockY in 0..<variance.maxBlocksY {
            for blockX in 0..<variance.maxBlocksX {
                if curve.gain(atVariance: variance.variance(blockX: blockX, blockY: blockY)) < 0.999 {
                    count += 1
                }
            }
        }
        return count
    }

    func fullStrengthBlockCount(variance: MacroblockVarianceCache, curve: VarianceGainCurve) -> Int {
        max(0, totalBlocks - attenuatedBlockCount(variance: variance, curve: curve))
    }

    func medianAmplitude() -> Double {
        guard !sortedAmplitudes.isEmpty else { return 0 }
        let mid = sortedAmplitudes.count / 2
        if sortedAmplitudes.count.isMultiple(of: 2) {
            return Double((sortedAmplitudes[mid - 1] + sortedAmplitudes[mid]) * 0.5)
        }
        return Double(sortedAmplitudes[mid])
    }
}
