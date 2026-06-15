//
//  ImageRotationUtils.swift
//  PhantomStamp
//
//  Center rotation into an expanded canvas so no source pixels are cropped.
//

import UIKit

nonisolated enum ImageRotationPadding: String, CaseIterable, Identifiable, Sendable {
    case black = "Black"
    case white = "White"

    var id: Self { self }

    var color: UIColor {
        switch self {
        case .black: return .black
        case .white: return .white
        }
    }
}

nonisolated enum ImageRotationUtils {
    static func previewOutputSize(
        sourceWidth: Int,
        sourceHeight: Int,
        degrees: Double
    ) -> (width: Int, height: Int)? {
        guard sourceWidth > 0, sourceHeight > 0, degrees.isFinite else { return nil }

        let radians = degrees * .pi / 180
        let rawCosine = abs(cos(radians))
        let rawSine = abs(sin(radians))
        let cosine = rawCosine < 1e-12 ? 0 : rawCosine
        let sine = rawSine < 1e-12 ? 0 : rawSine
        let width = Int(ceil(Double(sourceWidth) * cosine + Double(sourceHeight) * sine))
        let height = Int(ceil(Double(sourceWidth) * sine + Double(sourceHeight) * cosine))
        return (max(1, width), max(1, height))
    }

    static func rotateExpandingCanvas(
        image: UIImage,
        degrees: Double,
        padding: ImageRotationPadding
    ) -> UIImage? {
        let sourceWidth = Int((image.size.width * image.scale).rounded())
        let sourceHeight = Int((image.size.height * image.scale).rounded())
        guard let output = previewOutputSize(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            degrees: degrees
        ) else { return nil }

        let outputSize = CGSize(width: output.width, height: output.height)
        let sourceSize = CGSize(width: sourceWidth, height: sourceHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: outputSize, format: format).image { context in
            let cg = context.cgContext
            cg.setFillColor(padding.color.cgColor)
            cg.fill(CGRect(origin: .zero, size: outputSize))
            cg.translateBy(x: outputSize.width * 0.5, y: outputSize.height * 0.5)
            cg.rotate(by: CGFloat(degrees * .pi / 180))
            image.draw(
                in: CGRect(
                    x: -sourceSize.width * 0.5,
                    y: -sourceSize.height * 0.5,
                    width: sourceSize.width,
                    height: sourceSize.height
                )
            )
        }
    }
}
