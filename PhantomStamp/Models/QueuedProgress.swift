//
//  QueuedProgress.swift
//  PhantomStamp
// 
//

import Foundation

struct QueuedProgress: Sendable {
    let step: AppConstants.WatermarkStep
    let percentage: Double
    let enqueuedAt: UInt64

    static func priorityOrder(_ lhs: QueuedProgress, _ rhs: QueuedProgress) -> Bool {
        if lhs.percentage != rhs.percentage { return lhs.percentage < rhs.percentage }
        return lhs.enqueuedAt < rhs.enqueuedAt
    }
}

