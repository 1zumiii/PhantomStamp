//
//  AdvancedModeCanvasView.swift
//  PhantomStamp
//
//  Grid-wrapped canvas with custom reticle axis sliders, crosshair, and dodging loupe.
//

import SwiftUI
import UIKit

struct AdvancedModeCanvasView: View {
    @Environment(\.displayScale) private var displayScale
    @Bindable var viewModel: AdvancedModeCanvasViewModel
    let item: SelectedPhotoItem
    let visualization: AdvancedCanvasVisualization
    let watermarkService: any WatermarkServiceProtocol
    var isInteractionEnabled: Bool = true
    var onRemovePhoto: () -> Void

    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    /// Reserve slider gutters from source image dimensions so grid layout stays stable
    /// before/after the variance cache loads (prevents width oscillation rebuild loops).
    private var layoutShowsX: Bool { item.width / DCTMatrix8x8.side > 1 }
    private var layoutShowsY: Bool { item.height / DCTMatrix8x8.side > 1 }

    var body: some View {
        let sliderEnabled = viewModel.isCacheReady && isInteractionEnabled

        Grid(
            horizontalSpacing: AdvancedModeCanvasViewModel.gridSpacing,
            verticalSpacing: AdvancedModeCanvasViewModel.gridSpacing
        ) {
            GridRow(alignment: .top) {
                imageCanvas
                    .frame(maxWidth: .infinity)
                    .frame(height: AdvancedModeCanvasViewModel.canvasHeight)

                if layoutShowsY {
                    sliderSlot(axis: .vertical, sliderEnabled: sliderEnabled)
                }
            }

            if layoutShowsX {
                GridRow {
                    sliderSlot(axis: .horizontal, sliderEnabled: sliderEnabled)
                        .frame(maxWidth: .infinity)

                    if layoutShowsY {
                        Color.clear
                            .frame(
                                width: AdvancedModeCanvasViewModel.axisSliderThickness,
                                height: AdvancedModeCanvasViewModel.axisSliderThickness
                            )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            viewModel.bindPhoto(item.id)
        }
        .onChange(of: item.id) { _, newID in
            viewModel.bindPhoto(newID)
        }
    }

    @ViewBuilder
    private func sliderSlot(axis: ReticleSliderAxis, sliderEnabled: Bool) -> some View {
        Group {
            if viewModel.isCacheReady {
                switch axis {
                case .horizontal:
                    ReticleAxisSlider(
                        value: reticleXBinding,
                        range: 0...viewModel.xSliderUpperBound,
                        blockCount: viewModel.maxBlocksX,
                        axis: .horizontal,
                        isEnabled: sliderEnabled
                    )
                case .vertical:
                    ReticleAxisSlider(
                        value: reticleYBinding,
                        range: 0...viewModel.ySliderUpperBound,
                        blockCount: viewModel.maxBlocksY,
                        axis: .vertical,
                        isEnabled: sliderEnabled
                    )
                }
            } else {
                // Placeholder keeps grid geometry identical while cache builds.
                Color.clear
            }
        }
        .frame(
            width: axis == .vertical ? AdvancedModeCanvasViewModel.axisSliderThickness : nil,
            height: axis == .horizontal ? AdvancedModeCanvasViewModel.axisSliderThickness : AdvancedModeCanvasViewModel.canvasHeight
        )
    }

    @ViewBuilder
    private var imageCanvas: some View {
        GeometryReader { geo in
            let canvasSize = geo.size
            let dodgeLeading = viewModel.shouldDodgeLoupe(canvasSize: canvasSize)
            let displayImage = viewModel.previewImage ?? item.image

            ZStack {
                CanvasPhotoFill(
                    image: displayImage,
                    width: canvasSize.width,
                    height: canvasSize.height
                )
                .equatable()

                ReticleCrosshairHost(
                    isVisible: viewModel.isCacheReady,
                    blockX: viewModel.reticleBlockX,
                    blockY: viewModel.reticleBlockY,
                    maxBlocksX: viewModel.maxBlocksX,
                    maxBlocksY: viewModel.maxBlocksY
                )
                .equatable()

                CanvasChromeBorder(shape: shape)

                LoupeOverlayHost(
                    isCacheReady: viewModel.isCacheReady,
                    isBuilding: viewModel.isBuildingVarianceCache,
                    preview: viewModel.previewImage,
                    varianceCache: viewModel.varianceCache,
                    baseQCache: viewModel.baseQCache,
                    visualization: visualization,
                    reticleBlockX: viewModel.reticleBlockX,
                    reticleBlockY: viewModel.reticleBlockY,
                    dodgeLeading: dodgeLeading,
                    displayScale: displayScale
                )
                .equatable()

                ReticleMetricBadgeHost(
                    label: viewModel.reticleMetricLabel(for: visualization),
                    isVisible: viewModel.isCacheReady
                )
                .equatable()
            }
            .compositingGroup()
            .clipShape(shape)
            .overlay(alignment: .topTrailing) {
                Button(action: onRemovePhoto) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.45))
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isInteractionEnabled)
                .accessibilityLabel("Remove photo")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: AdvancedModeCanvasViewModel.canvasHeight)
        .onGeometryChange(for: CGSize.self, of: { proxy in
            CGSize(
                width: proxy.size.width.rounded(.toNearestOrAwayFromZero),
                height: proxy.size.height.rounded(.toNearestOrAwayFromZero)
            )
        }, action: { size in
            reportLayout(size)
        })
    }

    private var reticleXBinding: Binding<Double> {
        Binding(
            get: { Double(viewModel.reticleBlockX) },
            set: {
                let upper = viewModel.xSliderUpperBound
                viewModel.reticleBlockX = Int(min(max($0, 0), upper).rounded())
            }
        )
    }

    private var reticleYBinding: Binding<Double> {
        Binding(
            get: { Double(viewModel.reticleBlockY) },
            set: {
                let upper = viewModel.ySliderUpperBound
                viewModel.reticleBlockY = Int(min(max($0, 0), upper).rounded())
            }
        )
    }

    private func reportLayout(_ size: CGSize) {
        guard let service = watermarkService as? WatermarkService else {
            AdvancedCanvasDebug.log("reportLayout aborted — watermarkService is not WatermarkService")
            return
        }
        viewModel.updateLayout(
            containerSize: size,
            displayScale: displayScale,
            item: item,
            service: service
        )
    }
}

// MARK: - Performance-isolated canvas layers

/// Photo fill — `Equatable` so scroll passes skip bitmap re-layout when inputs are stable.
private struct CanvasPhotoFill: View, Equatable {
    let image: UIImage
    let width: CGFloat
    let height: CGFloat
    private let imagePixelWidth: Int
    private let imagePixelHeight: Int

