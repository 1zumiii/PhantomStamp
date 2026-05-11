//
//  OperationDetailDisplay.swift
//  PhantomStamp
//
//  Shared presentation model for the unified operation detail screen
//  (in-session extraction rows and persisted `WatermarkHistoryRecord` rows).
//

import UIKit

private enum ImageFilePresentation {
    /// Name without path extension (for navigation titles and list titles).
    static func baseName(from fullFileName: String) -> String {
        let s = fullFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "Image" }
        let base = (s as NSString).deletingPathExtension
        return base.isEmpty ? s : base
    }

    /// Uppercase extension for small badges (e.g. `JPG`); defaults to `JPG` when missing.
    static func extensionUpper(from fullFileName: String) -> String {
        let ext = (fullFileName as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "JPG" : ext
    }
}

struct OperationDetailDisplay {
    enum DetailStatus: Equatable {
        case pending
        case success
        case failed
    }

    enum OperationKind: Equatable {
        case extract
        case embed
    }

    var imageName: String
    var previewImage: UIImage?
    var operationKind: OperationKind
    var status: DetailStatus
    /// Extracted or embedded watermark text, when applicable.
    var primaryText: String?
    var failureReason: String?
    var durationMs: Double?
    var imagePixelWidth: Int?
    var imagePixelHeight: Int?
    var occurredAt: Date
    /// Offset-scan phase: best sync bits matched (out of 32). Extract only; embed rows leave this `nil`.
    var syncMatchCount: Int?
    var embedVisited8x8BlockCount: Int?
    var embedSmoothSkipped8x8BlockCount: Int?
    var extractGridOffsetXPx: Int?
    var extractGridOffsetYPx: Int?
    var extractMajoritySyncBits: Int?
    var extractMacroTileWidth: Int?
    var extractRawBitGridRows: Int?
    var extractRawBitGridCols: Int?
    /// When non-`nil`, this row exists in SwiftData history and may be deleted from the detail screen.
    var persistedHistoryRecordId: UUID?

    init(
        imageName: String,
        previewImage: UIImage?,
        operationKind: OperationKind,
        status: DetailStatus,
        primaryText: String?,
        failureReason: String?,
        durationMs: Double?,
        imagePixelWidth: Int?,
        imagePixelHeight: Int?,
        occurredAt: Date,
        syncMatchCount: Int? = nil,
        embedVisited8x8BlockCount: Int? = nil,
        embedSmoothSkipped8x8BlockCount: Int? = nil,
        extractGridOffsetXPx: Int? = nil,
        extractGridOffsetYPx: Int? = nil,
        extractMajoritySyncBits: Int? = nil,
        extractMacroTileWidth: Int? = nil,
        extractRawBitGridRows: Int? = nil,
        extractRawBitGridCols: Int? = nil,
        persistedHistoryRecordId: UUID? = nil
    ) {
        self.imageName = imageName
        self.previewImage = previewImage
        self.operationKind = operationKind
        self.status = status
        self.primaryText = primaryText
        self.failureReason = failureReason
        self.durationMs = durationMs
        self.imagePixelWidth = imagePixelWidth
        self.imagePixelHeight = imagePixelHeight
        self.occurredAt = occurredAt
        self.syncMatchCount = syncMatchCount
        self.embedVisited8x8BlockCount = embedVisited8x8BlockCount
        self.embedSmoothSkipped8x8BlockCount = embedSmoothSkipped8x8BlockCount
        self.extractGridOffsetXPx = extractGridOffsetXPx
        self.extractGridOffsetYPx = extractGridOffsetYPx
        self.extractMajoritySyncBits = extractMajoritySyncBits
        self.extractMacroTileWidth = extractMacroTileWidth
        self.extractRawBitGridRows = extractRawBitGridRows
        self.extractRawBitGridCols = extractRawBitGridCols
        self.persistedHistoryRecordId = persistedHistoryRecordId
    }

