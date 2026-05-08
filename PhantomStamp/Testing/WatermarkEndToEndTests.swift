//
//  WatermarkEndToEndTests.swift
//  PhantomStamp
//
//  Manual / DEBUG end-to-end validation:
//  - load bundled TestImg
//  - embed watermark (frequency-domain)
//  - extract watermark back
//  - validate progress notifications from `WatermarkService.embedWatermark`
//

import Foundation
import UIKit

enum WatermarkEndToEndTests {
    struct Report {
        var imageLoaded: Bool
        var embedSucceeded: Bool
        var extractSucceeded: Bool
        var textRoundTripPassed: Bool
        var progressPassed: Bool

        var embedTotalMs: Double
        var embedStepTimingsMs: [(step: String, ms: Double)]

        var watermarkedImage: UIImage?

        var extractedText: String?
        var progressEventCount: Int
        var finalProgress: Double?
        var stepOrder: [String]
    }

    static func runAll() async -> Report {
        guard let img = ImagePipelineTests.loadBundledTestUIImage() else {
            return Report(
                imageLoaded: false,
                embedSucceeded: false,
                extractSucceeded: false,
                textRoundTripPassed: false,
                progressPassed: false,
                embedTotalMs: 0,
                embedStepTimingsMs: [],
                watermarkedImage: nil,
                extractedText: nil,
                progressEventCount: 0,
                finalProgress: nil,
                stepOrder: []
            )
        }

        // Keep <= 16 bytes to satisfy current encodeFEC cap.
        let text = "水印OK" // 3 chars, UTF-8 <= 16 bytes
        let service = WatermarkService()

        let collector = ProgressCollector()
        collector.start()

        let embedT0 = CFAbsoluteTimeGetCurrent()
        var watermarked: UIImage?
        do {
            watermarked = try await service.embedWatermark(into: img, text: text)
        } catch {
            collector.stop()
            let embedTotalMs = (CFAbsoluteTimeGetCurrent() - embedT0) * 1000
            return Report(
                imageLoaded: true,
                embedSucceeded: false,
                extractSucceeded: false,
                textRoundTripPassed: false,
                progressPassed: collector.progressPassed(),
                embedTotalMs: embedTotalMs,
                embedStepTimingsMs: collector.stepTimingsMs(untilNow: CFAbsoluteTimeGetCurrent()),
                watermarkedImage: watermarked,
                extractedText: nil,
                progressEventCount: collector.events.count,
                finalProgress: collector.events.last?.percentage,
                stepOrder: collector.stepOrder()
            )
        }

        let embedTotalMs = (CFAbsoluteTimeGetCurrent() - embedT0) * 1000
        collector.stop()

        let extracted: String?
        do {
            extracted = try await service.extractWatermark(from: watermarked!)
        } catch {
            return Report(
                imageLoaded: true,
                embedSucceeded: true,
                extractSucceeded: false,
                textRoundTripPassed: false,
                progressPassed: collector.progressPassed(),
                embedTotalMs: embedTotalMs,
                embedStepTimingsMs: collector.stepTimingsMs(untilNow: CFAbsoluteTimeGetCurrent()),
                watermarkedImage: watermarked,
                extractedText: nil,
                progressEventCount: collector.events.count,
                finalProgress: collector.events.last?.percentage,
                stepOrder: collector.stepOrder()
            )
        }

        return Report(
            imageLoaded: true,
            embedSucceeded: true,
            extractSucceeded: true,
            textRoundTripPassed: (extracted == text),
            progressPassed: collector.progressPassed(),
            embedTotalMs: embedTotalMs,
            embedStepTimingsMs: collector.stepTimingsMs(untilNow: CFAbsoluteTimeGetCurrent()),
            watermarkedImage: watermarked,
            extractedText: extracted,
            progressEventCount: collector.events.count,
            finalProgress: collector.events.last?.percentage,
            stepOrder: collector.stepOrder()
        )
    }

    static func runAllAndPrintBlocking() {
        #if DEBUG
        let sema = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            let r = await runAll()
            let status = (r.imageLoaded && r.embedSucceeded && r.extractSucceeded && r.textRoundTripPassed && r.progressPassed) ? "PASS" : "FAIL"
            print("[WatermarkEndToEndTests] \(status) Embed → Extract")
            print("  - imageLoaded:     \(r.imageLoaded ? "PASS" : "FAIL")")
            print("  - embed:           \(r.embedSucceeded ? "PASS" : "FAIL")")
            print("  - extract:         \(r.extractSucceeded ? "PASS" : "FAIL")")
            print("  - text round-trip: \(r.textRoundTripPassed ? "PASS" : "FAIL")  extracted=\(r.extractedText ?? "nil")")
            print("  - progress:        \(r.progressPassed ? "PASS" : "FAIL")  events=\(r.progressEventCount) final=\(r.finalProgress.map { String(format: "%.3f", $0) } ?? "nil")")
            print("  - embed total:     \(String(format: "%.2f", r.embedTotalMs)) ms")
            if !r.embedStepTimingsMs.isEmpty {
                print("  - embed steps:    ")
                for (s, ms) in r.embedStepTimingsMs {
                    print("      - \(s)  \(String(format: "%.2f", ms)) ms")
                }
            }
            if !r.stepOrder.isEmpty {
                print("  - steps: \(r.stepOrder.joined(separator: " → "))")
            }
            sema.signal()
        }
        _ = sema.wait(timeout: .now() + 120)
        #endif
    }
}

// MARK: - Progress collection

private final class ProgressCollector {
    struct Event: Sendable {
        var step: String
        var percentage: Double
    }

    private var token: NSObjectProtocol?
    private(set) var events: [Event] = []

    private var firstTimeByStep: [String: CFAbsoluteTime] = [:]
    private var orderedSteps: [String] = []

    func start() {
        stop()
        events.removeAll(keepingCapacity: true)
        firstTimeByStep.removeAll(keepingCapacity: true)
        orderedSteps.removeAll(keepingCapacity: true)
        token = NotificationCenter.default.addObserver(
            forName: AppConstants.Notifications.watermarkProgress,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let payload = notification.userInfo?["payload"] as? ProgressPayload else { return }
            guard let self else { return }
            self.events.append(Event(step: payload.step.rawValue, percentage: payload.percentage))

            let step = payload.step.rawValue
            if self.firstTimeByStep[step] == nil {
                self.firstTimeByStep[step] = CFAbsoluteTimeGetCurrent()
                self.orderedSteps.append(step)
            }
        }
    }

    func stop() {
        if let token {
            NotificationCenter.default.removeObserver(token)
            self.token = nil
        }
    }

    func stepOrder() -> [String] {
        orderedSteps
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

    func progressPassed() -> Bool {
        guard let last = events.last else { return false }
        // Must end at 1 (or extremely close), and be monotonic non-decreasing.
        if abs(last.percentage - 1.0) > 1e-6 { return false }
        var prev = -Double.infinity
        for e in events {
            if e.percentage + 1e-9 < prev { return false }
            prev = e.percentage
        }
        // Should include all steps at least once.
        let steps = Set(stepOrder())
        let required: Set<String> = [
            AppConstants.WatermarkStep.preparation.rawValue,
            AppConstants.WatermarkStep.colorConversion.rawValue,
            AppConstants.WatermarkStep.processingStrips.rawValue,
            AppConstants.WatermarkStep.reassembling.rawValue,
        ]
        return required.isSubset(of: steps)
    }
}

