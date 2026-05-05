//
//  PreviewWatermarkService.swift
//  PhantomStamp
//
//  仅用于 SwiftUI Preview（主 App 目标编译）
//

import UIKit

final class PreviewWatermarkService: WatermarkServiceProtocol {
    func embedWatermark(into image: UIImage, text: String) async throws -> UIImage {
        try await Task.sleep(nanoseconds: AppConstants.Watermark.mockEmbedDelayNanoseconds)
        // Perform Testing only in Preview mode
        print(AppConstants.Debug.launchLogPrefix + AppVersion.marketing)
        ImagePipelineTests.runAllBundledAndPrint()
        MatrixOperationsTests.runAllAndPrint()
        return image
    }

    func extractWatermark(from image: UIImage) async throws -> String {
        try await Task.sleep(nanoseconds: AppConstants.Watermark.mockExtractDelayNanoseconds)
        _ = image
        return AppConstants.Watermark.mockExtractResultText
    }
}
