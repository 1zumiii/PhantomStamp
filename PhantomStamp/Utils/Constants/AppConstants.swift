//
//  AppConstants.swift
//  PhantomStamp
//
//  Centralize constants for numbers, text, UserDefaults keys, SF Symbol names, etc., for easy modification and retrieval.
//

import CoreGraphics
import Foundation

enum AppConstants {

    // MARK: - SwiftData

    enum Fetch {
        static let historyListLimit = 1_000
    }


    // MARK: - Info.plist

    enum InfoPlistKey {
        static let marketingVersion = "CFBundleShortVersionString"
    }

    enum VersionFallback {
        static let marketingUnknown = "0"
    }

    enum ErrorMessage {
        static let modelContainerPrefix = "Could not create ModelContainer: "
    }


    // MARK: - SF Symbols

    enum Symbol {
        static let tabEmbed = "wand.and.stars"
        static let tabExtract = "waveform.path.ecg"
        static let tabHistory = "clock.arrow.circlepath"
        static let tabSettings = "gearshape.fill"
    }

    // MARK: - Text (UI)

    enum Copy {

        enum Tab {
            static let watermark = "Embed"
            static let history   = "History"
            static let settings  = "Settings"
        }

        enum Watermark {
            static let navigationTitle    = "Test Page"
            static let alertTitle         = "Alert"
            static let embedButton        = "Embed Watermark"
            static let extractButton      = "Extract Watermark"
            static let okButton           = "OK"
            static let sectionPreview     = "Preview"
            static let sectionActions     = "Actions"
            static let sectionExtractResult  = "Extract Result"
            static let extractPlaceholder = "The result will be displayed here after extracting the watermark."
            static let processing         = "Processing…"
            static let embedChipFormat    = "Example Text · %@"
            static let tipArchitectureTitle = "DependencyInjection"
            static let tipHistoryTitle    = "History"
            static let captionDependencyInjection = "The view only depends on WatermarkServiceProtocol; at runtime, use WatermarkService; for SwiftUI Preview, use PreviewWatermarkService; for unit tests, use Mock in Tests."
            static let captionHistoryHintWhenLogging    = "Only when watermark embedding is successful will it be recorded in history (can be disabled in Settings)."
            static let captionHistoryHintWhenNotLogging = "Disabled: watermark embedding is not recorded when successful."
        }

        /// Copy for `UNUserNotificationCenter` alerts after watermark work completes.
        enum WatermarkPush {
            static let embedSingleSuccessTitle   = "Watermark embedded"
            static let embedSingleSuccessBody    = "Your image was watermarked successfully."
            static let embedSingleFailureTitle   = "Watermark embed failed"
            static let extractSingleSuccessTitle = "Watermark extracted"
            static let extractSingleSuccessBodyPrefix = "Payload: "
            static let extractSingleFailureTitle = "Watermark extract failed"
            static let batchEmbedDoneTitle       = "Batch embed finished"
            static let batchEmbedDoneBodyFormat  = "Succeeded: %d, failed: %d."
            static let batchExtractDoneTitle     = "Batch extract finished"
            static let batchExtractDoneBodyFormat = "Succeeded: %d, failed: %d."
            static let genericErrorBody          = "Something went wrong."
        }

        // AppConstants.Copy.History.navigationTitle
        enum History {
            static let navigationTitle           = "History"
            static let clearButton               = "Clear"
            static let printWatermarkRecordsButton = "Print saved watermark records"
            static let emptyTitle                = "No History"
            static let emptyDescription          = "When watermark embedding is successful on the watermark page, and \"Auto Log Watermark Embed\" is enabled in the settings, it will appear here."
            static let logWatermarkEmbeddedFormat = "Watermark Embedding Completed (Text: %@)"
        }

        enum Settings {
            // ── Existing constants (unchanged) ──
            static let navigationTitle      = "Settings"
            static let sectionHistory       = "History"
            static let sectionAppearance    = "Layout"
            static let sectionNotifications = "Notifications"
            static let toggleAutoLogWatermarkEmbed         = "Auto Log Watermark Embed"
            static let footnoteAutoLogWatermarkEmbed       = "When off, successful watermark embedding is not saved to SwiftData history. Stored in UserDefaults."
            static let toggleWatermarkOperationNotifications = "Watermark Finish Alerts"
            static let footnoteWatermarkOperationNotifications = "Local notifications when embedding or extraction completes (single image: per result; batch: one summary). Stored in UserDefaults."
            static let toggleCompactHistory   = "Compact History List"
            static let footnoteCompactHistory = "Persisted using UserDefaults, retained after app restart."

            // ── New constants added for SettingsView redesign ──

            // Page header
            static let pageSubtitle = "Manage your default watermark preferences and app settings."

            // Section headers
            static let sectionGeneral           = "General"
            static let sectionWatermarkDefaults = "Watermark Defaults"
            static let sectionAbout             = "About"
            static let sectionTesting           = "Testing"

            // General toggles (prototype labels)
            static let toggleSaveHistory  = "Save history"
            static let toggleShowAlerts   = "Show alerts"
            static let toggleSaveToPhotos = "Save to Photos"

            // Watermark Defaults rows
            static let labelDefaultWatermarkText = "Default Watermark text"
            static let placeholderWatermarkText  = "@YourName"
            static let labelEmbeddingStrength    = "Embedding strength"
            static let labelExportQuality        = "Export quality"
            static let exportQualityOptions      = ["Low", "Medium", "High"]
            static let footnoteWatermarkDefaults = "Default text is used as the watermark payload when embedding."

            // About rows
            static let rowAppVersion     = "App version"
            static let rowPrivacyStorage = "Privacy & Storage"
            static let rowLearnMore      = "Learn more"

            // Testing rows
            static let rowRobustnessTests = "Robustness Tests"
        }

        enum Footer {
            static let versionPrefix = "PhantomStamp v"
        }

        enum Preview {
            static let sectionCaption = "Example Description"
        }
    }
}
