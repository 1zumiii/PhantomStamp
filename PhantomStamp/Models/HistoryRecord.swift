// Models/HistoryRecord.swift
// PhantomStamp
//
// Defines the core data model for a watermarking history record.
// Uses struct (value semantics) and enums (type-safe domain values).
// All properties are immutable — updates are made by replacing the record in the array.

import Foundation

// MARK: - Operation Type

/// Represents the kind of watermarking operation that was performed.
enum HistoryOperationType: String, CaseIterable, Identifiable, Codable {
    case embedded  = "embedded"
    case extracted = "extracted"

    var id: String { rawValue }

    /// Human-readable label shown in the detail view
    var displayName: String {
        switch self {
        case .embedded:  return "Embed Watermark"
        case .extracted: return "Extract Watermark"
        }
    }

    /// Short label used in the filter bar
    var filterLabel: String {
        switch self {
        case .embedded:  return "Embedded"
        case .extracted: return "Extracted"
        }
    }
}

// MARK: - Record Status

/// Represents the outcome of a watermarking operation.
enum HistoryRecordStatus: String, CaseIterable, Identifiable, Codable {
    case exported  = "exported"   // embed succeeded, file saved
    case extracted = "extracted"  // extract succeeded, watermark found
    case failed    = "failed"     // operation did not complete successfully

    var id: String { rawValue }

    /// Human-readable label shown on status tags
    var displayName: String {
        switch self {
        case .exported:  return "Exported"
        case .extracted: return "Extracted"
        case .failed:    return "Failed"
        }
    }

    /// Convenience — avoids sprinkling `!= .failed` checks across views
    var isSuccess: Bool {
        switch self {
        case .exported, .extracted: return true
        case .failed:               return false
        }
    }
}

// MARK: - History Record

/// A single record in the watermarking history.
///
/// Designed as a value type (struct) so that:
/// - Copies are cheap and safe to pass across views
/// - SwiftUI diffing works correctly
/// - ViewModel can replace individual records without mutation
struct HistoryRecord: Identifiable, Equatable, Codable {

    // MARK: Identity
    let id: UUID

    // MARK: File info
    let fileName: String

    /// Name of the image asset in Assets.xcassets
    /// Add sample_cosmetic, sample_qvb, sample_opera, sample_cat to Assets.xcassets
    let thumbnailImageName: String

    let imageFormat: String   // e.g. "JPG", "PNG"
    let imageWidth: Int       // pixels
    let imageHeight: Int      // pixels

    // MARK: Operation
    let operationType: HistoryOperationType
    let status: HistoryRecordStatus

    /// The watermark string — present for embed operations; may be recovered on extract
    let watermarkText: String?

    /// Milliseconds taken by the watermark algorithm
    let processingDurationMs: Double

    // MARK: Metadata
    let createdAt: Date

    /// e.g. "High", "Medium" — nil for failed records
    let qualityLabel: String?

    /// Non-nil only when status == .failed
    let errorMessage: String?

    // MARK: Init

    init(
        id: UUID = UUID(),
        fileName: String,
        operationType: HistoryOperationType,
        status: HistoryRecordStatus,
        watermarkText: String? = nil,
        thumbnailImageName: String,
        imageFormat: String,
        imageWidth: Int,
        imageHeight: Int,
        processingDurationMs: Double,
        createdAt: Date = Date(),
        qualityLabel: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id                   = id
        self.fileName             = fileName
        self.operationType        = operationType
        self.status               = status
        self.watermarkText        = watermarkText
        self.thumbnailImageName   = thumbnailImageName
        self.imageFormat          = imageFormat
        self.imageWidth           = imageWidth
        self.imageHeight          = imageHeight
        self.processingDurationMs = processingDurationMs
        self.createdAt            = createdAt
        self.qualityLabel         = qualityLabel
        self.errorMessage         = errorMessage
    }
}
