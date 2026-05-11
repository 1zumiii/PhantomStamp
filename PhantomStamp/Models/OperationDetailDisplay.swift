//
//  OperationDetailDisplay.swift
//  PhantomStamp
//
//  Shared presentation model for the unified operation detail screen
//  (in-session extraction rows and persisted `WatermarkHistoryRecord` rows).
//

import UIKit

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
    var syncMatchCount: Int?

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
        syncMatchCount: Int? = nil
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
            syncMatchCount: nil
        )
    }

    init(history record: WatermarkHistoryRecord) {
        let thumb = record.thumbnailData.flatMap { UIImage(data: $0) }
        let detailStatus: DetailStatus = record.status == .success ? .success : .failed
        let kind: OperationKind = record.operationType == .embed ? .embed : .extract
        let titleFormatter = DateFormatter()
        titleFormatter.locale = Locale(identifier: "en_US_POSIX")
        titleFormatter.dateFormat = "MMM d, HH:mm"
        let imageName = "Image · \(titleFormatter.string(from: record.timestamp))"
        self.init(
            imageName: imageName,
            previewImage: thumb,
            operationKind: kind,
            status: detailStatus,
            primaryText: record.payload,
            failureReason: record.errorMessage,
            durationMs: record.processingDurationMs,
            imagePixelWidth: record.imageWidth > 0 ? record.imageWidth : nil,
            imagePixelHeight: record.imageHeight > 0 ? record.imageHeight : nil,
            occurredAt: record.timestamp,
            syncMatchCount: record.syncMatchCount
        )
    }
}
