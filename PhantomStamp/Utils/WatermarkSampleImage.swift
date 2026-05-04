//
//  WatermarkSampleImage.swift
//  PhantomStamp
//

import UIKit

enum WatermarkSampleImage {
    static func make() -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 140, weight: .medium)
        let base = UIImage(systemName: AppConstants.Watermark.sampleSystemSymbolName, withConfiguration: config)!
        let renderer = UIGraphicsImageRenderer(size: base.size)
        return renderer.image { _ in
            UIColor.secondarySystemBackground.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: base.size)).fill()
            base.withTintColor(.label, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(origin: .zero, size: base.size))
        }
    }
}
