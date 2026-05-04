//
//  WatermarkSampleImage.swift
//  PhantomStamp
//

import UIKit

enum WatermarkSampleImage {
    /// 固定大于 `AppConstants.Watermark.minimumImageSidePoints`，避免示例图触发尺寸校验失败。
    private static let canvasSize = CGSize(width: 256, height: 256)

    static func make() -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 120, weight: .medium)
        let base = UIImage(systemName: AppConstants.Watermark.sampleSystemSymbolName, withConfiguration: config)!
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { _ in
            UIColor.secondarySystemBackground.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: canvasSize)).fill()
            let drawRect = CGRect(
                x: (canvasSize.width - base.size.width) / 2,
                y: (canvasSize.height - base.size.height) / 2,
                width: base.size.width,
                height: base.size.height
            )
            base.withTintColor(.label, renderingMode: .alwaysOriginal)
                .draw(in: drawRect)
        }
    }
}
