//
//  AdvancedModeCanvasViewModel.swift
//  PhantomStamp
//
//  Advanced Mode canvas state: macroblock reticle, variance cache, and loupe dodge logic.
//

import Observation
import UIKit

@MainActor
@Observable
final class AdvancedModeCanvasViewModel {
    static let canvasHeight: CGFloat = 260
    static let loupeSize: CGFloat = 132
    static let loupeGridSpan = 15
    static let loupeDodgeFraction = 0.8
    static let axisSliderThickness: CGFloat = 28

    var reticleBlockX: Int = 0
    var reticleBlockY: Int = 0

    private(set) var varianceCache: MacroblockVarianceCache?
    private(set) var isBuildingVarianceCache = false

    private var buildToken: UUID?
    private var loadingPhotoID: UUID?

    var isCacheReady: Bool { varianceCache != nil }

    func maxBlocksX(fallbackImageWidth: Int) -> Int {
        varianceCache?.maxBlocksX ?? max(1, fallbackImageWidth / DCTMatrix8x8.side)
    }

    func maxBlocksY(fallbackImageHeight: Int) -> Int {
        varianceCache?.maxBlocksY ?? max(1, fallbackImageHeight / DCTMatrix8x8.side)
    }

    func xSliderUpperBound(fallbackImageWidth: Int) -> Double {
        Double(max(0, maxBlocksX(fallbackImageWidth: fallbackImageWidth) - 1))
    }

    func ySliderUpperBound(fallbackImageHeight: Int) -> Double {
        Double(max(0, maxBlocksY(fallbackImageHeight: fallbackImageHeight) - 1))
    }

    func showsHorizontalSlider(fallbackImageWidth: Int) -> Bool {
        maxBlocksX(fallbackImageWidth: fallbackImageWidth) > 1
    }

    func showsVerticalSlider(fallbackImageHeight: Int) -> Bool {
        maxBlocksY(fallbackImageHeight: fallbackImageHeight) > 1
    }

    func shouldDodgeLoupe(fallbackImageWidth: Int, fallbackImageHeight: Int) -> Bool {
        let maxX = maxBlocksX(fallbackImageWidth: fallbackImageWidth)
        let maxY = maxBlocksY(fallbackImageHeight: fallbackImageHeight)
        guard maxX > 1, maxY > 1 else { return false }
        let nx = CGFloat(reticleBlockX) / CGFloat(maxX - 1)
        let ny = CGFloat(reticleBlockY) / CGFloat(maxY - 1)
        return nx >= Self.loupeDodgeFraction && ny >= Self.loupeDodgeFraction
    }

    func scheduleVarianceCacheBuild(for item: SelectedPhotoItem, service: WatermarkService) {
        let token = UUID()
        buildToken = token
        loadingPhotoID = item.id
        varianceCache = nil
        isBuildingVarianceCache = true

        let photoID = item.id
        let image = item.image

        Task.detached(priority: .userInitiated) {
            let cache = service.buildMacroblockVarianceCache(from: image)
            await MainActor.run { [weak self] in
                guard let self,
                      self.buildToken == token,
                      self.loadingPhotoID == photoID else { return }
                self.isBuildingVarianceCache = false
                self.varianceCache = cache
                if let cache {
                    self.reticleBlockX = min(self.reticleBlockX, max(0, cache.maxBlocksX - 1))
                    self.reticleBlockY = min(self.reticleBlockY, max(0, cache.maxBlocksY - 1))
                }
            }
        }
    }

    func loadIfNeeded(for item: SelectedPhotoItem, service: WatermarkService) {
        guard varianceCache == nil, !isBuildingVarianceCache else { return }
        scheduleVarianceCacheBuild(for: item, service: service)
    }

    func clear() {
        varianceCache = nil
        buildToken = nil
        loadingPhotoID = nil
        isBuildingVarianceCache = false
        reticleBlockX = 0
        reticleBlockY = 0
    }

    func clampReticle(for item: SelectedPhotoItem) {
        let maxX = maxBlocksX(fallbackImageWidth: item.width)
        let maxY = maxBlocksY(fallbackImageHeight: item.height)
        reticleBlockX = min(reticleBlockX, max(0, maxX - 1))
        reticleBlockY = min(reticleBlockY, max(0, maxY - 1))
    }
}
