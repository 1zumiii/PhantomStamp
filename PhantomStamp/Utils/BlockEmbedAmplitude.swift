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

    /// Heatmap color: light yellow/green (low) → deep orange/red (high).
    static func heatmapUIColor(normalized t: Float) -> UIColor {
        let t = min(max(t, 0), 1)
        if t < 0.5 {
            let u = CGFloat(t * 2)
            return UIColor(
                red: 0.45 + 0.35 * u,
                green: 0.82 - 0.22 * u,
                blue: 0.38 - 0.28 * u,
                alpha: 0.72
            )
        }
        let u = CGFloat((t - 0.5) * 2)
        return UIColor(
            red: 0.95 + 0.05 * u,
            green: 0.58 - 0.38 * u,
            blue: 0.12 - 0.08 * u,
            alpha: 0.78
        )
    }
}
