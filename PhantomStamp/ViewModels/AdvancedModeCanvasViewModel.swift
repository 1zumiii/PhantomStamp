//
//  AdvancedModeCanvasViewModel.swift
//  PhantomStamp
//
//  Advanced Mode canvas state: macroblock reticle, variance cache, and loupe dodge logic.
//

import Observation
import UIKit

#if DEBUG
enum AdvancedCanvasDebug {
    static func log(_ message: String) {
        print("[AdvancedCanvas] \(message)")
    }
}
#else
enum AdvancedCanvasDebug {
    static func log(_ message: String) {}
}
#endif

@MainActor
@Observable
final class AdvancedModeCanvasViewModel {
    static let canvasHeight: CGFloat = 260
    static let loupeSize: CGFloat = 132
    static let loupeGridSpan = 15
    /// Padding around the loupe inside the image canvas overlay.
    static let loupeCanvasPadding: CGFloat = 10
    static let axisSliderThickness: CGFloat = 18
    static let gridSpacing: CGFloat = 4
    /// Initial crosshair inset from the top-leading corner (matches slider default).
    static let defaultReticleMarginFraction: CGFloat = 0.10

    var reticleBlockX: Int = 0
    var reticleBlockY: Int = 0

    private(set) var previewImage: UIImage?
    private(set) var varianceCache: MacroblockVarianceCache?
    private(set) var varianceHistogram: VarianceHistogramSummary?
    private(set) var isBuildingVarianceCache = false
    /// Human-readable status for on-screen debug (DEBUG) and support.
    private(set) var lastDebugStatus: String = "idle"
    private(set) var lastPreviewPixelSize: CGSize = .zero

    private var buildToken: UUID?
    private var activePhotoID: UUID?
    private var lastBuiltLayoutSize: CGSize?
    private var shouldApplyDefaultReticle = false

    var isCacheReady: Bool { varianceCache != nil && previewImage != nil }

    var maxBlocksX: Int {
        varianceCache?.maxBlocksX ?? 1
    }

    var maxBlocksY: Int {
        varianceCache?.maxBlocksY ?? 1
    }

    var xSliderUpperBound: Double {
        Double(max(0, maxBlocksX - 1))
    }

    var ySliderUpperBound: Double {
        Double(max(0, maxBlocksY - 1))
    }

    var showsHorizontalSlider: Bool { maxBlocksX > 1 }
    var showsVerticalSlider: Bool { maxBlocksY > 1 }

    /// True when the crosshair center overlaps the default bottom-trailing loupe slot.
    func shouldDodgeLoupe(canvasSize: CGSize) -> Bool {
        guard canvasSize.width > 0, canvasSize.height > 0,
              maxBlocksX > 1, maxBlocksY > 1 else { return false }

        let crossX = ReticleBlockGeometry.blockCenterFraction(
            index: reticleBlockX,
            blockCount: maxBlocksX
        ) * canvasSize.width
        let crossY = ReticleBlockGeometry.blockCenterFraction(
            index: reticleBlockY,
            blockCount: maxBlocksY
        ) * canvasSize.height

        let loupeFootprint = Self.loupeSize + Self.loupeCanvasPadding * 2
        let loupeMinX = canvasSize.width - loupeFootprint
        let loupeMinY = canvasSize.height - loupeFootprint

        return crossX >= loupeMinX && crossY >= loupeMinY
    }

    /// Binds the canvas to a photo. Call once when the photo identity changes.
    func bindPhoto(_ photoID: UUID) {
        guard activePhotoID != photoID else { return }
        buildToken = UUID()
        activePhotoID = photoID
        previewImage = nil
        varianceCache = nil
        varianceHistogram = nil
        isBuildingVarianceCache = false
        lastBuiltLayoutSize = nil
        shouldApplyDefaultReticle = true
        reticleBlockX = 0
        reticleBlockY = 0
        lastDebugStatus = "bound photo \(photoID.uuidString.prefix(8))"
        AdvancedCanvasDebug.log("bindPhoto \(photoID.uuidString.prefix(8))")
    }

