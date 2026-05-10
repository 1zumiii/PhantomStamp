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

    // MARK: - UserDefaults

    enum UserDefaultsKey {
        /// Only control whether watermark embedding is recorded in SwiftData (`WatermarkHistoryRecord` embed rows).
        static let autoLogWatermarkEmbed = "phantomstamp.settings.autoLogWatermarkEmbed"
        static let compactHistoryList = "phantomstamp.settings.compactHistoryList"
        /// User toggle for local notifications after embed/extract complete (`WatermarkOperationNotificationService`).
        static let watermarkOperationNotifications = "phantomstamp.settings.watermarkOperationNotifications"
    }

    enum SettingsDefault {
        static let autoLogWatermarkEmbed = true
        static let compactHistoryList = false
        static let watermarkOperationNotifications = true
    }

    // MARK: - History record kind (SwiftData `HistoryEntry.kind`)

    enum HistoryRecordKind {
        static let watermarkEmbedded = "watermark.embedded"
    }

    // MARK: - Watermark (Mock / Real delay and placeholder)

    enum Watermark {
        static let mockEmbedDelayNanoseconds: UInt64 = 2_000_000_000
        static let mockExtractDelayNanoseconds: UInt64 = 1_000_000_000
        /// Strip height (pixels); the image height must be a multiple of this value and aligned with 8 for the algorithm to work.
        static let stripHeightPixels = 80
        /// Smooth block variance threshold, below which embedding is skipped for stealth (privacy).
        static let smoothBlockVarianceThreshold: Float = 10.5
        /// Minimum side length (points), below which `WatermarkService` throws `imageTooSmall` (matches algorithm pseudocode).
        static let minimumImageSidePoints: CGFloat = 128
        static let mockExtractResultText = "Test_Copyright_2026"
        static let embedSampleText = "MyText"
        static let sampleSystemSymbolName = "photo.fill"
    }

    // MARK: - Info.plist

    enum InfoPlistKey {
        static let marketingVersion = "CFBundleShortVersionString"
    }

    enum VersionFallback {
        static let marketingUnknown = "0"
    }

    // MARK: - Debug / Error

    enum Debug {
        static let launchLogPrefix = "[PhantomStamp] launch, marketing version = "
    }

    enum ErrorMessage {
        static let modelContainerPrefix = "Could not create ModelContainer: "
    }

    // MARK: - Layout

    enum Layout {
        static let watermarkSectionSpacing: CGFloat = 20
        static let watermarkPreviewMaxHeight: CGFloat = 280
        static let watermarkPreviewCornerRadius: CGFloat = 20
        static let watermarkCardPadding: CGFloat = 14
        static let watermarkActionsCardCornerRadius: CGFloat = 16
        static let historyRowInnerSpacing: CGFloat = 4
        static let historyRowPaddingCompact: CGFloat = 2
        static let historyRowPaddingRegular: CGFloat = 6
    }

    // MARK: - SF Symbols

    enum Symbol {
        static let tabWatermark = "wand.and.stars"
        static let tabHistory = "clock.arrow.circlepath"
        static let tabSettings = "gearshape.fill"
    }

    // MARK: - Text (UI)

    enum Copy {

        enum Tab {
            static let watermark = "Embed"
            static let history = "History"
            static let settings = "Settings"
        }

        enum Watermark {
            static let navigationTitle = "Test Page"
            static let alertTitle = "Alert"
            static let embedButton = "Embed Watermark"
            static let extractButton = "Extract Watermark"
            static let okButton = "OK"
            static let sectionPreview = "Preview"
            static let sectionActions = "Actions"
            static let sectionExtractResult = "Extract Result"
            static let extractPlaceholder = "The result will be displayed here after extracting the watermark."
            static let processing = "Processing…"
            static let embedChipFormat = "Example Text · %@"
            static let tipArchitectureTitle = "DependencyInjection"
            static let tipHistoryTitle = "History"
            static let captionDependencyInjection = "The view only depends on WatermarkServiceProtocol; at runtime, use WatermarkService; for SwiftUI Preview, use PreviewWatermarkService; for unit tests, use Mock in Tests."
            static let captionHistoryHintWhenLogging = "Only when watermark embedding is successful will it be recorded in history (can be disabled in Settings)."
            static let captionHistoryHintWhenNotLogging = "Disabled: watermark embedding is not recorded when successful."
        }

        /// Copy for `UNUserNotificationCenter` alerts after watermark work completes.
        enum WatermarkPush {
            static let embedSingleSuccessTitle = "Watermark embedded"
            static let embedSingleSuccessBody = "Your image was watermarked successfully."
            static let embedSingleFailureTitle = "Watermark embed failed"
            static let extractSingleSuccessTitle = "Watermark extracted"
            static let extractSingleSuccessBodyPrefix = "Payload: "
            static let extractSingleFailureTitle = "Watermark extract failed"
            static let batchEmbedDoneTitle = "Batch embed finished"
            static let batchEmbedDoneBodyFormat = "Succeeded: %d, failed: %d."
            static let batchExtractDoneTitle = "Batch extract finished"
            static let batchExtractDoneBodyFormat = "Succeeded: %d, failed: %d."
            static let genericErrorBody = "Something went wrong."
        }

        // AppConstants.Copy.History.navigationTitle
        enum History {
            static let navigationTitle = "History"
            static let clearButton = "Clear"
            static let printWatermarkRecordsButton = "Print saved watermark records"
            static let emptyTitle = "No History"
            static let emptyDescription = "When watermark embedding is successful on the watermark page, and \"Auto Log Watermark Embed\" is enabled in the settings, it will appear here."
            static let logWatermarkEmbeddedFormat = "Watermark Embedding Completed (Text: %@)"
        }

        enum Settings {
            static let navigationTitle = "Settings"
            static let sectionHistory = "History"
            static let sectionAppearance = "Layout"
            static let sectionNotifications = "Notifications"
            static let toggleAutoLogWatermarkEmbed = "Auto Log Watermark Embed"
            static let footnoteAutoLogWatermarkEmbed = "When off, successful watermark embedding is not saved to SwiftData history. Stored in UserDefaults."
            static let toggleWatermarkOperationNotifications = "Watermark Finish Alerts"
            static let footnoteWatermarkOperationNotifications = "Local notifications when embedding or extraction completes (single image: per result; batch: one summary). Stored in UserDefaults."
            static let toggleCompactHistory = "Compact History List"
            static let footnoteCompactHistory = "Persisted using UserDefaults, retained after app restart."
        }

        enum Footer {
            static let versionPrefix = "PhantomStamp v"
        }

        enum Preview {
            static let sectionCaption = "Example Description"
        }
    }
}
