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

            let centerX = ReticleBlockGeometry.blockCenterPosition(
                index: blockX,
                blockCount: maxBlocksX,
                trackLength: size.width
            )
            let centerY = ReticleBlockGeometry.blockCenterPosition(
                index: blockY,
                blockCount: maxBlocksY,
                trackLength: size.height
            )
            let blockW = size.width / CGFloat(maxBlocksX)
            let blockH = size.height / CGFloat(maxBlocksY)

            var horizontal = Path()
            horizontal.move(to: CGPoint(x: 0, y: centerY))
            horizontal.addLine(to: CGPoint(x: size.width, y: centerY))

            var vertical = Path()
            vertical.move(to: CGPoint(x: centerX, y: 0))
            vertical.addLine(to: CGPoint(x: centerX, y: size.height))

            // Dark outline for contrast on bright regions (e.g. sky).
            context.stroke(horizontal, with: .color(.black.opacity(0.72)), lineWidth: 2.25)
            context.stroke(vertical, with: .color(.black.opacity(0.72)), lineWidth: 2.25)
            context.stroke(horizontal, with: .color(.orange.opacity(0.95)), lineWidth: 1.1)
            context.stroke(vertical, with: .color(.orange.opacity(0.95)), lineWidth: 1.1)

            let frame = CGRect(
                x: centerX - blockW * 0.5,
                y: centerY - blockH * 0.5,
                width: blockW,
                height: blockH
            )
            context.stroke(
                Path(frame),
                with: .color(.yellow.opacity(0.98)),
                style: StrokeStyle(lineWidth: 1.75)
            )
            context.stroke(
                Path(frame.insetBy(dx: 0.75, dy: 0.75)),
                with: .color(.black.opacity(0.5)),
                style: StrokeStyle(lineWidth: 0.75)
            )
        }
        .allowsHitTesting(false)
    }
}
