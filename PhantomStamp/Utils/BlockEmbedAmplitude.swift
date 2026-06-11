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

    /// Maps absolute amplitude to pseudo-color.
    /// Ceiling is peak block at `intensityMax` — slider at 5.5× lands near mid-range, not saturated.
    static func heatmapUIColor(amplitude: Float, normalizationCeiling: Float) -> UIColor {
        let raw = Double(amplitude / max(normalizationCeiling, 0.001))
        // Gentle compression above 1.0 so rare overshoots don't flatten to one color.
        let t = CGFloat(raw / (1.0 + 0.45 * max(0, raw - 1.0)))
        let u = min(max(t, 0), 1)

        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        if u < 0.33 {
            let s = u / 0.33
            red = 0.28 + 0.22 * s
            green = 0.72 + 0.08 * s
            blue = 0.46 - 0.16 * s
        } else if u < 0.66 {
            let s = (u - 0.33) / 0.33
            red = 0.50 + 0.38 * s
            green = 0.80 - 0.28 * s
            blue = 0.30 - 0.22 * s
        } else {
            let s = (u - 0.66) / 0.34
            red = 0.88 + 0.10 * s
            green = 0.52 - 0.38 * s
            blue = 0.08 - 0.04 * s
        }

        let alpha = 0.26 + 0.58 * u
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
