//
//  AdvancedModeCanvasView.swift
//  PhantomStamp
//
//  Grid-wrapped canvas with custom reticle axis sliders, crosshair, and dodging loupe.
//

import SwiftUI
import UIKit

struct AdvancedModeCanvasView: View {
    @Bindable var viewModel: AdvancedModeCanvasViewModel
    let item: SelectedPhotoItem
    let varianceThreshold: Float
    let watermarkService: any WatermarkServiceProtocol
    var isInteractionEnabled: Bool = true
    var onRemovePhoto: () -> Void

    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    var body: some View {
        let maxBlocksX = viewModel.maxBlocksX(fallbackImageWidth: item.width)
        let maxBlocksY = viewModel.maxBlocksY(fallbackImageHeight: item.height)
        let showsX = viewModel.showsHorizontalSlider(fallbackImageWidth: item.width)
        let showsY = viewModel.showsVerticalSlider(fallbackImageHeight: item.height)
        let sliderEnabled = viewModel.isCacheReady && isInteractionEnabled
        let dodgeLeading = viewModel.shouldDodgeLoupe(
            fallbackImageWidth: item.width,
            fallbackImageHeight: item.height
        )

        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow(alignment: .top) {
                imageCanvas(
                    maxBlocksX: maxBlocksX,
                    maxBlocksY: maxBlocksY,
                    dodgeLeading: dodgeLeading
                )
                .frame(maxWidth: .infinity)
                .frame(height: AdvancedModeCanvasViewModel.canvasHeight)

                if showsY {
                    ReticleAxisSlider(
                        value: reticleYBinding(upperBound: viewModel.ySliderUpperBound(fallbackImageHeight: item.height)),
                        range: 0...viewModel.ySliderUpperBound(fallbackImageHeight: item.height),
                        axis: .vertical,
                        isEnabled: sliderEnabled
                    )
                    .frame(
                        width: AdvancedModeCanvasViewModel.axisSliderThickness,
                        height: AdvancedModeCanvasViewModel.canvasHeight
                    )
                }
            }

            if showsX {
                GridRow {
                    ReticleAxisSlider(
                        value: reticleXBinding(upperBound: viewModel.xSliderUpperBound(fallbackImageWidth: item.width)),
                        range: 0...viewModel.xSliderUpperBound(fallbackImageWidth: item.width),
                        axis: .horizontal,
                        isEnabled: sliderEnabled
                    )
                    .frame(height: AdvancedModeCanvasViewModel.axisSliderThickness)
                    .frame(maxWidth: .infinity)

                    if showsY {
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
            loadCacheIfPossible()
        }
    }

    @ViewBuilder
    private func imageCanvas(maxBlocksX: Int, maxBlocksY: Int, dodgeLeading: Bool) -> some View {
        GeometryReader { geo in
            Image(uiImage: item.image)
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
                            maxBlocksX: maxBlocksX,
                            maxBlocksY: maxBlocksY
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
                .overlay(alignment: dodgeLeading ? .bottomLeading : .bottomTrailing) {
                    loupeOverlay
                        .padding(10)
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
    }

    @ViewBuilder
    private var loupeOverlay: some View {
        if viewModel.isCacheReady, let cache = viewModel.varianceCache {
            AdvancedModeLoupeViewport(
                image: item.image,
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

    private func reticleXBinding(upperBound: Double) -> Binding<Double> {
        Binding(
            get: { Double(viewModel.reticleBlockX) },
            set: { viewModel.reticleBlockX = Int(min(max($0, 0), upperBound).rounded()) }
        )
    }

    private func reticleYBinding(upperBound: Double) -> Binding<Double> {
        Binding(
            get: { Double(viewModel.reticleBlockY) },
            set: { viewModel.reticleBlockY = Int(min(max($0, 0), upperBound).rounded()) }
        )
    }

    private func loadCacheIfPossible() {
        guard let service = watermarkService as? WatermarkService else { return }
        viewModel.loadIfNeeded(for: item, service: service)
    }
}
