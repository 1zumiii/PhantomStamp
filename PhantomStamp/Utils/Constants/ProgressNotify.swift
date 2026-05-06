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
    }
    
    // Fixed all possible operation stages
    enum WatermarkStep: String {
        case preparation = "数据准备中..."
        case colorConversion = "提取亮度通道..."
        case processingStrips = "频域水印嵌入中..."
        case reassembling = "图像重组中..."
    }
}

// 专门用于广播的进度载体
struct ProgressPayload {
    let step: AppConstants.WatermarkStep
    let percentage: Double // 0.0 to 1.0
}
