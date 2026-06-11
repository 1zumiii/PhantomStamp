//
//  VarianceHistogramSummary.swift
//  PhantomStamp
//
//  Per-block σ distribution for Advanced Mode threshold UI (histogram + protected stats).
//

import Foundation

/// Pre-computed σ histogram over all macroblocks in a variance cache.
struct VarianceHistogramSummary: Sendable {
    static let sigmaMax: Double = 10
    static let binCount = 50

    let totalBlocks: Int
    /// Block counts per σ bin on `[0, sigmaMax)`.
    let binCounts: [Int]
    let binWidth: Double
    private let sortedSigmas: [Float]

    var maxBinCount: Int { binCounts.max() ?? 0 }

    static func build(from cache: MacroblockVarianceCache) -> VarianceHistogramSummary {
        let binWidth = sigmaMax / Double(binCount)
        var bins = [Int](repeating: 0, count: binCount)
        var sigmas = [Float]()
        sigmas.reserveCapacity(cache.maxBlocksX * cache.maxBlocksY)

        for row in cache.grid {
            for variance in row {
                let sigma = sqrt(variance)
                sigmas.append(sigma)
                let bin = min(binCount - 1, max(0, Int(Double(sigma) / binWidth)))
                bins[bin] += 1
            }
        }

        sigmas.sort()

        return VarianceHistogramSummary(
            totalBlocks: sigmas.count,
            binCounts: bins,
            binWidth: binWidth,
            sortedSigmas: sigmas
        )
    }

    /// Blocks whose population σ is strictly below the threshold σ (embed uses variance < σ²).
    func protectedBlockCount(atSigma sigma: Double) -> Int {
        guard !sortedSigmas.isEmpty else { return 0 }
        let threshold = Float(sigma)
        var low = 0
        var high = sortedSigmas.count
        while low < high {
            let mid = (low + high) / 2
            if sortedSigmas[mid] < threshold {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    func protectedFraction(atSigma sigma: Double) -> Double {
        guard totalBlocks > 0 else { return 0 }
        return Double(protectedBlockCount(atSigma: sigma)) / Double(totalBlocks)
    }

    func textureBlockCount(atSigma sigma: Double) -> Int {
        max(0, totalBlocks - protectedBlockCount(atSigma: sigma))
    }
}
