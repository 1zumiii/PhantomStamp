//
//  BlockEmbedAmplitude.swift
//  PhantomStamp
//
//  Per-8×8 target embed amplitude preview (matches FrequencyEmbedding pipeline).
//

import UIKit

enum BlockEmbedAmplitude {
    /// Payload macroblock strength in `embedBitIntoFrequencies` (non-sync/header cells).
    static let payloadStrength: Float = 2.0

    static let intensityMax: Double = 10
    static let intensityStep: Double = 0.5

    /// Target DCT separation (`targetQa`) for one block — the absolute coefficient delta scale.
    static func targetAmplitude(
        baseAdaptiveQ: Float,
        variance: Float,
        embeddingIntensity: Float,
        varianceThreshold: Float? = nil,
        varianceGainCurve: VarianceGainCurve? = nil,
        smoothReductionFactor: Float = AppConstants.SmoothProtection.reductionFactor
    ) -> Float {
        let gain = embedGain(
            variance: variance,
            varianceThreshold: varianceThreshold,
            varianceGainCurve: varianceGainCurve,
            smoothReductionFactor: smoothReductionFactor
        )
        return baseAdaptiveQ * embeddingIntensity * gain * payloadStrength
    }

    /// Per-block strength multiplier (0…1) from curve or legacy binary threshold.
    static func embedGain(
        variance: Float,
        varianceThreshold: Float?,
        varianceGainCurve: VarianceGainCurve?,
        smoothReductionFactor: Float = AppConstants.SmoothProtection.reductionFactor
    ) -> Float {
        if let curve = varianceGainCurve {
            return curve.gain(atVariance: variance)
        }
        if let threshold = varianceThreshold {
            return variance < threshold ? smoothReductionFactor : 1.0
        }
        return 1.0
    }

    /// Maps absolute amplitude to pseudo-color (6-stop thermal ramp).
    /// Ceiling is peak block at `intensityMax` — slider at 5.5× lands near mid-range, not saturated.
    static func heatmapUIColor(amplitude: Float, normalizationCeiling: Float) -> UIColor {
        let raw = Double(amplitude / max(normalizationCeiling, 0.001))
        // Gentle compression above 1.0 so rare overshoots don't flatten to one color.
        let t = CGFloat(raw / (1.0 + 0.45 * max(0, raw - 1.0)))
        let u = min(max(t, 0), 1)
        let (red, green, blue) = rgbAt(stops: Self.amplitudeColorStops, u: u)
        let alpha = 0.28 + 0.58 * u
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Maps variance-gain 0…1 to a multi-hue purple ramp (Loupe gain-curve overlay).
    static func gainHeatmapUIColor(gain: Float) -> UIColor {
        let u = CGFloat(min(max(gain, 0), 1))
        let (red, green, blue) = rgbAt(stops: Self.gainColorStops, u: u)
        let alpha = 0.30 + 0.58 * u
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    // MARK: - Multi-stop palettes

    private typealias RGBStop = (position: CGFloat, rgb: (CGFloat, CGFloat, CGFloat))

    /// Deep blue → cyan → green → yellow → orange → red.
    private static let amplitudeColorStops: [RGBStop] = [
        (0.00, (0.10, 0.16, 0.58)),
        (0.18, (0.08, 0.48, 0.78)),
        (0.36, (0.18, 0.70, 0.52)),
        (0.54, (0.62, 0.78, 0.20)),
        (0.72, (0.94, 0.62, 0.12)),
        (0.88, (0.96, 0.38, 0.10)),
        (1.00, (0.90, 0.14, 0.16)),
    ]

    /// Indigo → violet → brand purple → magenta → coral (gain curve tab).
    private static let gainColorStops: [RGBStop] = [
        (0.00, (0.20, 0.10, 0.46)),
        (0.20, (0.34, 0.16, 0.68)),
        (0.40, (0.48, 0.24, 0.86)),
        (0.60, (0.62, 0.28, 0.94)),
        (0.78, (0.84, 0.26, 0.82)),
        (0.92, (0.96, 0.38, 0.62)),
        (1.00, (0.98, 0.52, 0.44)),
    ]

    private static func rgbAt(stops: [RGBStop], u: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        guard let first = stops.first else { return (0.5, 0.5, 0.5) }
        if u <= first.position { return first.rgb }
        if let last = stops.last, u >= last.position { return last.rgb }

        for index in 0..<(stops.count - 1) {
            let left = stops[index]
            let right = stops[index + 1]
            guard u >= left.position, u <= right.position else { continue }
            let span = right.position - left.position
            guard span > 1e-6 else { return right.rgb }
            let s = (u - left.position) / span
            return (
                left.rgb.0 + (right.rgb.0 - left.rgb.0) * s,
                left.rgb.1 + (right.rgb.1 - left.rgb.1) * s,
                left.rgb.2 + (right.rgb.2 - left.rgb.2) * s
            )
        }
        return stops.last?.rgb ?? (0.5, 0.5, 0.5)
    }
}
