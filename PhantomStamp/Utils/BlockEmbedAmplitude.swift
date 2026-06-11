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
        varianceThreshold: Float,
        embeddingIntensity: Float,
        smoothReductionFactor: Float = AppConstants.SmoothProtection.reductionFactor
    ) -> Float {
        let isSmooth = variance < varianceThreshold
        let globalMultiplier = embeddingIntensity * (isSmooth ? smoothReductionFactor : 1.0)
        return baseAdaptiveQ * globalMultiplier * payloadStrength
    }

    /// Maps absolute amplitude to a pseudo-color using a fixed per-image baseline (intensity 1.0×).
    /// `rawRatio` may exceed 1.0 before clamping — higher slider values deepen saturation globally.
    static func heatmapUIColor(amplitude: Float, baselineMaxAmplitude: Float) -> UIColor {
        let rawRatio = amplitude / max(baselineMaxAmplitude, 0.001)
        let t = min(max(rawRatio, 0), 1)
        let u = CGFloat(t)

        // Light green → yellow → orange-red with opacity tied to energy level.
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        if u < 0.5 {
            let s = u * 2
            red = 0.32 + 0.58 * s
            green = 0.78 - 0.18 * s
            blue = 0.42 - 0.30 * s
        } else {
            let s = (u - 0.5) * 2
            red = 0.90 + 0.10 * s
            green = 0.68 - 0.48 * s
            blue = 0.12 - 0.08 * s
        }

        let alpha = 0.28 + 0.62 * u
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
