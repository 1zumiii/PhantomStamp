//
//  WatermarkExtractViewModel.swift
//  PhantomStamp
//

import Observation
import UIKit

@MainActor
@Observable
final class WatermarkExtractViewModel {
    private static let retainedPreviewMaxPixelEdge: CGFloat = 1_200
    private let watermarkService: any WatermarkServiceProtocol

    init(watermarkService: any WatermarkServiceProtocol) {
        self.watermarkService = watermarkService
    }

    var isExtracting: Bool = false
    /// Non-extract failures (e.g. picker load failures).
    var errorMessage: String?

    /// Results shown on this screen only.
    var records: [ExtractionRecord] = []

    var canExtract: Bool {
        records.contains(where: { $0.status == .pending }) && !isExtracting
    }

    func clearPageResults() {
        records.removeAll()
        errorMessage = nil
    }

    func appendPickedPhotoItems(_ items: [SelectedPhotoItem]) {
        guard !items.isEmpty else { return }

        let start = records.count
        let adjusted: [SelectedPhotoItem] = items.enumerated().map { offset, item in
            guard item.displayName == SelectedPhotoItem.missingFileNamePlaceholder else { return item }
            let n = start + offset + 1
            return SelectedPhotoItem(
                id: item.id,
                image: item.image,
                width: item.width,
                height: item.height,
                suggestedName: "Image \(n)"
            )
        }

        let newRecords = adjusted.map {
            ExtractionRecord(
                imageName: $0.displayName,
                image: $0.image,
                imagePixelWidth: $0.width,
                imagePixelHeight: $0.height,
                status: .pending
            )
        }
        records.insert(contentsOf: newRecords, at: 0)
    }

    func extractWatermarks() async {
        guard canExtract else { return }

        let pendingIndexes = records.indices.filter { records[$0].status == .pending }
        guard !pendingIndexes.isEmpty else { return }

        isExtracting = true
        defer { isExtracting = false }

        errorMessage = nil

        var indexImagePairs: [(index: Int, image: UIImage)] = []
        for index in pendingIndexes {
            guard let image = records[index].image else {
                records[index].status = .failed
                records[index].message = nil
                records[index].confidence = nil
                records[index].failureReason = "No image data is available for extraction."
                records[index].diagnostics = nil
                continue
            }
            indexImagePairs.append((index, image))
        }

        guard !indexImagePairs.isEmpty else { return }

        if indexImagePairs.count == 1 {
            let index = indexImagePairs[0].index
            let image = indexImagePairs[0].image
            let t0 = CFAbsoluteTimeGetCurrent()
            do {
                let extractedText: String
                if let svc = watermarkService as? WatermarkService {
                    let result = try await svc.extractWatermarkWithDiagnostics(
                        from: image,
                        sourceImageName: records[index].imageName
                    )
                    extractedText = result.text
                    records[index].diagnostics = result.diagnostics
                    records[index].durationMs = result.diagnostics.durationMs
                } else {
                    extractedText = try await watermarkService.extractWatermark(from: image)
                    records[index].durationMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                }
                records[index].status = .extracted
                records[index].message = extractedText
                records[index].confidence = nil
                records[index].failureReason = nil
            } catch {
                records[index].status = .failed
                records[index].message = nil
                records[index].confidence = nil
                records[index].failureReason = error.localizedDescription
                records[index].durationMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                records[index].diagnostics = nil
            }
            compactRecordImage(at: index)
            return
        }

        var images = indexImagePairs.map(\.image)
        let names = indexImagePairs.map { records[$0.index].imageName }
        let recordIndexes = indexImagePairs.map(\.index)
        let detailedResults: [WatermarkExtractionResult?]?
        let fallbackResults: [String?]?
        if let svc = watermarkService as? WatermarkService {
            detailedResults = await svc.extractWatermarkBestEffortWithDiagnostics(
                from: images,
                sourceImageNames: names
            )
            fallbackResults = nil
        } else {
            detailedResults = nil
            fallbackResults = await watermarkService.extractWatermarkBestEffort(from: images)
        }

        // The page records are the last owners of the original 4K images after these temporary
        // batch arrays are cleared. Replace each processed source with a bounded preview below.
        images.removeAll(keepingCapacity: false)
        indexImagePairs.removeAll(keepingCapacity: false)

        for pairIndex in recordIndexes.indices {
            let recordIndex = recordIndexes[pairIndex]
            let detailed = detailedResults?[pairIndex]
            let extractedText = detailed?.text ?? fallbackResults?[pairIndex]
            if let extractedText {
                records[recordIndex].status = .extracted
                records[recordIndex].message = extractedText
                records[recordIndex].confidence = nil
                records[recordIndex].failureReason = nil
                records[recordIndex].durationMs = detailed?.diagnostics.durationMs
                records[recordIndex].diagnostics = detailed?.diagnostics
            } else {
                records[recordIndex].status = .failed
                records[recordIndex].message = nil
                records[recordIndex].confidence = nil
                records[recordIndex].failureReason = "Failed to extract watermark from this image."
                records[recordIndex].durationMs = nil
                records[recordIndex].diagnostics = nil
            }
            compactRecordImage(at: recordIndex)
        }
    }

    private func compactRecordImage(at index: Int) {
        guard records.indices.contains(index), let source = records[index].image else { return }

        let pixelWidth = Int((source.size.width * source.scale).rounded())
        let pixelHeight = Int((source.size.height * source.scale).rounded())
        records[index].imagePixelWidth = records[index].imagePixelWidth ?? pixelWidth
        records[index].imagePixelHeight = records[index].imagePixelHeight ?? pixelHeight

        let longestEdge = max(pixelWidth, pixelHeight)
        guard longestEdge > Int(Self.retainedPreviewMaxPixelEdge) else { return }

        records[index].image = autoreleasepool {
            let scale = Self.retainedPreviewMaxPixelEdge / CGFloat(longestEdge)
            let target = CGSize(
                width: max(1, floor(CGFloat(pixelWidth) * scale)),
                height: max(1, floor(CGFloat(pixelHeight) * scale))
            )
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            return UIGraphicsImageRenderer(size: target, format: format).image { _ in
                source.draw(in: CGRect(origin: .zero, size: target))
            }
        }
    }
}
