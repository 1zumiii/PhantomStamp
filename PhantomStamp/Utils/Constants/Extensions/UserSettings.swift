//
//  UserSettings.swift
//  PhantomStamp
//
//  Created by Orion on 10/5/2026.
//

import Foundation

extension AppConstants{
    // MARK: - UserDefaults

    enum UserDefaultsKey {
        /// Only control whether watermark embedding is recorded in SwiftData (`WatermarkHistoryRecord` embed rows).
        static let autoLogWatermarkEmbed = "phantomstamp.settings.autoLogWatermarkEmbed"
        /// Previous key; `AppUserDefault` migrates into `autoLogWatermarkEmbed` once then removes this entry.
        static let legacyAutoLogWatermarkEmbed = "phantomstamp.settings.autoLogWatermark"
        static let compactHistoryList = "phantomstamp.settings.compactHistoryList"
        /// User toggle for local notifications after embed/extract complete (`WatermarkOperationNotificationService`).
        static let watermarkOperationNotifications = "phantomstamp.settings.watermarkOperationNotifications"
    }

    enum SettingsDefault {
        static let autoLogWatermarkEmbed = true
        static let compactHistoryList = false
        static let watermarkOperationNotifications = true
    }
}
