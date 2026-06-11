//
//  VarianceGainCurve.swift
//  PhantomStamp
//
//  Continuous variance → embed-strength mapping for Advanced Mode (replaces binary σ cut).
//

import Foundation

/// One anchor on the variance–gain plane. `normalizedX` is fixed per preset layout; user drags `gain`.
struct VarianceGainControlPoint: Equatable, Codable, Sendable {
  /// Position along [0, maxVariance], normalized 0…1.
  var normalizedX: Double
  /// Intensity multiplier 0…1 (0%…100%).
  var gain: Double
}

/// Piecewise monotonic cubic spline mapping physical variance to per-block embed gain.
struct VarianceGainCurve: Equatable, Codable, Sendable {
  /// X-axis ceiling: physical variance (σ=10 → 100).
  var maxVariance: Double
  /// Sorted by `normalizedX`; must include endpoints at 0 and 1.
  var points: [VarianceGainControlPoint]

  static let defaultMaxVariance: Double = 100.0

  // MARK: Presets

  /// Low-variance blocks stay near full strength (protection off).
  static var presetLinear: VarianceGainCurve {
    VarianceGainCurve(
      maxVariance: defaultMaxVariance,
      points: [
        VarianceGainControlPoint(normalizedX: 0.0, gain: 1.0),
        VarianceGainControlPoint(normalizedX: 0.5, gain: 1.0),
        VarianceGainControlPoint(normalizedX: 1.0, gain: 1.0),
      ]
    )
  }

  /// Strong separation: smooth regions weak, textured regions full.
  static var presetS: VarianceGainCurve {
    VarianceGainCurve(
      maxVariance: defaultMaxVariance,
      points: [
        VarianceGainControlPoint(normalizedX: 0.0, gain: 0.15),
        VarianceGainControlPoint(normalizedX: 0.5, gain: 0.55),
        VarianceGainControlPoint(normalizedX: 1.0, gain: 1.0),
      ]
    )
  }

  /// Fast rise in low-variance band, then plateaus toward texture.
  static var presetLog: VarianceGainCurve {
    VarianceGainCurve(
      maxVariance: defaultMaxVariance,
      points: [
        VarianceGainControlPoint(normalizedX: 0.0, gain: 0.35),
        VarianceGainControlPoint(normalizedX: 0.32, gain: 0.78),
        VarianceGainControlPoint(normalizedX: 1.0, gain: 1.0),
      ]
    )
  }

  static var `default`: VarianceGainCurve { presetS }

  // MARK: Evaluation

  /// Gain multiplier in 0…1 for a block's physical variance.
  func gain(atVariance variance: Float) -> Float {
    let clamped = min(max(Double(variance), 0), maxVariance)
    let t = clamped / max(maxVariance, 1e-6)
    return Float(interpolateGain(normalizedX: t))
  }

  func gainPercent(atVariance variance: Float) -> Double {
    Double(gain(atVariance: variance)) * 100.0
  }

  /// Lossless encoding for loupe / overlay cache keys.
  struct PackedKey: Hashable, Sendable {
    let maxVarianceBits: UInt64
    /// Interleaved normalizedX, gain bit patterns for each control point.
    let pointBits: [UInt64]
  }

  var packedKey: PackedKey {
    let bits = sortedPoints.flatMap { pt -> [UInt64] in
      [pt.normalizedX.bitPattern, pt.gain.bitPattern]
    }
    return PackedKey(maxVarianceBits: maxVariance.bitPattern, pointBits: bits)
  }

  static func decoded(from packedKey: PackedKey) -> VarianceGainCurve {
    var pts: [VarianceGainControlPoint] = []
    let pairs = packedKey.pointBits.count / 2
    for i in 0..<pairs {
      let x = Double(bitPattern: packedKey.pointBits[i * 2])
      let g = Double(bitPattern: packedKey.pointBits[i * 2 + 1])
      pts.append(VarianceGainControlPoint(normalizedX: x, gain: g))
    }
    return VarianceGainCurve(
      maxVariance: Double(bitPattern: packedKey.maxVarianceBits),
      points: pts.isEmpty ? VarianceGainCurve.presetS.points : pts
    )
  }

  var sortedPoints: [VarianceGainControlPoint] {
    points.sorted { $0.normalizedX < $1.normalizedX }
  }

  /// Draggable interior indices (endpoints at x=0 and x=1 keep gain clamped but mid anchors move freely).
  static let draggableAnchorIndices = [0, 1]

  /// Updates gain for the anchor at `sortedIndex` (0 = lowest variance knot).
  mutating func setGain(atSortedIndex sortedIndex: Int, gain newGain: Double) {
    let sorted = sortedPoints
    guard sorted.indices.contains(sortedIndex) else { return }
    let targetX = sorted[sortedIndex].normalizedX
    guard let i = points.firstIndex(where: { abs($0.normalizedX - targetX) < 1e-9 }) else { return }
    let clamped = min(max(newGain, 0), 1)
    if sortedIndex == sorted.count - 1 {
      points[i].gain = 1.0
    } else {
      points[i].gain = clamped
    }
  }

  // MARK: Interpolation

  private func interpolateGain(normalizedX t: Double) -> Double {
    let pts = sortedPoints
    guard let first = pts.first, let last = pts.last else { return 1.0 }
    if t <= first.normalizedX { return first.gain }
    if t >= last.normalizedX { return last.gain }

    for i in 0..<(pts.count - 1) {
      let p0 = pts[i]
      let p1 = pts[i + 1]
      guard t >= p0.normalizedX, t <= p1.normalizedX else { continue }
      let span = p1.normalizedX - p0.normalizedX
      guard span > 1e-9 else { return p1.gain }
      let u = (t - p0.normalizedX) / span
      return cubicHermite(y0: p0.gain, y1: p1.gain, t: u)
    }
    return last.gain
  }

  /// Smooth ease between knots without overshoot (Hermite with zero end tangents per segment).
  private func cubicHermite(y0: Double, y1: Double, t: Double) -> Double {
    let u = min(max(t, 0), 1)
    let u2 = u * u
    let u3 = u2 * u
    return (2 * u3 - 3 * u2 + 1) * y0 + (-2 * u3 + 3 * u2) * y1
  }
}
