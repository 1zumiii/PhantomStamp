//
//  HistoryRecordService.swift
//  PhantomStamp
//
//  Persists and queries `WatermarkHistoryRecord` (SwiftData). Call from the main actor
//  with a `ModelContext` obtained from SwiftUI (`@Environment(\.modelContext)`) or
//  `ModelContainer.mainContext`.
//
//  USAGE (typical SwiftUI wiring)
//  -----------------------------
//  1. Register `WatermarkHistoryRecord.self` in your app `Schema` and attach `.modelContainer(...)`.
//  2. Hold `ModelContext` on the service that runs watermark work (see `WatermarkService.historyModelContext`),
//     or pass `modelContext` from a view / view model into `insertAndSave` after operations.
//  3. After a successful or failed embed/extract, build a `WatermarkHistoryRecord` (or use the helpers below)
//     and call `insertAndSave(_:context:)`.
//  4. Load rows for a list: `try HistoryRecordService.fetchRecords(context: modelContext, limit: 100)`.
//  5. Delete one row: `try HistoryRecordService.deleteRecord(id: recordId, context: modelContext)`.
//
//  List thumbnails stay small (`thumbnailData`); detail hero uses optional `detailPreviewData` (larger downscale at save time).
//  JPEG bytes use `@Attribute(.externalStorage)` for large blobs.
//

import Foundation
import SwiftData
import UIKit

@MainActor
enum HistoryRecordService {

    private static let detailPreviewMaxPixelEdge: CGFloat = 2048
    private static let detailPreviewJPEGQuality: CGFloat = 0.82

    // MARK: - Thumbnail

    /// Downscales the image to fit within `maxPixelEdge` (points, scale 1) and encodes JPEG.
    /// Intended for history list previews only — not for exporting watermarked assets.
    static func makeThumbnailData(
        from image: UIImage,
        maxPixelEdge: CGFloat = 200,
        jpegQuality: CGFloat = 0.5
    ) -> Data? {
        let w = image.size.width * image.scale
        let h = image.size.height * image.scale
        guard w > 0, h > 0 else { return nil }

        let scale = min(1, maxPixelEdge / max(w, h))
        let target = CGSize(width: floor(w * scale), height: floor(h * scale))
        guard target.width >= 1, target.height >= 1 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let thumb = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return thumb.jpegData(compressionQuality: min(max(jpegQuality, 0.05), 0.95))
    }

    // MARK: - Pixel size

    static func pixelWidthHeight(of image: UIImage) -> (width: Int, height: Int) {
        let w = Int((image.size.width * image.scale).rounded())
        let h = Int((image.size.height * image.scale).rounded())
        return (max(w, 0), max(h, 0))
    }

    // MARK: - Write