    func updateLayout(
        containerSize: CGSize,
        displayScale: CGFloat,
        item: SelectedPhotoItem,
        service: WatermarkService
    ) {
        guard containerSize.width > 1, containerSize.height > 1 else {
            lastDebugStatus = "skip layout — size too small \(containerSize)"
            AdvancedCanvasDebug.log(lastDebugStatus)
            return
        }

        if activePhotoID == nil {
            activePhotoID = item.id
            AdvancedCanvasDebug.log("activePhotoID was nil; auto-bound \(item.id.uuidString.prefix(8))")
        }

        guard item.id == activePhotoID else {
            lastDebugStatus = "skip layout — photo mismatch"
            AdvancedCanvasDebug.log("\(lastDebugStatus) active=\(activePhotoID?.uuidString.prefix(8) ?? "nil") item=\(item.id.uuidString.prefix(8))")
            return
        }

        let rounded = CGSize(
            width: containerSize.width.rounded(.toNearestOrAwayFromZero),
            height: containerSize.height.rounded(.toNearestOrAwayFromZero)
        )

        if let lastBuiltLayoutSize,
           lastBuiltLayoutSize == rounded,
           previewImage != nil,
           varianceCache != nil {
            lastDebugStatus = "cache hit \(Int(rounded.width))×\(Int(rounded.height))"
            return
        }

        if isBuildingVarianceCache,
           lastBuiltLayoutSize == rounded {
            lastDebugStatus = "build in flight for \(Int(rounded.width))×\(Int(rounded.height))"
            AdvancedCanvasDebug.log(lastDebugStatus)
            return
        }

        lastBuiltLayoutSize = rounded
        scheduleBuild(
            item: item,
            containerSize: rounded,
            displayScale: displayScale,
            service: service
        )
    }

    private func scheduleBuild(
        item: SelectedPhotoItem,
        containerSize: CGSize,
        displayScale: CGFloat,
        service: WatermarkService
    ) {
        let token = UUID()
        buildToken = token
        isBuildingVarianceCache = true
        lastDebugStatus = "building \(Int(containerSize.width))×\(Int(containerSize.height))…"
        AdvancedCanvasDebug.log("scheduleBuild token=\(token.uuidString.prefix(8)) size=\(containerSize)")

        let photoID = item.id
        let sourceImage = item.image
        let layoutSize = containerSize
        let scale = displayScale

        Task { [weak self] in
            let preview = await MainActor.run {
                CanvasPreviewMapping.renderDisplayMatchedPreview(
                    from: sourceImage,
                    containerSize: layoutSize,
                    displayScale: scale
                ) ?? sourceImage
            }

            let cache = await Task.detached(priority: .userInitiated) {
                service.buildMacroblockVarianceCache(from: preview)
            }.value

            await MainActor.run { [weak self] in
                guard let self else { return }
                defer { self.isBuildingVarianceCache = false }

                guard self.buildToken == token else {
                    self.lastDebugStatus = "stale token — discarded"
                    AdvancedCanvasDebug.log("\(self.lastDebugStatus) expected=\(token.uuidString.prefix(8))")
                    return
                }
                guard self.activePhotoID == photoID else {
                    self.lastDebugStatus = "stale photo — discarded"
                    AdvancedCanvasDebug.log(self.lastDebugStatus)
                    return
                }

                self.previewImage = preview
                self.varianceCache = cache
                self.varianceHistogram = cache.map { VarianceHistogramSummary.build(from: $0) }
                self.lastPreviewPixelSize = CGSize(
                    width: preview.size.width * preview.scale,
                    height: preview.size.height * preview.scale
                )

                if let cache {
                    if self.shouldApplyDefaultReticle {
                        self.reticleBlockX = ReticleBlockGeometry.defaultBlockIndex(
                            blockCount: cache.maxBlocksX,
                            marginFraction: Self.defaultReticleMarginFraction
                        )
                        self.reticleBlockY = ReticleBlockGeometry.defaultBlockIndex(
                            blockCount: cache.maxBlocksY,
                            marginFraction: Self.defaultReticleMarginFraction
                        )
                        self.shouldApplyDefaultReticle = false
                    } else {
                        self.reticleBlockX = min(self.reticleBlockX, max(0, cache.maxBlocksX - 1))
                        self.reticleBlockY = min(self.reticleBlockY, max(0, cache.maxBlocksY - 1))
                    }
                    self.lastDebugStatus = "ready \(cache.maxBlocksX)×\(cache.maxBlocksY) · r(\(self.reticleBlockX),\(self.reticleBlockY))"
                    AdvancedCanvasDebug.log(
                        "build done blocks=\(cache.maxBlocksX)×\(cache.maxBlocksY) " +
                        "previewPt=\(Int(preview.size.width))×\(Int(preview.size.height))@\(preview.scale) " +
                        "previewPx=\(Int(self.lastPreviewPixelSize.width))×\(Int(self.lastPreviewPixelSize.height))"
                    )
                } else {
                    self.lastDebugStatus = "build failed — cache nil"
                    AdvancedCanvasDebug.log(self.lastDebugStatus)
                }
            }
        }
    }

    func clear() {
        buildToken = UUID()
        previewImage = nil
        varianceCache = nil
        varianceHistogram = nil
        activePhotoID = nil
        lastBuiltLayoutSize = nil
        isBuildingVarianceCache = false
        shouldApplyDefaultReticle = false
        reticleBlockX = 0
        reticleBlockY = 0
        lastDebugStatus = "cleared"
        AdvancedCanvasDebug.log("clear")
    }
}
