//
//  WatermarkExtractViewModel.swift
//  PhantomStamp
//

import Observation
import UIKit

@MainActor
@Observable
final class WatermarkExtractViewModel {
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
                    extractedText = try await svc.extractWatermark(from: image, sourceImageName: records[index].imageName)
                } else {
                    extractedText = try await watermarkService.extractWatermark(from: image)
                }
                records[index].status = .extracted
                records[index].message = extractedText
                records[index].confidence = nil
                records[index].failureReason = nil
                records[index].durationMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            } catch {
                records[index].status = .failed
                records[index].message = nil
                records[index].confidence = nil
                records[index].failureReason = error.localizedDescription
                records[index].durationMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            }
            return
        }

        let images = indexImagePairs.map(\.image)
        let names = indexImagePairs.map { records[$0.index].imageName }
        let results: [String?]
        if let svc = watermarkService as? WatermarkService {
            results = await svc.extractWatermarkBestEffort(from: images, sourceImageNames: names)
        } else {
            results = await watermarkService.extractWatermarkBestEffort(from: images)
        }

        for pairIndex in results.indices {
            let recordIndex = indexImagePairs[pairIndex].index
            if let extractedText = results[pairIndex] {
                records[recordIndex].status = .extracted
                records[recordIndex].message = extractedText
                records[recordIndex].confidence = nil
                records[recordIndex].failureReason = nil
                records[recordIndex].durationMs = nil
            } else {
                records[recordIndex].status = .failed
                records[recordIndex].message = nil
                records[recordIndex].confidence = nil
                records[recordIndex].failureReason = "Failed to extract watermark from this image."
                records[recordIndex].durationMs = nil
            }
        }
    }
}

