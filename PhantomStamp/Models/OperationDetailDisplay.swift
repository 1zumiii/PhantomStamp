//
//  OperationDetailDisplay.swift
//  PhantomStamp
//
//  Shared presentation model for the unified operation detail screen
//  (in-session extraction rows and persisted `WatermarkHistoryRecord` rows).
//

import SwiftUI
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
    var embedTextureVarianceThreshold: Double?
    var embedEmbeddingStrength: Double?
    var extractDeskewAngleDegrees: Double?
    var extractDeskewScale: Double?
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
        embedTextureVarianceThreshold: Double? = nil,
        embedEmbeddingStrength: Double? = nil,
        extractDeskewAngleDegrees: Double? = nil,
        extractDeskewScale: Double? = nil,
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
        self.embedTextureVarianceThreshold = embedTextureVarianceThreshold
        self.embedEmbeddingStrength = embedEmbeddingStrength
        self.extractDeskewAngleDegrees = extractDeskewAngleDegrees
        self.extractDeskewScale = extractDeskewScale
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
            embedTextureVarianceThreshold: nil,
            embedEmbeddingStrength: nil,
            extractDeskewAngleDegrees: nil,
            extractDeskewScale: nil,
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
            embedTextureVarianceThreshold: record.embedTextureVarianceThreshold,
            embedEmbeddingStrength: record.embedEmbeddingStrength,
            extractDeskewAngleDegrees: record.extractDeskewAngleDegrees,
            extractDeskewScale: record.extractDeskewScale,
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

    /// Grouped diagnostics for the unified detail screen.
    var diagnosticsSections: [OperationDiagnosticsSectionModel] {
        var sections: [OperationDiagnosticsSectionModel] = [fileInfoSection]
        switch operationKind {
        case .embed:
            if let embed = embedDiagnosticsSection { sections.append(embed) }
        case .extract:
            if let geometry = extractGeometrySection { sections.append(geometry) }
            if let alignment = extractAlignmentSection { sections.append(alignment) }
            if let decoding = extractDecodingSection { sections.append(decoding) }
        }
        return sections.filter { !$0.rows.isEmpty }
    }

    private var fileInfoSection: OperationDiagnosticsSectionModel {
        let sizeText: String = {
            if let w = imagePixelWidth, let h = imagePixelHeight, w > 0, h > 0 {
                return HistoryFormatters.imageSize(width: w, height: h)
            }
            if let img = previewImage {
                let w = Int(img.size.width * img.scale)
                let h = Int(img.size.height * img.scale)
                return HistoryFormatters.imageSize(width: w, height: h)
            }
            return "—"
        }()
        let formatText: String = {
            let ext = (imageName as NSString).pathExtension.uppercased()
            return ext.isEmpty ? "—" : ext
        }()
        let durationText: String = {
            guard let ms = durationMs else { return "—" }
            return HistoryFormatters.processingDuration(ms: ms)
        }()

        return OperationDiagnosticsSectionModel(
            id: "file",
            title: "FILE INFO",
            rows: [
                OperationDiagnosticsRow(id: "duration", title: "Processing", value: durationText, systemImage: "clock"),
                OperationDiagnosticsRow(id: "format", title: "Format", value: formatText, systemImage: "doc", valueMonospaced: false),
                OperationDiagnosticsRow(id: "size", title: "Image size", value: sizeText, systemImage: "arrow.up.left.and.arrow.down.right")
            ]
        )
    }

    private var embedDiagnosticsSection: OperationDiagnosticsSectionModel? {
        let visited = embedVisited8x8BlockCount
        let skipped = embedSmoothSkipped8x8BlockCount
        let thr = embedTextureVarianceThreshold
        let intensity = embedEmbeddingStrength
        guard visited != nil || skipped != nil || thr != nil || intensity != nil else { return nil }

        var rows: [OperationDiagnosticsRow] = []
        if let t = thr {
            let sigmaValue: String = {
                if t < 0 { return "All" }
                guard let sigma = HistoryFormatters.textureSigma(fromVarianceThreshold: t) else { return "—" }
                return String(format: "%.1f", sigma)
            }()
            rows.append(OperationDiagnosticsRow(id: "sigma", title: "Texture σ threshold", value: sigmaValue, systemImage: "dial.low"))
        }
        if let intensityLabel = HistoryFormatters.formatEmbeddingStrength(intensity) {
            rows.append(OperationDiagnosticsRow(id: "intensity", title: "Embedding intensity", value: intensityLabel, systemImage: "flame", valueMonospaced: false))
        }
        if let v = visited {
            rows.append(OperationDiagnosticsRow(id: "visited", title: "8×8 blocks scanned", value: "\(v)", systemImage: "square.grid.3x3"))
        }
        if let s = skipped {
            rows.append(OperationDiagnosticsRow(id: "skipped", title: "Smooth blocks protected", value: "\(s)", systemImage: "wind"))
        }
        if let v = visited, v > 0 {
            let s = skipped ?? 0
            let embedded = max(0, v - s)
            let pct = 100.0 * Double(embedded) / Double(v)
            rows.append(OperationDiagnosticsRow(
                id: "rate",
                title: "Effective embed rate",
                value: String(format: "%.1f%% (%d / %d)", pct, embedded, v),
                systemImage: "percent",
                valueMonospaced: false
            ))
        }

        return OperationDiagnosticsSectionModel(id: "embed", title: "EMBED PARAMETERS", rows: rows)
    }

    private var extractGeometrySection: OperationDiagnosticsSectionModel? {
        guard extractDeskewAngleDegrees != nil || extractDeskewScale != nil else { return nil }

        var rows: [OperationDiagnosticsRow] = []
        if let angle = HistoryFormatters.formatDeskewAngle(degrees: extractDeskewAngleDegrees) {
            rows.append(OperationDiagnosticsRow(id: "angle", title: "Detected rotation", value: angle, systemImage: "rotate.right"))
        }
        if let scale = HistoryFormatters.formatDeskewScale(extractDeskewScale) {
            rows.append(OperationDiagnosticsRow(id: "scale", title: "Detected scale", value: scale, systemImage: "arrow.up.left.and.arrow.down.right"))
        }
        let applied = HistoryFormatters.deskewWasApplied(
            angleDegrees: extractDeskewAngleDegrees,
            scale: extractDeskewScale
        )
        rows.append(OperationDiagnosticsRow(
            id: "deskew",
            title: "Deskew applied",
            value: applied ? "Yes" : "No (identity)",
            systemImage: "perspective",
            valueMonospaced: false
        ))

        return OperationDiagnosticsSectionModel(id: "geometry", title: "GEOMETRIC CORRECTION", rows: rows)
    }

    private var extractAlignmentSection: OperationDiagnosticsSectionModel? {
        let hasAny = syncMatchCount != nil
            || extractGridOffsetXPx != nil
            || extractGridOffsetYPx != nil
            || extractRawBitGridRows != nil
        guard hasAny else { return nil }

        var rows: [OperationDiagnosticsRow] = []
        if let sync = syncMatchCount {
            rows.append(OperationDiagnosticsRow(id: "offsetSync", title: "Offset scan sync", value: "\(sync) / 32", systemImage: "scope"))
        }
        if extractGridOffsetXPx != nil || extractGridOffsetYPx != nil {
            let xStr = extractGridOffsetXPx.map(String.init) ?? "—"
            let yStr = extractGridOffsetYPx.map(String.init) ?? "—"
            rows.append(OperationDiagnosticsRow(id: "offset", title: "Pixel grid offset", value: "(\(xStr), \(yStr))", systemImage: "arrow.up.left"))
        }
        if let rowsCount = extractRawBitGridRows, let cols = extractRawBitGridCols {
            rows.append(OperationDiagnosticsRow(id: "grid", title: "Raw bit grid", value: "\(rowsCount) × \(cols)", systemImage: "square.grid.2x2"))
        }

        return OperationDiagnosticsSectionModel(id: "alignment", title: "GRID ALIGNMENT", rows: rows)
    }

    private var extractDecodingSection: OperationDiagnosticsSectionModel? {
        guard extractMajoritySyncBits != nil || extractMacroTileWidth != nil else { return nil }

        var rows: [OperationDiagnosticsRow] = []
        if let maj = extractMajoritySyncBits {
            rows.append(OperationDiagnosticsRow(id: "majority", title: "Majority vote sync", value: "\(maj) / 32", systemImage: "checkmark.circle"))
        }
        if let w = extractMacroTileWidth {
            rows.append(OperationDiagnosticsRow(id: "tileW", title: "Macro tile width W", value: "\(w)", systemImage: "rectangle.split.3x3"))
        }

        return OperationDiagnosticsSectionModel(id: "decoding", title: "DECODING", rows: rows)
    }
}
