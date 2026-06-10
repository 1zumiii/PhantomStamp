//
//  QueuedProgress.swift
//  PhantomStamp
//  Created by Orion on 9/5/2026.
//

import Foundation

struct QueuedProgress: Sendable {
    let step: AppConstants.WatermarkStep
    let percentage: Double
    let enqueuedAt: UInt64
    /// When set (robustness tests), shown instead of `step.rawValue`.
    let detailOverride: String?

    init(
        step: AppConstants.WatermarkStep,
        percentage: Double,
        enqueuedAt: UInt64,
        detailOverride: String? = nil
    ) {
        self.step = step
        self.percentage = percentage
        self.enqueuedAt = enqueuedAt
        self.detailOverride = detailOverride
    }

    static func priorityOrder(_ lhs: QueuedProgress, _ rhs: QueuedProgress) -> Bool {
        if lhs.percentage != rhs.percentage { return lhs.percentage < rhs.percentage }
        return lhs.enqueuedAt < rhs.enqueuedAt
    }
}

