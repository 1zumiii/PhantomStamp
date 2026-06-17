//
//  UserSettings.swift
//  PhantomStamp
//
//  Created by Orion on 10/5/2026.
//

import Foundation

extension AppConstants {
    // MARK: - UserDefaults

    enum UserDefaultsKey {
        /// Only control whether watermark embedding is recorded in SwiftData (`WatermarkHistoryRecord` embed rows).
        static let autoLogWatermarkEmbed = "phantomstamp.settings.autoLogWatermarkEmbed"
        /// Previous key; `AppUserDefault` migrates into `autoLogWatermarkEmbed` once then removes this entry.
        static let legacyAutoLogWatermarkEmbed = "phantomstamp.settings.autoLogWatermark"
        static let compactHistoryList = "phantomstamp.settings.compactHistoryList"
        /// User toggle for local notifications after embed/extract complete (`WatermarkOperationNotificationService`).
        static let watermarkOperationNotifications = "phantomstamp.settings.watermarkOperationNotifications"
        static let darkThemeEnabled = "phantomstamp.settings.darkThemeEnabled"

        // Watermark Defaults — added for SettingsView
        static let defaultWatermarkText = "phantomstamp.settings.defaultWatermarkText"
        static let exportQualityIndex   = "phantomstamp.settings.exportQualityIndex"
        /// Save to Photos toggle (always-on until properly wired to export pipeline).
        static let saveToPhotos         = "phantomstamp.settings.saveToPhotos"

        /// Adaptive texture protection: low-variance 8×8 blocks are embedded at reduced strength
        /// (weak-energy embed, see `SmoothProtection.reductionFactor`).
        static let textureVarianceThreshold = "phantomstamp.settings.textureVarianceThreshold"

        /// DFT sync template ripple intensity (peak ± LSB per pixel) used by `applySpatialTiling`.
        /// Higher values strengthen geometric attack resistance at the cost of more visible texture.
        static let syncTemplateIntensity = "phantomstamp.settings.syncTemplateIntensity"
    }

    nonisolated enum SettingsDefault {
        static let autoLogWatermarkEmbed = true
        static let compactHistoryList    = false
        static let watermarkOperationNotifications = true
        static let darkThemeEnabled = false

        // Watermark Defaults — added for SettingsView
        static let defaultWatermarkText: String = ""
        /// Fixed Adaptive-mode multiplier for mid-frequency embed Q (`adaptiveQuantizationStep`).
        /// Advanced mode and internal tests may override this locally for one embed run.
        static let embeddingStrength: Double     = EmbeddingStrength.default
        static let exportQualityIndex: Int       = 1   // 0 = Low, 1 = Medium, 2 = High
        static let saveToPhotos: Bool            = true

        /// Recommended default: subtle protection without killing redundancy.
        static let textureVarianceThreshold: Double = 0.0

        /// `5.0` is the empirically-determined value at which the DFT geometric detector recovers
        /// rotation up to ±15° and scale across [0.85×, 1.15×] on natural photos with strong
        /// frequency content (e.g. `TestImg`). Lower values (e.g. 2.5) keep the template wave
        /// barely visible but the geometric detection becomes flaky on textured images. Tunable
        /// per-image via the slider on `RobustnessTestingView`.
        static let syncTemplateIntensity: Double = 5.0
    }

    /// Smooth-block protection (weak-energy embed).
    ///
    /// Blocks whose variance falls below `textureVarianceThreshold` are NO LONGER zero-energy
    /// skipped: they are embedded with the adaptive-Q global multiplier scaled by this factor.
    /// The bit stays physically present (sync correlation and majority voting never lose whole
    /// repetitions in flat regions) while the ripple amplitude stays visually negligible.
    nonisolated enum SmoothProtection {
        static let reductionFactor: Float = 0.3
    }

    /// Adaptive-mode embed intensity bounds. Kept as algorithm constants, not user settings.
    nonisolated enum EmbeddingStrength {
        static let min: Double = 0
        static let max: Double = 10
        static let step: Double = 0.5
        /// Adaptive mode uses the strongest tested global Q multiplier by default.
        static let `default`: Double = 10.0
    }

    /// Normalizes an embed intensity value for history display and one-shot test/Advanced overrides.
    static func normalizedEmbeddingStrength(_ storedValue: Double) -> Double {
        let migrated: Double
        if storedValue > EmbeddingStrength.max {
            // Legacy percent slider: 50% → 1.0×.
            migrated = storedValue / 10.0
        } else {
            migrated = storedValue
        }
        return min(max(migrated, EmbeddingStrength.min), EmbeddingStrength.max)
    }

    /// Global multiplier passed to `adaptiveQuantizationStep` during embed.
    static func embeddingStrengthMultiplier(for storedValue: Double) -> Float {
        Float(normalizedEmbeddingStrength(storedValue))
    }
}
