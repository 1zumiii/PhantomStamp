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
    let varianceThreshold: Float
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
            let dodgeLeading = viewModel.shouldDodgeLoupe(canvasSize: geo.size)
            let displayImage = viewModel.previewImage ?? item.image

            Image(uiImage: displayImage)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .clipShape(shape)
                .overlay {
                    if viewModel.isCacheReady {
                        AdvancedReticleCrosshair(
                            blockX: viewModel.reticleBlockX,
                            blockY: viewModel.reticleBlockY,
                            maxBlocksX: viewModel.maxBlocksX,
                            maxBlocksY: viewModel.maxBlocksY
                        )
                        .clipShape(shape)
                    }
                }
                .overlay {
                    shape.strokeBorder(
                        Color.primary.opacity(0.28),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 7])
                    )
                }
                .overlay {
                    loupeOverlay
                        .padding(AdvancedModeCanvasViewModel.loupeCanvasPadding)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: dodgeLeading ? .bottomLeading : .bottomTrailing
                        )
                        .animation(.easeInOut(duration: 0.22), value: dodgeLeading)
                }
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

    @ViewBuilder
    private var loupeOverlay: some View {
        if viewModel.isCacheReady,
           let cache = viewModel.varianceCache,
           let preview = viewModel.previewImage {
            AdvancedModeLoupeViewport(
                image: preview,
                cache: cache,
                reticleBlockX: viewModel.reticleBlockX,
                reticleBlockY: viewModel.reticleBlockY,
                varianceThreshold: varianceThreshold,
                gridSpan: AdvancedModeCanvasViewModel.loupeGridSpan,
                loupeSize: AdvancedModeCanvasViewModel.loupeSize
            )
        } else if viewModel.isBuildingVarianceCache {
            ProgressView()
                .controlSize(.small)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
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
