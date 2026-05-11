//
//  ExtractionRecord.swift
//  PhantomStamp
//

import SwiftUI
import UIKit

enum ExtractionStatus: String, CaseIterable, Identifiable {
    case pending = "Pending"
    case extracted = "Extracted"
    case failed = "Not Found"

    var id: String { rawValue }

    var title: String { rawValue }

    var tintColor: Color {
        switch self {
        case .pending:
            return .orange
        case .extracted:
            return .green
        case .failed:
            return .orange
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
    /// Input image (the stamped / possibly watermarked source).
    var image: UIImage?
    /// Output image after extraction (e.g. watermark removed / recovered image), when available.
    var extractedImage: UIImage?
    var status: ExtractionStatus
    var message: String?
    var confidence: Double?
    var failureReason: String?
    /// Wall-clock processing duration for extraction, when available.
    var durationMs: Double?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        imageName: String,
        image: UIImage? = nil,
        extractedImage: UIImage? = nil,
        status: ExtractionStatus = .pending,
        message: String? = nil,
        confidence: Double? = nil,
        failureReason: String? = nil,
        durationMs: Double? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.imageName = imageName
        self.image = image
        self.extractedImage = extractedImage
        self.status = status
        self.message = message
        self.confidence = confidence
        self.failureReason = failureReason
        self.durationMs = durationMs
        self.createdAt = createdAt
    }
}

