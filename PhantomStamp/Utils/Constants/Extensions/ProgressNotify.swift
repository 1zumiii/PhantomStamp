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
        /// Embed preparation: validates the image, FEC-encodes the text, adds the sync marker,
        /// and folds the resulting bits into the repeating 2D watermark tile.
        case preparation = "Packing the secret into a tiny suitcase"

        /// Reserved granular embed step: adds forward-error-correction redundancy to the payload.
        case fecEncoding = "Adding a little protection for the journey"

        /// Reserved granular embed step: arranges the encoded payload into its repeating tile pattern.
        case macroblockBuild = "Teaching the message its hiding pattern"

        /// Embed color/layout step: converts RGB pixels to YCbCr and prepares the luminance channel.
        case colorConversion = "Finding a quiet corner among the colors"

        /// Reserved granular embed step: divides the luminance plane into independently processed strips.
        case stripSlicing = "Making room between the pixels"

        /// Embed frequency step: runs the strip tasks, applies block DCT, and hides payload bits.
        case processingStrips = "Teaching the pixels to keep a secret"

        /// Embed assembly step: writes processed strips back into the full luminance plane
        /// and applies the spatial synchronization template.
        case reassembling = "Putting the picture back together"

        /// Embed finishing step: converts the completed YCbCr image back to a displayable RGB image.
        case rgbRebuild = "Polishing the last few pixels"

        // Extraction pipeline (bit recovery + decode).
        /// Extraction setup: validates input and starts the detached matrix-processing task.
        case extractPreparation = "Listening for something hidden"

        /// Extraction color step: converts the source image to YCbCr and selects its luminance plane.
        case extractConvertToYCbCr = "Looking beneath the colors"

        /// Extraction alignment step: scans all 64 pixel-grid offsets and topology hypotheses.
        case extractOffsetScan = "Following the faint pixel trail"

        /// Extraction sampling step: reads signed DCT coefficient differences into the raw soft-bit grid.
        case extractBitGrid = "Gathering the scattered clues"

        /// Reserved granular extraction step: folds repeated tiles and performs confidence-weighted voting.
        case extractMajorityVoting = "Letting the clues compare notes"

        /// Extraction finishing step: tries the expected payload lengths and decodes Hamming FEC.
        case extractDecodeFEC = "Opening the message"

        /// Extraction geometry step: detects rotation and scale from the spatial sync template.
        case extractDetectTransforms = "Seeking the brightest star"

        /// Reserved granular extraction step: resamples the luminance plane to undo detected geometry.
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
