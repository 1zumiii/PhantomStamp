//
//  ExtractionRecord.swift
//  PhantomStamp
//

import SwiftUI
import UIKit

enum ExtractionStatus: String, CaseIterable, Identifiable {
    case pending = "Pending"
    case extracted = "Extracted"
    case failed = "Failed"

    var id: String { rawValue }

    var title: String {
        rawValue
    }

    var tintColor: Color {
        switch self {
        case .pending:
            return .orange
        case .extracted:
            return .green
        case .failed:
            return .red
        }
    }

    var iconName: String {
        switch self {
        case .pending:
            return "clock.fill"
        case .extracted:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }
}

struct ExtractionRecord: Identifiable, Equatable {
    let id: UUID
    var imageName: String
    var image: UIImage?
    var status: ExtractionStatus
    var message: String?
    var confidence: Double?
    var failureReason: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        imageName: String,
        image: UIImage? = nil,
        status: ExtractionStatus = .pending,
        message: String? = nil,
        confidence: Double? = nil,
        failureReason: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.imageName = imageName
        self.image = image
        self.status = status
        self.message = message
        self.confidence = confidence
        self.failureReason = failureReason
        self.createdAt = createdAt
    }
}
