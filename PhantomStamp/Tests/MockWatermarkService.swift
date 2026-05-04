//
//  MockWatermarkService.swift
//  PhantomStamp
//
//  UI 侧 Mock：不依赖真实算法，用于调试 Loading / 成功 / 失败流程。
//

import UIKit

final class MockWatermarkService: WatermarkServiceProtocol {
    func embedWatermark(into image: UIImage, text: String) async throws -> UIImage {
        try await Task.sleep(nanoseconds: AppConstants.Watermark.mockEmbedDelayNanoseconds)
        return image
    }

    func extractWatermark(from image: UIImage) async throws -> String {
        try await Task.sleep(nanoseconds: AppConstants.Watermark.mockExtractDelayNanoseconds)
        return AppConstants.Watermark.mockExtractResultText
    }
}