    /// Title without file suffix (e.g. `IMG_abcd` from `IMG_abcd.jpg`).
    var navigationTitleName: String {
        ImageFilePresentation.baseName(from: imageName)
    }

    /// Uppercase type badge for thumbnails (e.g. `JPG`, `PNG`).
    var formatBadgeUppercase: String {
        ImageFilePresentation.extensionUpper(from: imageName)
    }
}

extension OperationDetailDisplay {
    init(extraction record: ExtractionRecord) {
        let detailStatus: DetailStatus
        switch record.status {
        case .pending: detailStatus = .pending
        case .extracted: detailStatus = .success
        case .failed: detailStatus = .failed
        }
        let iw: Int?
        let ih: Int?
        if let img = record.image {
            iw = Int((img.size.width * img.scale).rounded())
            ih = Int((img.size.height * img.scale).rounded())
        } else {
            iw = nil
            ih = nil
        }
        self.init(
            imageName: record.imageName,
            previewImage: record.image,
            operationKind: .extract,
            status: detailStatus,
            primaryText: record.message,
            failureReason: record.failureReason,
            durationMs: record.durationMs,
            imagePixelWidth: iw,
            imagePixelHeight: ih,
            occurredAt: record.createdAt,
            syncMatchCount: nil,
            embedVisited8x8BlockCount: nil,
            embedSmoothSkipped8x8BlockCount: nil,
            extractGridOffsetXPx: nil,
            extractGridOffsetYPx: nil,
            extractMajoritySyncBits: nil,
            extractMacroTileWidth: nil,
            extractRawBitGridRows: nil,
            extractRawBitGridCols: nil,
            persistedHistoryRecordId: nil
        )
    }

    init(history record: WatermarkHistoryRecord) {
        let preview = record.detailPreviewData.flatMap { UIImage(data: $0) }
            ?? record.thumbnailData.flatMap { UIImage(data: $0) }
        let detailStatus: DetailStatus = record.status == .success ? .success : .failed
        let kind: OperationKind = record.operationType == .embed ? .embed : .extract
        let imageName = Self.historyListFileName(for: record)
        self.init(
            imageName: imageName,
            previewImage: preview,
            operationKind: kind,
            status: detailStatus,
            primaryText: record.payload,
            failureReason: record.errorMessage,
            durationMs: record.processingDurationMs,
            imagePixelWidth: record.imageWidth > 0 ? record.imageWidth : nil,
            imagePixelHeight: record.imageHeight > 0 ? record.imageHeight : nil,
            occurredAt: record.timestamp,
            syncMatchCount: record.syncMatchCount,
            embedVisited8x8BlockCount: record.embedVisited8x8BlockCount,
            embedSmoothSkipped8x8BlockCount: record.embedSmoothSkipped8x8BlockCount,
            extractGridOffsetXPx: record.extractGridOffsetXPx,
            extractGridOffsetYPx: record.extractGridOffsetYPx,
            extractMajoritySyncBits: record.extractMajoritySyncBits,
            extractMacroTileWidth: record.extractMacroTileWidth,
            extractRawBitGridRows: record.extractRawBitGridRows,
            extractRawBitGridCols: record.extractRawBitGridCols,
            persistedHistoryRecordId: record.id
        )
    }

    /// Full synthetic file name for history rows, alerts, and `imageName` (includes extension).
    static func historyListFileName(for record: WatermarkHistoryRecord) -> String {
        let trimmed = record.sourceImageName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return "IMG_\(String(record.id.uuidString.prefix(4))).jpg"
    }

    static func historyListTitleBase(for record: WatermarkHistoryRecord) -> String {
        ImageFilePresentation.baseName(from: historyListFileName(for: record))
    }

    static func historyListFormatBadge(for record: WatermarkHistoryRecord) -> String {
        ImageFilePresentation.extensionUpper(from: historyListFileName(for: record))
    }
}
