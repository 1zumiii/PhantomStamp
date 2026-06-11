//
//  VarianceGainCurveSummary.swift
//  PhantomStamp
//
//  Block counts / histogram for the variance–gain curve editor.
//

import Foundation

struct VarianceGainCurveSummary: Sendable {
  static let gainBinCount = 50

  let totalBlocks: Int
  /// Block counts per gain bin on [0, 1).
  let gainBinCounts: [Int]
  let gainBinWidth: Double
  private let sortedGains: [Float]

  var maxGainBinCount: Int { gainBinCounts.max() ?? 0 }

  static func build(
    variance: MacroblockVarianceCache,
    curve: VarianceGainCurve
  ) -> VarianceGainCurveSummary {
    var gains = [Float]()
    gains.reserveCapacity(variance.maxBlocksX * variance.maxBlocksY)
    var bins = [Int](repeating: 0, count: gainBinCount)
    let binWidth = 1.0 / Double(gainBinCount)

    for row in variance.grid {
      for v in row {
        let g = curve.gain(atVariance: v)
        gains.append(g)
        let bin = min(gainBinCount - 1, max(0, Int(Double(g) / binWidth)))
        bins[bin] += 1
      }
    }
    gains.sort()

    return VarianceGainCurveSummary(
      totalBlocks: gains.count,
      gainBinCounts: bins,
      gainBinWidth: binWidth,
      sortedGains: gains
    )
  }

  func attenuatedBlockCount(gainThreshold: Float = 0.999) -> Int {
    guard !sortedGains.isEmpty else { return 0 }
    var low = 0
    var high = sortedGains.count
    while low < high {
      let mid = (low + high) / 2
      if sortedGains[mid] < gainThreshold {
        low = mid + 1
      } else {
        high = mid
      }
    }
    return low
  }

  func fullStrengthBlockCount(gainThreshold: Float = 0.999) -> Int {
    max(0, totalBlocks - attenuatedBlockCount(gainThreshold: gainThreshold))
  }

  func attenuatedFraction(gainThreshold: Float = 0.999) -> Double {
    guard totalBlocks > 0 else { return 0 }
    return Double(attenuatedBlockCount(gainThreshold: gainThreshold)) / Double(totalBlocks)
  }
}
