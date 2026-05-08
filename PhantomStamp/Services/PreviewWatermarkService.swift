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

        func timed(_ label: String, _ block: () -> Void) {
            let t0 = CFAbsoluteTimeGetCurrent()
            block()
            let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            print("[Timing] \(label) took \(String(format: "%.2f", dtMs)) ms")
        }

        let steps: [Step] = [
            Step(
                title: "Running Tests",
                detail: "Image pipeline (YCbCr round-trip)…",
                percentage: 0.12,
                run: {
                    timed("ImagePipelineTests.runAllBundledAndPrint") {
                        ImagePipelineTests.runAllBundledAndPrint()
                    }
                }
            ),
            Step(
                title: "Running Tests",
                detail: "DSP transforms (variance / DCT)…",
                percentage: 0.28,
                run: {
                    timed("DSPTransformsTests.runAllAndPrint") {
                        DSPTransformsTests.runAllAndPrint()
                    }
                }
            ),
            Step(
                title: "Running Tests",
                detail: "Strips (slice / reassemble)…",
                percentage: 0.44,
                run: {
                    timed("StripsTests.runAllAndPrint") {
                        StripsTests.runAllAndPrint()
                    }
                }
            ),
            Step(
                title: "Running Tests",
                detail: "Alignment (64 offsets + sliding window)…",
                percentage: 0.62,
                run: {
                    timed("GridAlignmentTests.runAllAndPrint") {
                        GridAlignmentTests.runAllAndPrint()
                    }
                }
            ),
            Step(
                title: "Running Tests",
                detail: "Extraction (bits + majority vote)…",
                percentage: 0.80,
                run: {
                    timed("ExtractionAndVotingTests.runAllAndPrint") {
                        ExtractionAndVotingTests.runAllAndPrint()
                    }
                }
            ),
            Step(
                title: "Running Tests",
                detail: "Data processing (FEC / sync / tile)…",
                percentage: 0.92,
                run: {
                    timed("DataProcessingTests.runAllAndPrint") {
                        DataProcessingTests.runAllAndPrint()
                    }
                }
            ),
            Step(
                title: "Running Tests",
                detail: "End-to-end (embed → extract)…",
                percentage: 0.97,
                run: {
                    timed("WatermarkEndToEndTests.runAllAndPrintBlocking") {
                        WatermarkEndToEndTests.runAllAndPrintBlocking()
                    }
                }
            ),
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
