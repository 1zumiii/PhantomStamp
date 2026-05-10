//
//  WatermarkExtractViewModel.swift
//  PhantomStamp
//

import Foundation
import SwiftUI
import UIKit

enum ExtractionDetectionMode: String, CaseIterable, Identifiable {
    case fast = "Fast scan"
    case robust = "Robust scan"

    var id: String { rawValue }
}

@MainActor
@Observable
final class WatermarkExtractViewModel {
    private let watermarkService: any WatermarkServiceProtocol
    init(watermarkService: any WatermarkServiceProtocol) {
        self.watermarkService = watermarkService
    }
    var detectionMode: ExtractionDetectionMode = .fast
    var selectedImage: UIImage?
    var selectedImageName: String = "Selected image"
    var isExtracting: Bool = false
    var errorMessage: String?

    // Demo records for the extract page and detail page.
    // Later this can be replaced with real extraction results.
    var records: [ExtractionRecord] = []

    var latestSuccessfulRecord: ExtractionRecord? {
        records.first(where: { $0.status == .extracted })
    }

    var canExtract: Bool {
        records.contains(where: { $0.status == .pending }) && !isExtracting
    }
    
    func selectImage(_ image: UIImage, name: String = "Selected image") {
        selectedImage = image
        selectedImageName = name

        let pendingRecord = ExtractionRecord(
            imageName: name,
            image: image,
            status: .pending
        )

        records.insert(pendingRecord, at: 0)
    }

    func extractWatermarks() async {
        guard !isExtracting else { return }

        let pendingIndexes = records.indices.filter {
            records[$0].status == .pending
        }

        guard !pendingIndexes.isEmpty else { return }

        isExtracting = true
        errorMessage = nil

        for index in pendingIndexes {
            guard let image = records[index].image else {
                records[index].status = .failed
                records[index].message = nil
                records[index].confidence = nil
                records[index].failureReason = "No image data is available for extraction."
                continue
            }

            do {
                let service = watermarkService

                let extractedText = try await Task.detached(priority: .userInitiated) {
                    try await service.extractWatermark(from: image)
                }.value

                records[index].status = .extracted
                records[index].message = extractedText
                records[index].confidence = nil
                records[index].failureReason = nil
            } catch {
                records[index].status = .failed
                records[index].message = nil
                records[index].confidence = nil
                records[index].failureReason = error.localizedDescription
            }        }

        isExtracting = false
    }

    func resetCurrentSelection() {
        selectedImage = nil
        selectedImageName = "Selected image"
        errorMessage = nil
    }

    func retryExtraction(for record: ExtractionRecord) async {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }

        records[index].status = .pending
        records[index].message = nil
        records[index].confidence = nil
        records[index].failureReason = nil

        isExtracting = true
        try? await Task.sleep(nanoseconds: 700_000_000)

        records[index].status = .extracted
        records[index].message = "Hello PhantomStamp"
        records[index].confidence = 0.92
        records[index].failureReason = nil

        isExtracting = false
    }
    
    func selectImages(_ images: [(image: UIImage, name: String)]) {
        let newRecords = images.enumerated().map { index, item in
            ExtractionRecord(
                imageName: item.name.isEmpty ? "Uploaded image \(index + 1)" : item.name,
                image: item.image,
                status: .pending
            )
        }

        records.insert(contentsOf: newRecords, at: 0)
    }
}
