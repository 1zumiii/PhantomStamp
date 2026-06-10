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

        // Watermark Defaults — added for SettingsView
        static let defaultWatermarkText = "phantomstamp.settings.defaultWatermarkText"
        static let embeddingStrength    = "phantomstamp.settings.embeddingStrength"
        static let exportQualityIndex   = "phantomstamp.settings.exportQualityIndex"
        /// Save to Photos toggle (always-on until properly wired to export pipeline).
        static let saveToPhotos         = "phantomstamp.settings.saveToPhotos"

        /// Adaptive texture protection: skip modifying low-variance 8×8 blocks (zero-energy embed).
        static let textureVarianceThreshold = "phantomstamp.settings.textureVarianceThreshold"

        /// DFT sync template ripple intensity (peak ± LSB per pixel) used by `applySpatialTiling`.
        /// Higher values strengthen geometric attack resistance at the cost of more visible texture.
        static let syncTemplateIntensity = "phantomstamp.settings.syncTemplateIntensity"
    }

    enum SettingsDefault {
        static let autoLogWatermarkEmbed = true
        static let compactHistoryList    = false
        static let watermarkOperationNotifications = true

        // Watermark Defaults — added for SettingsView
        static let defaultWatermarkText: String = ""
        static let embeddingStrength: Double     = 50
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

    /// Converts the Settings “Embedding strength” slider (0–100%) into the global multiplier
    /// passed to `adaptiveQuantizationStep`. Default 50% → 1.0 (baseline adaptive Q unchanged).
    static func embeddingStrengthMultiplier(for strengthPercent: Double) -> Float {
        let baseline = SettingsDefault.embeddingStrength
        guard baseline > 0 else { return 1.0 }
        return Float(strengthPercent / baseline)
    }
}
