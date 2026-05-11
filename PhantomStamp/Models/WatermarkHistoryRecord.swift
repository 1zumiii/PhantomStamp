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
    /// Original file name from picker (e.g. `IMG_0021.jpg`). Optional for older rows.
    var sourceImageName: String?
    var imageWidth: Int
    var imageHeight: Int
    
    /// Processing time (milliseconds)
    var processingDurationMs: Double
    /// Offset-scan phase: best sync bits matched out of 32 (pixel grid search).
    var syncMatchCount: Int?

    // MARK: Embed diagnostics (optional; older rows may be nil)

    /// Total 8×8 block positions visited during strip embedding.
    var embedVisited8x8BlockCount: Int?
    /// Blocks skipped as “too smooth” (variance below threshold) and not modified.
    var embedSmoothSkipped8x8BlockCount: Int?
    /// The texture-variance threshold used for this embed run.
    var embedTextureVarianceThreshold: Double?

    // MARK: Extract diagnostics (optional)

    /// Chosen physical pixel offset of the 8×8 grid (sub-block alignment).
    var extractGridOffsetXPx: Int?
    var extractGridOffsetYPx: Int?
    /// Majority-voting phase: best sync header match (out of 32) on the bit grid.
    var extractMajoritySyncBits: Int?
    /// Inferred macro-tile width W used when folding tiles (typically 8…18).
    var extractMacroTileWidth: Int?
    /// Size of the raw per-block bit grid after `extractBitsWithOffset`.
    var extractRawBitGridRows: Int?
    var extractRawBitGridCols: Int?
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        operationType: OperationType,
        status: OperationStatus,
        payload: String? = nil,
        errorMessage: String? = nil,
        thumbnailData: Data? = nil,
        detailPreviewData: Data? = nil,
        sourceImageName: String? = nil,
        imageWidth: Int = 0,
        imageHeight: Int = 0,
        processingDurationMs: Double = 0,
        syncMatchCount: Int? = nil,
        embedVisited8x8BlockCount: Int? = nil,
        embedSmoothSkipped8x8BlockCount: Int? = nil,
        embedTextureVarianceThreshold: Double? = nil,
        extractGridOffsetXPx: Int? = nil,
        extractGridOffsetYPx: Int? = nil,
        extractMajoritySyncBits: Int? = nil,
        extractMacroTileWidth: Int? = nil,
        extractRawBitGridRows: Int? = nil,
        extractRawBitGridCols: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.operationType = operationType
        self.status = status
        self.payload = payload
        self.errorMessage = errorMessage
        self.thumbnailData = thumbnailData
        self.detailPreviewData = detailPreviewData
        self.sourceImageName = sourceImageName
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.processingDurationMs = processingDurationMs
        self.syncMatchCount = syncMatchCount
        self.embedVisited8x8BlockCount = embedVisited8x8BlockCount
        self.embedSmoothSkipped8x8BlockCount = embedSmoothSkipped8x8BlockCount
        self.embedTextureVarianceThreshold = embedTextureVarianceThreshold
        self.extractGridOffsetXPx = extractGridOffsetXPx
        self.extractGridOffsetYPx = extractGridOffsetYPx
        self.extractMajoritySyncBits = extractMajoritySyncBits
        self.extractMacroTileWidth = extractMacroTileWidth
        self.extractRawBitGridRows = extractRawBitGridRows
        self.extractRawBitGridCols = extractRawBitGridCols
    }
}
