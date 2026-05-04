//
//  WatermarkServiceProtocol.swift
//  PhantomStamp
//
//  UI 与算法共同遵守的契约：`async throws` 便于处理耗时与失败场景。
//
import Foundation
import UIKit

protocol WatermarkServiceProtocol {
    /// 将文本水印嵌入位图；耗时操作须在后台友好实现（必要时内部切换线程）。
    func embedWatermark(into image: UIImage, text: String) async throws -> UIImage

    /// 从位图中提取水印文本。
    func extractWatermark(from image: UIImage) async throws -> String
}

enum WatermarkError: Error {
    case imageTooSmall
    case extractFailed
    case processingError
}

extension WatermarkError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .imageTooSmall:
            return "图片尺寸过小，无法满足水印处理的最小要求。"
        case .extractFailed:
            return "未能从当前图片中提取水印（算法未完成或图片不含有效水印）。"
        case .processingError:
            return "水印处理过程中发生错误。"
        }
    }
}