    init(image: UIImage, width: CGFloat, height: CGFloat) {
        self.image = image
        self.width = width
        self.height = height
        imagePixelWidth = Int(image.size.width * image.scale)
        imagePixelHeight = Int(image.size.height * image.scale)
    }

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            .clipped()
    }
}

private struct ReticleCrosshairHost: View, Equatable {
    let isVisible: Bool
    let blockX: Int
    let blockY: Int
    let maxBlocksX: Int
    let maxBlocksY: Int

    private static let canvasClipShape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    var body: some View {
        if isVisible {
            AdvancedReticleCrosshair(
                blockX: blockX,
                blockY: blockY,
                maxBlocksX: maxBlocksX,
                maxBlocksY: maxBlocksY
            )
            .clipShape(Self.canvasClipShape)
        }
    }
}

private struct ReticleMetricBadgeHost: View, Equatable {
    let label: String?
    let isVisible: Bool

    var body: some View {
        if isVisible, let label {
            ReticleMetricBadge(label: label)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }
}

private struct CanvasChromeBorder: View {
    let shape: RoundedRectangle

    var body: some View {
        shape.strokeBorder(
            Color.primary.opacity(0.28),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 7])
        )
        .allowsHitTesting(false)
    }
}

/// Loupe slot — isolates magnifier updates from the main photo layer during scroll.
private struct LoupeOverlayHost: View, Equatable {
    let isCacheReady: Bool
    let isBuilding: Bool
    let preview: UIImage?
    let varianceCache: MacroblockVarianceCache?
    let baseQCache: MacroblockBaseQuantizationCache?
    let visualization: AdvancedCanvasVisualization
    let reticleBlockX: Int
    let reticleBlockY: Int
    let dodgeLeading: Bool
    let displayScale: CGFloat

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isCacheReady == rhs.isCacheReady
            && lhs.isBuilding == rhs.isBuilding
            && lhs.visualization == rhs.visualization
            && lhs.reticleBlockX == rhs.reticleBlockX
            && lhs.reticleBlockY == rhs.reticleBlockY
            && lhs.dodgeLeading == rhs.dodgeLeading
            && lhs.displayScale == rhs.displayScale
            && Self.pairEquals(lhs.previewPixelSignature, rhs.previewPixelSignature)
            && Self.pairEquals(lhs.cacheSignature, rhs.cacheSignature)
            && lhs.baseQReady == rhs.baseQReady
    }

    private var baseQReady: Bool { baseQCache != nil }

    private var previewPixelSignature: (Int, Int)? {
        preview.map { (Int($0.size.width * $0.scale), Int($0.size.height * $0.scale)) }
    }

    private var cacheSignature: (Int, Int)? {
        varianceCache.map { ($0.maxBlocksX, $0.maxBlocksY) }
    }

    private static func pairEquals(_ lhs: (Int, Int)?, _ rhs: (Int, Int)?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (left?, right?): left == right
        default: false
        }
    }

    var body: some View {
        Group {
            if isCacheReady, let preview, let varianceCache {
                AdvancedModeLoupeViewport(
                    image: preview,
                    varianceCache: varianceCache,
                    baseQCache: baseQCache,
                    visualization: visualization,
                    reticleBlockX: reticleBlockX,
                    reticleBlockY: reticleBlockY,
                    gridSpan: AdvancedModeCanvasViewModel.loupeGridSpan,
                    loupeSize: AdvancedModeCanvasViewModel.loupeSize,
                    displayScale: displayScale
                )
                .padding(AdvancedModeCanvasViewModel.loupeCanvasPadding)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: dodgeLeading ? .bottomLeading : .bottomTrailing
                )
            } else if isBuilding {
                ProgressView()
                    .controlSize(.small)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(AdvancedModeCanvasViewModel.loupeCanvasPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
