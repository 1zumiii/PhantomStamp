//
//  RandomScribbleUtils.swift
//  PhantomStamp
//
//  Local-damage image generator for robustness testing.
//

import UIKit

enum RandomScribbleUtils {
    /// Draws a few short, high-contrast curves without changing the source pixel dimensions.
    static func applyingRandomScribbles(
        to image: UIImage,
        strokeCount: Int,
        widthPercent: Double
    ) -> UIImage? {
        let pixelWidth = Int((image.size.width * image.scale).rounded())
        let pixelHeight = Int((image.size.height * image.scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let canvasSize = CGSize(width: pixelWidth, height: pixelHeight)
        let shortEdge = CGFloat(min(pixelWidth, pixelHeight))
        let count = min(max(strokeCount, 1), 8)
        let clampedWidthPercent = min(max(widthPercent, 0.15), 2.0)
        let coreWidth = max(2, shortEdge * CGFloat(clampedWidthPercent / 100))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { rendererContext in
            image.draw(in: CGRect(origin: .zero, size: canvasSize))

            let context = rendererContext.cgContext
            context.setLineCap(.round)
            context.setLineJoin(.round)

            for _ in 0..<count {
                let path = randomShortCurve(canvasSize: canvasSize, lineWidth: coreWidth)
                let darkCore = Bool.random()

                context.addPath(path.cgPath)
                context.setStrokeColor((darkCore ? UIColor.white : UIColor.black).cgColor)
                context.setLineWidth(coreWidth * 1.75)
                context.strokePath()

                context.addPath(path.cgPath)
                context.setStrokeColor((darkCore ? UIColor.black : UIColor.white).cgColor)
                context.setLineWidth(coreWidth)
                context.strokePath()
            }
        }
    }

    private static func randomShortCurve(
        canvasSize: CGSize,
        lineWidth: CGFloat
    ) -> UIBezierPath {
        let inset = max(lineWidth * 2, 2)
        let usableWidth = max(canvasSize.width - inset * 2, 1)
        let usableHeight = max(canvasSize.height - inset * 2, 1)
        let shortEdge = min(canvasSize.width, canvasSize.height)

        let start = CGPoint(
            x: inset + CGFloat.random(in: 0...1) * usableWidth,
            y: inset + CGFloat.random(in: 0...1) * usableHeight
        )
        let length = shortEdge * CGFloat.random(in: 0.08...0.18)
        let angle = CGFloat.random(in: 0...(2 * .pi))
        let end = clampedPoint(
            CGPoint(
                x: start.x + cos(angle) * length,
                y: start.y + sin(angle) * length
            ),
            canvasSize: canvasSize,
            inset: inset
        )

        let normalAngle = angle + .pi / 2
        let bend = length * CGFloat.random(in: -0.35...0.35)
        let midpoint = CGPoint(
            x: (start.x + end.x) / 2,
            y: (start.y + end.y) / 2
        )
        let control = clampedPoint(
            CGPoint(
                x: midpoint.x + cos(normalAngle) * bend,
                y: midpoint.y + sin(normalAngle) * bend
            ),
            canvasSize: canvasSize,
            inset: inset
        )

        let path = UIBezierPath()
        path.move(to: start)
        path.addQuadCurve(to: end, controlPoint: control)
        return path
    }

    private static func clampedPoint(
        _ point: CGPoint,
        canvasSize: CGSize,
        inset: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: min(max(point.x, inset), max(inset, canvasSize.width - inset)),
            y: min(max(point.y, inset), max(inset, canvasSize.height - inset))
        )
    }
}
