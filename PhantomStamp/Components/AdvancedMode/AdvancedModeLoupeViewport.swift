//
//  AdvancedModeLoupeViewport.swift
//  PhantomStamp
//

import SwiftUI
import UIKit

/// Floating magnifier: zoomed preview crop + overlay (smooth mask or amplitude heatmap).
struct AdvancedModeLoupeViewport: View {
    let image: UIImage
    let varianceCache: MacroblockVarianceCache
    let baseQCache: MacroblockBaseQuantizationCache?
    let visualization: AdvancedCanvasVisualization
    let reticleBlockX: Int
    let reticleBlockY: Int
    let gridSpan: Int
    let loupeSize: CGFloat
    let displayScale: CGFloat

    @State private var displayModel: LoupeDisplayBuilder.Model?

    private var overlayMode: LoupeDisplayBuilder.LoupeOverlayMode {
        switch visualization {
        case .smoothBlock(let varianceThreshold):
            return .smoothMask(varianceThresholdBits: varianceThreshold.bitPattern)
        case .varianceGain(let curve):
            return .gainHeatmap(curveKey: curve.packedKey)
        case .embedIntensity(let curve, let embeddingIntensity):
            return .amplitudeHeatmap(
                curveKey: curve.packedKey,
                embeddingIntensityBits: embeddingIntensity.bitPattern
            )
        }
    }

    private var cacheKey: LoupeDisplayBuilder.Key {
        LoupeDisplayBuilder.key(
            mode: overlayMode,
            image: image,
            cache: varianceCache,
            reticleBlockX: reticleBlockX,
            reticleBlockY: reticleBlockY,
            gridSpan: gridSpan,
            loupeSize: loupeSize,
            displayScale: displayScale
        )
    }

    var body: some View {
        ZStack {
            if let displayModel {
                Image(uiImage: displayModel.croppedImage)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: loupeSize, height: loupeSize)

                Image(uiImage: displayModel.maskOverlayImage)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: loupeSize, height: loupeSize)
            }
        }
        .frame(width: loupeSize, height: loupeSize)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.black.opacity(0.35), lineWidth: 1.5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.55), lineWidth: 0.75)
                .padding(0.75)
        }
        .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 3)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: cacheKey) {
            let key = cacheKey
            let mode = overlayMode
            let built = await Task.detached(priority: .utility) {
                LoupeDisplayBuilder.build(
                    mode: mode,
                    image: image,
                    varianceCache: varianceCache,
                    baseQCache: baseQCache,
                    reticleBlockX: key.reticleBlockX,
                    reticleBlockY: key.reticleBlockY,
                    gridSpan: key.gridSpan,
                    loupeSize: loupeSize,
                    displayScale: displayScale
                )
            }.value
            displayModel = built
        }
    }
}
