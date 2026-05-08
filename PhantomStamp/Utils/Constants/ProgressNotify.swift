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
        case preparation = "Preparing payload..."
        case fecEncoding = "Applying FEC..."
        case macroblockBuild = "Building 2D tile..."

        case colorConversion = "Extracting luminance (Y)..."
        case stripSlicing = "Slicing luminance into strips..."

        case processingStrips = "Embedding bits into DCT blocks..."

        case reassembling = "Reassembling luminance..."
        case rgbRebuild = "Rebuilding final image..."
    }
}

// 专门用于广播的进度载体
struct ProgressPayload {
    let step: AppConstants.WatermarkStep
    let percentage: Double // 0.0 to 1.0
}

/// Demo-only payload for UI progress overlays (English copy).
struct DemoProgressPayload: Sendable {
    let title: String
    let detail: String
    let percentage: Double // 0.0 to 1.0
}
