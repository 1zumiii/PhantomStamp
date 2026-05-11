//
//  WatermarkHistoryRecord.swift
//  PhantomStamp
//
//  Created by Orion on 9/5/2026.
//

import Foundation
import SwiftData

// MARK: - Enums for State Machine

enum OperationType: String, Codable {
    case embed = "Embed"
    case extract = "Extract"
}

enum OperationStatus: String, Codable {
    case success = "Success"
    case failed = "Failed"
}

// MARK: - SwiftData Model

@Model
final class WatermarkHistoryRecord {
    // Unique identifier
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    
    // Operation type and status (corresponding to Tag colors and text on the UI)
    var operationType: OperationType
    var status: OperationStatus
    
    // Business data
    /// Text content extracted or embedded. If extraction fails, this field is nil.
    var payload: String?
    /// Error log. Only has a value when status == .failed, to help users click to see why it failed.
    var errorMessage: String?
    
    // Image metadata for UI (list uses small thumbnails; detail uses optional larger preview, not raw camera originals)
    /// Extremely compressed thumbnail data (recommended JPEG, q=0.5, size should be within 200x200)
    /// Use .externalStorage to tell SwiftData to automatically detach to an external file when the data is large, to ensure the speed of SQLite queries.
    @Attribute(.externalStorage) var thumbnailData: Data?
    /// Larger JPEG for the history detail hero (downscaled from the source at save time; not the raw camera file).
    /// Older rows may have `nil` here and fall back to `thumbnailData`.
    @Attribute(.externalStorage) var detailPreviewData: Data?
    var imageWidth: Int
    var imageHeight: Int
    
    /// Processing time (milliseconds)
    var processingDurationMs: Double
    /// If Extract, you can record the number of found sync headers (e.g. 32, representing perfect match)
    var syncMatchCount: Int?
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        operationType: OperationType,
        status: OperationStatus,
        payload: String? = nil,
        errorMessage: String? = nil,
        thumbnailData: Data? = nil,
        detailPreviewData: Data? = nil,
        imageWidth: Int = 0,
        imageHeight: Int = 0,
        processingDurationMs: Double = 0,
        syncMatchCount: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.operationType = operationType
        self.status = status
        self.payload = payload
        self.errorMessage = errorMessage
        self.thumbnailData = thumbnailData
        self.detailPreviewData = detailPreviewData
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.processingDurationMs = processingDurationMs
        self.syncMatchCount = syncMatchCount
    }
}
