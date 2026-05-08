//
//  PreviewWatermarkService.swift
//  PhantomStamp
//
//  仅用于 SwiftUI Preview（主 App 目标编译）
//

import Foundation
import UIKit

final class PreviewWatermarkService: WatermarkServiceProtocol {
    func embedWatermark(into image: UIImage, text: String) async throws -> UIImage {
        await runDebugTestsWithOverlay()
        try await Task.sleep(nanoseconds: AppConstants.Watermark.mockEmbedDelayNanoseconds)
        return image
    }

    func extractWatermark(from image: UIImage) async throws -> String {
        try await Task.sleep(nanoseconds: AppConstants.Watermark.mockExtractDelayNanoseconds)
        _ = image
        return AppConstants.Watermark.mockExtractResultText
    }
}

private extension PreviewWatermarkService {
    func runDebugTestsWithOverlay() async {
        // These manual tests can be CPU-heavy; run them off the main thread to avoid freezing UI.
        await MainActor.run {
            print(AppConstants.Debug.launchLogPrefix + AppVersion.marketing)
            NotificationCenter.default.post(name: AppConstants.Notifications.demoProgressOverlayDidStart, object: nil)
            NotificationCenter.default.post(
                name: AppConstants.Notifications.demoProgressDidUpdate,
                object: nil,
                userInfo: ["payload": DemoProgressPayload(title: "Running Tests", detail: "Preparing…", percentage: 0)]
            )
        }

        struct Step {
            let title: String
            let detail: String
            let percentage: Double
            let run: @Sendable () -> Void
        }

        let steps: [Step] = [
            Step(
                title: "Running Tests",
                detail: "Image pipeline (YCbCr round-trip)…",
                percentage: 0.10,
                run: {
                    let t0 = CFAbsoluteTimeGetCurrent()
                    ImagePipelineTests.runAllBundledAndPrint()
                    let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                    print("[Timing] ImagePipelineTests.runAllBundledAndPrint took \(String(format: "%.2f", dtMs)) ms")
                }
            ),
            Step(
                title: "Running Tests",
                detail: "Matrix ops (DCT / slice / sync)…",
                percentage: 0.55,
                run: {
                    let t0 = CFAbsoluteTimeGetCurrent()
                    MatrixOperationsTests.runAllAndPrint()
                    let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                    print("[Timing] MatrixOperationsTests.runAllAndPrint took \(String(format: "%.2f", dtMs)) ms")
                }
            ),
            Step(
                title: "Running Tests",
                detail: "Data processing (FEC / sync / tile)…",
                percentage: 0.88,
                run: {
                    let t0 = CFAbsoluteTimeGetCurrent()
                    DataProcessingTests.runAllAndPrint()
                    let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                    print("[Timing] DataProcessingTests.runAllAndPrint took \(String(format: "%.2f", dtMs)) ms")
                }
            )
        ]

        for s in steps {
            await MainActor.run {
                NotificationCenter.default.post(
                    name: AppConstants.Notifications.demoProgressDidUpdate,
                    object: nil,
                    userInfo: ["payload": DemoProgressPayload(title: s.title, detail: s.detail, percentage: s.percentage)]
                )
            }
            _ = await Task.detached(priority: .userInitiated) { s.run() }.value
        }

        await MainActor.run {
            NotificationCenter.default.post(
                name: AppConstants.Notifications.demoProgressDidUpdate,
                object: nil,
                userInfo: ["payload": DemoProgressPayload(title: "Running Tests", detail: "Completed", percentage: 1)]
            )
            NotificationCenter.default.post(name: AppConstants.Notifications.demoProgressOverlayDidEnd, object: nil)
        }
    }
}
