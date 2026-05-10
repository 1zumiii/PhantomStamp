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
        /// Broadcast to hide the full-screen progress overlay (embed/extract session end).
        static let watermarkProgressOverlayDidEnd = Notification.Name("WatermarkProgressOverlayDidEnd")

        // Demo-only (WatermarkInsertDemoView) full-screen overlay
        static let demoProgressOverlayDidStart = Notification.Name("DemoProgressOverlayDidStart")
        static let demoProgressOverlayDidEnd = Notification.Name("DemoProgressOverlayDidEnd")
        static let demoProgressDidUpdate = Notification.Name("DemoProgressDidUpdate")
    }
    
    // Fixed all possible operation stages
    enum WatermarkStep: String {
        // Embedding pipeline (frequency-domain watermark).
        case preparation = "Preparing payload"
        case fecEncoding = "Applying FEC"
        case macroblockBuild = "Building 2D tile"

        case colorConversion = "Extracting luminance (Y)"
        case stripSlicing = "Slicing luminance into strips"

        case processingStrips = "Embedding bits into DCT blocks"

        case reassembling = "Reassembling luminance"
        case rgbRebuild = "Rebuilding final image"

        // Extraction pipeline (bit recovery + decode).
        case extractPreparation = "Preparing extraction"
        case extractConvertToYCbCr = "Convert To YCbCr"
        case extractOffsetScan = "Perform offset scan"
        case extractBitGrid = "Extract Bits"
        case extractMajorityVoting = "Apply Majority Voting"
        case extractDecodeFEC = "Decode FEC"
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
