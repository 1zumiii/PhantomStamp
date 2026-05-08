//
//  WatermarkEmbedOnlyTests.swift
//  PhantomStamp
//
//  Manual / DEBUG validation for `WatermarkService.embedWatermark` only.
//  Focuses on:
//  - performance (total + per-step timing via progress notifications)
//  - basic success (returns an output image)
//

import Foundation
import UIKit

enum WatermarkEmbedOnlyTests {
    struct Report: Sendable {
        var imageLoaded: Bool
        var embedSucceeded: Bool
        var totalMs: Double
        var stepTimingsMs: [(step: String, ms: Double)]
        var progressEventCount: Int
    }

    static func runOnBundledTestImg(text: String) async -> Report {
        guard let img = ImagePipelineTests.loadBundledTestUIImage() else {
            return Report(imageLoaded: false, embedSucceeded: false, totalMs: 0, stepTimingsMs: [], progressEventCount: 0)
        }

        let service = WatermarkService()
        let collector = StepTimingCollector()
        collector.start()

        let t0 = CFAbsoluteTimeGetCurrent()
        do {
            _ = try await service.embedWatermark(into: img, text: text)
        } catch {
            let totalMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            collector.stop()
            return Report(
                imageLoaded: true,
                embedSucceeded: false,
                totalMs: totalMs,
                stepTimingsMs: collector.stepTimingsMs(untilNow: CFAbsoluteTimeGetCurrent()),
                progressEventCount: collector.eventsCount
            )
        }
        let totalMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        collector.stop()

        return Report(
            imageLoaded: true,
            embedSucceeded: true,
            totalMs: totalMs,
            stepTimingsMs: collector.stepTimingsMs(untilNow: CFAbsoluteTimeGetCurrent()),
            progressEventCount: collector.eventsCount
        )
    }

    static func runAndPrintBlocking() {
        #if DEBUG
        let sema = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            // Keep <= 16 bytes to satisfy current encodeFEC cap.
            let r = await runOnBundledTestImg(text: "Successful")
            let status = (r.imageLoaded && r.embedSucceeded) ? "PASS" : "FAIL"
            print("[WatermarkEmbedOnlyTests] \(status) Embed only (TestImg)")
            print("  - total: \(String(format: "%.2f", r.totalMs)) ms  progressEvents=\(r.progressEventCount)")
            for (s, ms) in r.stepTimingsMs {
                print("  - step: \(s)  \(String(format: "%.2f", ms)) ms")
            }
            sema.signal()
        }
        _ = sema.wait(timeout: .now() + 120)
        #endif
    }
}

// MARK: - Progress step timing

private final class StepTimingCollector {
    private var token: NSObjectProtocol?
    private var firstTimeByStep: [String: CFAbsoluteTime] = [:]
    private var orderedSteps: [String] = []
    private(set) var eventsCount: Int = 0

    func start() {
        stop()
        firstTimeByStep.removeAll(keepingCapacity: true)
        orderedSteps.removeAll(keepingCapacity: true)
        eventsCount = 0

        token = NotificationCenter.default.addObserver(
            forName: AppConstants.Notifications.watermarkProgress,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let payload = notification.userInfo?["payload"] as? ProgressPayload else { return }
            let step = payload.step.rawValue
            self?.eventsCount += 1
            if self?.firstTimeByStep[step] == nil {
                self?.firstTimeByStep[step] = CFAbsoluteTimeGetCurrent()
                self?.orderedSteps.append(step)
            }
        }
    }

    func stop() {
        if let token {
            NotificationCenter.default.removeObserver(token)
            self.token = nil
        }
    }

    func stepTimingsMs(untilNow now: CFAbsoluteTime) -> [(step: String, ms: Double)] {
        guard !orderedSteps.isEmpty else { return [] }
        var out: [(String, Double)] = []
        for (i, step) in orderedSteps.enumerated() {
            let t0 = firstTimeByStep[step] ?? now
            let t1: CFAbsoluteTime
            if i + 1 < orderedSteps.count {
                t1 = firstTimeByStep[orderedSteps[i + 1]] ?? now
            } else {
                t1 = now
            }
            out.append((step, max(0, (t1 - t0) * 1000)))
        }
        return out
    }
}

