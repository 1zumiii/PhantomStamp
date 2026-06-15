//
//  WatermarkAttackTestHarness.swift
//  PhantomStamp
//
//  Shared embed/extract wiring for compression & crop attack tests.
//  Uses the app's live `WatermarkService` + `UserSettingsStore` so results match
//  manual testing on the Embed / Extract tabs. Only `textureVarianceThreshold` is
//  temporarily forced to -1 (embed every 8×8 tile) during embed.
//

import UIKit

enum WatermarkAttackTestHarness {
  /// Canonical payload used by documented robustness sweeps.
  /// 15 ASCII characters/bytes -> 17x17 DCT-block tile -> 136px spatial period.
  static let referencePayload = "DesignedByOrion"

  @MainActor
  static func wire(service: WatermarkService, settingsStore: UserSettingsStore) {
    service.settingsStore = settingsStore
  }

  /// Embeds with full tile coverage while preserving all other user settings
  /// (`syncTemplateIntensity`, `embeddingStrength`, …).
  @MainActor
  static func embedForAttackTest(
    service: WatermarkService,
    settingsStore: UserSettingsStore,
    image: UIImage,
    text: String
  ) async throws -> UIImage {
    wire(service: service, settingsStore: settingsStore)
    let savedThreshold = settingsStore.textureVarianceThreshold
    settingsStore.textureVarianceThreshold = -1
    defer { settingsStore.textureVarianceThreshold = savedThreshold }
    return try await service.embedWatermarkSilently(into: image, text: text)
  }

  static func pixelSize(of image: UIImage) -> (w: Int, h: Int) {
    (Int(image.size.width * image.scale), Int(image.size.height * image.scale))
  }
}
