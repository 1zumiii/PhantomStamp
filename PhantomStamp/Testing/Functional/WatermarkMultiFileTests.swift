//
//  WatermarkMultiFileTests.swift
//  PhantomStamp
//
//  Manual / DEBUG validation:
//  - load bundled TestImg
//  - duplicate it N times (same source image)
//  - sequentially embed watermark into all images (no outer concurrency)
//  - optionally save outputs for inspection
//

import Foundation
import UIKit

enum WatermarkMultiFileTests {
    struct EmbedReport: Sendable {
        var imageLoaded: Bool
        var embedSucceeded: Bool
        var fileCount: Int
        var totalMs: Double
        var outputImages: [UIImage]?
    }

    /// Embeds watermark into multiple images sequentially using the same bundled TestImg.
    static func runMultiFileEmbedOnBundledTestImg(
        text: String = "BatchWatermarkOK",
        fileCount: Int = 5
    ) async -> EmbedReport {
        guard let img = ImagePipelineTests.loadBundledTestUIImage() else {
            return EmbedReport(imageLoaded: false, embedSucceeded: false, fileCount: fileCount, totalMs: 0, outputImages: nil)
        }

        let n = max(1, fileCount)
        let inputs = Array(repeating: img, count: n)
        let service = WatermarkService()

        let t0 = CFAbsoluteTimeGetCurrent()
        do {
            let outputs = try await service.embedWatermark(into: inputs, text: text)
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
            let ok = (outputs.count == n)
            return EmbedReport(imageLoaded: true, embedSucceeded: ok, fileCount: n, totalMs: ms, outputImages: outputs)
        } catch {
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
            return EmbedReport(imageLoaded: true, embedSucceeded: false, fileCount: n, totalMs: ms, outputImages: nil)
        }
    }
}

