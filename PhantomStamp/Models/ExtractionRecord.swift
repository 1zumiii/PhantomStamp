//
//  ExtractionRecord.swift
//  PhantomStamp
//

import SwiftUI
import UIKit

struct ExtractionDiagnosticsSnapshot: Equatable, Sendable {
    var durationMs: Double
    var syncMatchCount: Int?
    var deskewAngleDegrees: Double?
    var deskewScale: Double?
    var topologyHypothesisRawValue: String?
    var gridOffsetXPx: Int?
    var gridOffsetYPx: Int?
    var majoritySyncBits: Int?
    var macroTileWidth: Int?
    var rawBitGridRows: Int?
    var rawBitGridCols: Int?
}

struct WatermarkExtractionResult: Equatable, Sendable {
    var text: String
    var diagnostics: ExtractionDiagnosticsSnapshot
}

enum ExtractionStatus: String, CaseIterable, Identifiable {
    case pending = "Pending"
    case extracted = "Extracted"
    case failed = "Not Found"

    var id: String { rawValue }

    var title: String { rawValue }

    var tintColor: Color {
        switch self {
        case .pending:
            return .purple
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
    /// Original source dimensions, retained even when `image` is compacted to a display preview.
    var imagePixelWidth: Int?
    var imagePixelHeight: Int?
    /// Output image after extraction (e.g. watermark removed / recovered image), when available.
    var extractedImage: UIImage?
    var status: ExtractionStatus
    var message: String?
    var confidence: Double?
    var failureReason: String?
    /// Wall-clock processing duration for extraction, when available.
    var durationMs: Double?
    var diagnostics: ExtractionDiagnosticsSnapshot?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        imageName: String,
        image: UIImage? = nil,
        imagePixelWidth: Int? = nil,
        imagePixelHeight: Int? = nil,
        extractedImage: UIImage? = nil,
        status: ExtractionStatus = .pending,
        message: String? = nil,
        confidence: Double? = nil,
        failureReason: String? = nil,
        durationMs: Double? = nil,
        diagnostics: ExtractionDiagnosticsSnapshot? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.imageName = imageName
        self.image = image
        self.imagePixelWidth = imagePixelWidth
        self.imagePixelHeight = imagePixelHeight
        self.extractedImage = extractedImage
        self.status = status
        self.message = message
        self.confidence = confidence
        self.failureReason = failureReason
        self.durationMs = durationMs
        self.diagnostics = diagnostics
        self.createdAt = createdAt
    }
}
