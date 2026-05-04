//
//  WatermarkService.swift
//  PhantomStamp
//
//  算法组实现：`YCbCr` / `DCT` / `TaskGroup` 等应在此替换当前占位逻辑。
//

import UIKit

final class WatermarkService: WatermarkServiceProtocol {
    func embedWatermark(into image: UIImage, text: String) async throws -> UIImage {
        let minSide = min(image.size.width, image.size.height)
        guard minSide >= AppConstants.Watermark.minimumImageSidePoints else {
            throw WatermarkError.imageTooSmall
        }

        try await Task.sleep(nanoseconds: AppConstants.Watermark.realEmbedDelayNanoseconds)

        // TODO: 1. 转 YCbCr  2. TaskGroup 切片并发  3. DCT / 嵌入比特
        _ = text

        return image
    }

    func extractWatermark(from image: UIImage) async throws -> String {
        let minSide = min(image.size.width, image.size.height)
        guard minSide >= AppConstants.Watermark.minimumImageSidePoints else {
            throw WatermarkError.imageTooSmall
        }

        try await Task.sleep(nanoseconds: AppConstants.Watermark.realExtractDelayNanoseconds)

        // TODO: 算法组 — 提取流水线；完成前故意失败以便验证错误 UI（提交前改为 return 提取结果）
        throw WatermarkError.extractFailed
    }
}
