//
//  AdvancedReticleCrosshair.swift
//  PhantomStamp
//

import SwiftUI

/// Full-span crosshair aligned to the active 8×8 macroblock; hollow frame marks the target block.
struct AdvancedReticleCrosshair: View {
    let blockX: Int
    let blockY: Int
    let maxBlocksX: Int
    let maxBlocksY: Int

    var body: some View {
        Canvas { context, size in
            guard maxBlocksX > 0, maxBlocksY > 0 else { return }

            let centerX = blockCenterCoordinate(index: blockX, blockCount: maxBlocksX, canvasLength: size.width)
            let centerY = blockCenterCoordinate(index: blockY, blockCount: maxBlocksY, canvasLength: size.height)
            let blockW = size.width / CGFloat(maxBlocksX)
            let blockH = size.height / CGFloat(maxBlocksY)

            var horizontal = Path()
            horizontal.move(to: CGPoint(x: 0, y: centerY))
            horizontal.addLine(to: CGPoint(x: size.width, y: centerY))

            var vertical = Path()
            vertical.move(to: CGPoint(x: centerX, y: 0))
            vertical.addLine(to: CGPoint(x: centerX, y: size.height))

            context.stroke(horizontal, with: .color(.black.opacity(0.45)), lineWidth: 1.25)
            context.stroke(vertical, with: .color(.black.opacity(0.45)), lineWidth: 1.25)
            context.stroke(horizontal, with: .color(.white.opacity(0.88)), lineWidth: 0.75)
            context.stroke(vertical, with: .color(.white.opacity(0.88)), lineWidth: 0.75)

            let frame = CGRect(
                x: centerX - blockW * 0.5,
                y: centerY - blockH * 0.5,
                width: blockW,
                height: blockH
            )
            context.stroke(
                Path(frame),
                with: .color(.yellow.opacity(0.95)),
                style: StrokeStyle(lineWidth: 1.5)
            )
            context.stroke(
                Path(frame.insetBy(dx: 0.75, dy: 0.75)),
                with: .color(.black.opacity(0.35)),
                style: StrokeStyle(lineWidth: 0.5)
            )
        }
        .allowsHitTesting(false)
    }

    private func blockCenterCoordinate(index: Int, blockCount: Int, canvasLength: CGFloat) -> CGFloat {
        guard blockCount > 1 else { return canvasLength * 0.5 }
        let normalized = (CGFloat(index) + 0.5) / CGFloat(blockCount)
        return normalized * canvasLength
    }
}
