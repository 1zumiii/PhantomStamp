//
//  ProgressNotify.swift
//  PhantomStamp
//
//  Created by Orion on 5/5/2026.
//

import Foundation

extension AppConstants {
    enum Notifications {
        // Fixed notification channel name
        static let watermarkProgress = Notification.Name("WatermarkProgress")
        /// Batch-level progress for multi-file processing (completed / total).
        static let watermarkBatchProgress = Notification.Name("WatermarkBatchProgress")
        /// UI ack: per-file progress reached 100% and queue drained (for sequential batch pacing).
        static let watermarkPerFileProgressDidDrain = Notification.Name("WatermarkPerFileProgressDidDrain")
        /// Broadcast to show a full-screen progress overlay (embed/extract session start).
        static let watermarkProgressOverlayDidStart = Notification.Name("WatermarkProgressOverlayDidStart")
        /// UI ack posted after the overlay has had a frame to become visible.
        static let watermarkProgressOverlayDidPresent = Notification.Name("WatermarkProgressOverlayDidPresent")
        /// Broadcast to hide the full-screen progress overlay (embed/extract session end).
        static let watermarkProgressOverlayDidEnd = Notification.Name("WatermarkProgressOverlayDidEnd")

        // Demo-only (WatermarkInsertDemoView) full-screen overlay
        static let demoProgressOverlayDidStart = Notification.Name("DemoProgressOverlayDidStart")
        static let demoProgressOverlayDidEnd = Notification.Name("DemoProgressOverlayDidEnd")
        static let demoProgressDidUpdate = Notification.Name("DemoProgressDidUpdate")
        /// Posted after a `WatermarkHistoryRecord` is inserted or removed so the History tab can reload.
        static let watermarkHistoryRecordsDidChange = Notification.Name("WatermarkHistoryRecordsDidChange")

        // Robustness / internal test page (RobustnessTestingView)
        static let robustnessTestProgressOverlayDidStart = Notification.Name("RobustnessTestProgressOverlayDidStart")
        static let robustnessTestProgressDidUpdate = Notification.Name("RobustnessTestProgressDidUpdate")
        static let robustnessTestProgressOverlayDidEnd = Notification.Name("RobustnessTestProgressOverlayDidEnd")
    }
    
    // Fixed all possible operation stages
    enum WatermarkStep: String {
        // Embedding pipeline (frequency-domain watermark).
        case preparation = "Packing the secret into a tiny suitcase"
        case fecEncoding = "Adding a little protection for the journey"
        case macroblockBuild = "Teaching the message its hiding pattern"

        case colorConversion = "Finding a quiet corner among the colors"
        case stripSlicing = "Making room between the pixels"

        case processingStrips = "Teaching the pixels to keep a secret"

        case reassembling = "Putting the picture back together"
        case rgbRebuild = "Polishing the last few pixels"

        // Extraction pipeline (bit recovery + decode).
        case extractPreparation = "Listening for something hidden"
        case extractConvertToYCbCr = "Looking beneath the colors"
        case extractOffsetScan = "Following the faint pixel trail"
        case extractBitGrid = "Gathering the scattered clues"
        case extractMajorityVoting = "Letting the clues compare notes"
        case extractDecodeFEC = "Opening the message"

        case extractDetectTransforms = "Seeking the brightest star"
        case extractDeskew = "Straightening the picture frame"

        var isExtraction: Bool {
            switch self {
            case .extractPreparation,
                 .extractConvertToYCbCr,
                 .extractOffsetScan,
                 .extractBitGrid,
                 .extractMajorityVoting,
                 .extractDecodeFEC,
                 .extractDetectTransforms,
                 .extractDeskew:
                return true
            default:
                return false
            }
        }
    }
}

/// Single-file progress payload for UI overlays.
struct ProgressPayload {
    let step: AppConstants.WatermarkStep
    let percentage: Double // 0.0 to 1.0
}

/// Multi-file batch progress payload for UI overlays.
struct BatchProgressPayload: Sendable {
    let completed: Int
    let total: Int
    /// 0-based index of the file currently being processed.
    /// When `current` changes, the UI should reset the per-file progress bar.
    let current: Int
}

/// UI ack payload indicating the current file's progress display drained.
struct PerFileProgressDrainPayload: Sendable {
    let current: Int
}

/// Demo-only payload for UI progress overlays (English copy).
struct DemoProgressPayload: Sendable {
    let title: String
    let detail: String
    let percentage: Double // 0.0 to 1.0
}

/// Progress payload for internal robustness / limit tests (`RobustnessTestingView`).
struct RobustnessTestProgressPayload: Sendable {
    enum Kind: String, Sendable {
        case compressionLimit = "JPEG quality limit"
        case cropLimit = "Crop limit"
        case syncTemplateBasic = "Sync template baseline"
        case syncTemplateSweep = "Geometric sweep"
        case multiFileEmbed = "Multi-file embed"
    }

    let kind: Kind
    let phase: String
    let percentage: Double
}
