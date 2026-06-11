//
//  AdvancedModeLoupeViewport.swift
//  PhantomStamp
//

import SwiftUI
import UIKit

/// Floating magnifier: zoomed preview crop + smooth-block mask from the variance cache.
/// Heavy crop/mask work runs off the main thread and is keyed so scroll does not re-render each frame.
struct AdvancedModeLoupeViewport: View {
    let image: UIImage
    let cache: MacroblockVarianceCache
    let reticleBlockX: Int
    let reticleBlockY: Int
    let varianceThreshold: Float
    let gridSpan: Int
    let loupeSize: CGFloat
    let displayScale: CGFloat

    @State private var displayModel: LoupeDisplayBuilder.Model?

    private var cacheKey: LoupeDisplayBuilder.Key {
        LoupeDisplayBuilder.key(
            image: image,
            cache: cache,
            reticleBlockX: reticleBlockX,
            reticleBlockY: reticleBlockY,
            varianceThreshold: varianceThreshold,
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
            let built = await Task.detached(priority: .utility) {
                LoupeDisplayBuilder.build(
                    image: image,
                    cache: cache,
                    reticleBlockX: key.reticleBlockX,
                    reticleBlockY: key.reticleBlockY,
                    varianceThreshold: Float(bitPattern: key.varianceThresholdBits),
                    gridSpan: key.gridSpan,
                    loupeSize: loupeSize,
                    displayScale: displayScale
                )
            }.value
            displayModel = built
        }
    }
}
