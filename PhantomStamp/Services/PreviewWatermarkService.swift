//
//  PreviewWatermarkService.swift
//  PhantomStamp
//
//  仅用于 SwiftUI Preview（主 App 目标编译）
//

import UIKit

final class PreviewWatermarkService: WatermarkServiceProtocol {
    func embedWatermark(into image: UIImage, text: String) async throws -> UIImage {
        // Perform Testing only in Preview mode
        print(AppConstants.Debug.launchLogPrefix + AppVersion.marketing)
        do {
            let t0 = CFAbsoluteTimeGetCurrent()
            // this step is time consuming
            ImagePipelineTests.runAllBundledAndPrint()
            let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            print("[Timing] ImagePipelineTests.runAllBundledAndPrint took \(String(format: "%.2f", dtMs)) ms")
        }

        do {
            let t0 = CFAbsoluteTimeGetCurrent()
            MatrixOperationsTests.runAllAndPrint()
            let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            print("[Timing] MatrixOperationsTests.runAllAndPrint took \(String(format: "%.2f", dtMs)) ms")
        }
        try await Task.sleep(nanoseconds: AppConstants.Watermark.mockEmbedDelayNanoseconds)
        return image
    }

    func extractWatermark(from image: UIImage) async throws -> String {
        try await Task.sleep(nanoseconds: AppConstants.Watermark.mockExtractDelayNanoseconds)
        _ = image
        return AppConstants.Watermark.mockExtractResultText
    }
}