    /// Inserts a new history row and persists the context (best-effort).
    static func insertAndSave(_ record: WatermarkHistoryRecord, context: ModelContext) {
        context.insert(record)
        PersistenceService.save(context)
        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkHistoryRecordsDidChange,
            object: nil
        )
    }

    // MARK: - Read

    /// Fetches watermark operation history, newest first by default.
    /// - Parameters:
    ///   - context: Active SwiftData context (usually the view’s `modelContext`).
    ///   - limit: Optional maximum number of rows (applied before optional type filtering when both are set).
    ///   - operationType: When non-`nil`, only rows matching this operation are returned.
    ///   - sortNewestFirst: When `true`, sorts by `timestamp` descending.
    static func fetchRecords(
        context: ModelContext,
        limit: Int? = nil,
        operationType: OperationType? = nil,
        sortNewestFirst: Bool = true
    ) throws -> [WatermarkHistoryRecord] {
        var descriptor = FetchDescriptor<WatermarkHistoryRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: sortNewestFirst ? .reverse : .forward)]
        )
        if let operationType {
            let op = operationType
            descriptor.predicate = #Predicate { $0.operationType == op }
        }
        if let limit {
            descriptor.fetchLimit = limit
        }
        return try context.fetch(descriptor)
    }

    // MARK: - Delete

    /// Deletes the `WatermarkHistoryRecord` with the given primary key `id`.
    /// - Returns: `true` if a matching row existed and was removed; `false` if nothing matched.
    /// - Throws: SwiftData fetch errors from `ModelContext.fetch`.
    @discardableResult
    static func deleteRecord(id: UUID, context: ModelContext) throws -> Bool {
        let targetId = id
        let descriptor = FetchDescriptor<WatermarkHistoryRecord>(
            predicate: #Predicate { $0.id == targetId }
        )
        guard let record = try context.fetch(descriptor).first else { return false }
        context.delete(record)
        PersistenceService.save(context)
        return true
    }

    // MARK: - Convenience builders

    /// Records a finished embed attempt. Pass the **same** `UIImage` you used for the thumbnail source
    /// (commonly the input photo before embed, or the watermarked output if you prefer that preview).
    static func makeEmbedRecord(
        succeeded: Bool,
        payloadText: String?,
        sourceImageForThumbnail: UIImage,
        sourceImageName: String? = nil,
        error: Error?,
        durationMs: Double,
        embedVisited8x8BlockCount: Int? = nil,
        embedSmoothSkipped8x8BlockCount: Int? = nil,
        thumbnailJPEGQuality: CGFloat = 0.5
    ) -> WatermarkHistoryRecord {
        let dims = pixelWidthHeight(of: sourceImageForThumbnail)
        let thumb = makeThumbnailData(from: sourceImageForThumbnail, jpegQuality: thumbnailJPEGQuality)
        let detail = makeThumbnailData(
            from: sourceImageForThumbnail,
            maxPixelEdge: detailPreviewMaxPixelEdge,
            jpegQuality: detailPreviewJPEGQuality
        )
        if succeeded {
            return WatermarkHistoryRecord(
                operationType: .embed,
                status: .success,
                payload: payloadText,
                errorMessage: nil,
                thumbnailData: thumb,
                detailPreviewData: detail,
                sourceImageName: sourceImageName,
                imageWidth: dims.width,
                imageHeight: dims.height,
                processingDurationMs: durationMs,
                syncMatchCount: nil,
                embedVisited8x8BlockCount: embedVisited8x8BlockCount,
                embedSmoothSkipped8x8BlockCount: embedSmoothSkipped8x8BlockCount
            )
        }
        return WatermarkHistoryRecord(
            operationType: .embed,
            status: .failed,
            payload: payloadText,
            errorMessage: error?.localizedDescription,
            thumbnailData: thumb,
            detailPreviewData: detail,
            sourceImageName: sourceImageName,
            imageWidth: dims.width,
            imageHeight: dims.height,
            processingDurationMs: durationMs,
            syncMatchCount: nil,
            embedVisited8x8BlockCount: embedVisited8x8BlockCount,
            embedSmoothSkipped8x8BlockCount: embedSmoothSkipped8x8BlockCount
        )
    }

    /// Records a finished extract attempt. On success, `payload` holds the decoded text.
    static func makeExtractRecord(
        succeeded: Bool,
        extractedText: String?,
        sourceImage: UIImage,
        sourceImageName: String? = nil,
        error: Error?,
        durationMs: Double,
        syncMatchCount: Int? = nil,
        extractGridOffsetXPx: Int? = nil,
        extractGridOffsetYPx: Int? = nil,
        extractMajoritySyncBits: Int? = nil,
        extractMacroTileWidth: Int? = nil,
        extractRawBitGridRows: Int? = nil,
        extractRawBitGridCols: Int? = nil,
        thumbnailJPEGQuality: CGFloat = 0.5
    ) -> WatermarkHistoryRecord {
        let dims = pixelWidthHeight(of: sourceImage)
        let thumb = makeThumbnailData(from: sourceImage, jpegQuality: thumbnailJPEGQuality)
        let detail = makeThumbnailData(
            from: sourceImage,
            maxPixelEdge: detailPreviewMaxPixelEdge,
            jpegQuality: detailPreviewJPEGQuality
        )
        if succeeded {
            return WatermarkHistoryRecord(
                operationType: .extract,
                status: .success,
                payload: extractedText,
                errorMessage: nil,
                thumbnailData: thumb,
                detailPreviewData: detail,
                sourceImageName: sourceImageName,
                imageWidth: dims.width,
                imageHeight: dims.height,
                processingDurationMs: durationMs,
                syncMatchCount: syncMatchCount,
                extractGridOffsetXPx: extractGridOffsetXPx,
                extractGridOffsetYPx: extractGridOffsetYPx,
                extractMajoritySyncBits: extractMajoritySyncBits,
                extractMacroTileWidth: extractMacroTileWidth,
                extractRawBitGridRows: extractRawBitGridRows,
                extractRawBitGridCols: extractRawBitGridCols
            )
        }
        return WatermarkHistoryRecord(
            operationType: .extract,
            status: .failed,
            payload: nil,
            errorMessage: error?.localizedDescription,
            thumbnailData: thumb,
            detailPreviewData: detail,
            sourceImageName: sourceImageName,
            imageWidth: dims.width,
            imageHeight: dims.height,
            processingDurationMs: durationMs,
            syncMatchCount: syncMatchCount,
            extractGridOffsetXPx: extractGridOffsetXPx,
            extractGridOffsetYPx: extractGridOffsetYPx,
            extractMajoritySyncBits: extractMajoritySyncBits,
            extractMacroTileWidth: extractMacroTileWidth,
            extractRawBitGridRows: extractRawBitGridRows,
            extractRawBitGridCols: extractRawBitGridCols
        )
    }
}
