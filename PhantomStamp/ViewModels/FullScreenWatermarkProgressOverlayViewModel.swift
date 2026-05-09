//
//  FullScreenWatermarkProgressOverlayViewModel.swift
//  PhantomStamp
//  Created by Orion on 9/5/2026.
//

import Foundation
import Observation
import SwiftUI


/// ViewModel owns all progress buffering / throttling / batch state.
@MainActor
@Observable
final class FullScreenWatermarkProgressOverlayViewModel {
    var isVisible = false
    var title: String = "Watermark"
    var detail: String = AppConstants.WatermarkStep.preparation.rawValue
    var progress: Double = 0
    var progressTextValue: Double = 0

    // Batch (multi-file) progress
    var batchCompleted: Int = 0
    var batchTotal: Int = 0

    /// Logical batch index reported by the service (may advance before UI finishes animating).
    private(set) var batchCurrent: Int = 0
    /// The file index currently shown by the per-file progress bar.
    private(set) var displayFileIndex: Int = 0
    private var lastDrainAckCurrent: Int = -1

    private var hideTask: Task<Void, Never>?

    // Progress event buffering / throttling (adaptive)
    private var pendingProgress = MinHeap<QueuedProgress>(areSorted: QueuedProgress.priorityOrder)
    private var progressPumpTask: Task<Void, Never>?
    private var lastProgressApplyInstant: ContinuousClock.Instant?
    private var endRequested: Bool = false

    func cancel() {
        hideTask?.cancel()
        hideTask = nil
        progressPumpTask?.cancel()
        progressPumpTask = nil
    }

    func startIfNeeded() {
        hideTask?.cancel()
        hideTask = nil
        title = "Watermark"
        pendingProgress.removeAll(keepingCapacity: true)
        progressPumpTask?.cancel()
        progressPumpTask = nil

        // Reset progress without animation to avoid "100% -> 0%" rewind effect between runs.
        var t = Transaction()
        t.animation = nil
        withTransaction(t) {
            progress = 0
            progressTextValue = 0
        }
        isVisible = true
        endRequested = false
        lastProgressApplyInstant = nil
        lastDrainAckCurrent = -1
        displayFileIndex = batchCurrent

        ensureProgressPump()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            // Keep visible briefly at completion.
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                self.isVisible = false
            }
            // Clear batch state when the overlay ends.
            self.batchCompleted = 0
            self.batchTotal = 0
            self.batchCurrent = 0
        }
    }

    // MARK: - Progress queue (priority + throttling)

    func enqueueProgress(_ payload: ProgressPayload) {
        let target = min(max(payload.percentage, 0), 1)
        pendingProgress.insert(
            .init(
                step: payload.step,
                percentage: target,
                enqueuedAt: DispatchTime.now().uptimeNanoseconds
            )
        )

        // NOTE:
        // Do NOT auto-hide on completion during batch processing.
        // Batch runs are explicitly ended by `watermarkProgressOverlayDidEnd`.
        if target >= 1.0 - 1e-9, batchTotal <= 1 {
            endRequested = true
        }

        ensureProgressPump()
    }

    func requestEndAndHideWhenDrained() {
        endRequested = true
        ensureProgressPump()
    }

    func handleBatchProgress(_ payload: BatchProgressPayload) {
        let nextCurrent = max(0, payload.current)
        batchCurrent = nextCurrent

        // With strict backend pacing (awaiting drain ACK), it's safe to switch immediately.
        let hasNextFile = nextCurrent < max(0, payload.total)
        if hasNextFile, nextCurrent != displayFileIndex {
            pendingProgress.removeAll(keepingCapacity: true)
            progressPumpTask?.cancel()
            progressPumpTask = nil
            lastProgressApplyInstant = nil
            lastDrainAckCurrent = -1

            var t = Transaction()
            t.animation = nil
            withTransaction(t) {
                progress = 0
                progressTextValue = 0
            }
            displayFileIndex = nextCurrent
            ensureProgressPump()
        }

        batchCompleted = max(0, payload.completed)
        batchTotal = max(0, payload.total)
    }

    private func ensureProgressPump() {
        guard progressPumpTask == nil else { return }
        progressPumpTask = Task { @MainActor in
            let clock = ContinuousClock()
            defer { progressPumpTask = nil }

            while isVisible, !Task.isCancelled {
                if pendingProgress.isEmpty {
                    // If we're in batch mode and the UI has fully displayed completion for the current file,
                    // send an ack so the service can safely advance to the next file.
                    if batchTotal > 1,
                       progress >= 1.0 - 1e-9,
                       lastDrainAckCurrent != displayFileIndex
                    {
                        lastDrainAckCurrent = displayFileIndex
                        NotificationCenter.default.post(
                            name: AppConstants.Notifications.watermarkPerFileProgressDidDrain,
                            object: nil,
                            userInfo: ["payload": PerFileProgressDrainPayload(current: displayFileIndex)]
                        )
                    }

                    if endRequested {
                        scheduleHide()
                        break
                    }
                    // Idle briefly; avoid a tight loop.
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    continue
                }

                // Priority queue behavior: always take the smallest progress first.
                guard let next = pendingProgress.popMin() else {
                    continue
                }

                // Enforce minimum time between *applied* updates (adaptive + fast-forward under backlog).
                let qCount = pendingProgress.count
                let dynamicMinInterval = qCount > 2 ? 0.01 : 0.10

                let deltaForInterval = abs(next.percentage - progress)
                let intervalSeconds = min(max(deltaForInterval * 10.0, dynamicMinInterval), 1.00)
                if let last = lastProgressApplyInstant {
                    let elapsed = last.duration(to: clock.now)
                    let minInterval = Duration.seconds(intervalSeconds)
                    if elapsed < minInterval {
                        try? await clock.sleep(for: (minInterval - elapsed))
                    }
                }

                detail = next.step.rawValue

                let target = next.percentage
                // Drop stale regressions (can happen with concurrent notifications arriving out of order).
                if target < progress - 1e-9 {
                    continue
                }

                // Update the percent label without animation (avoid "counting" feel).
                var tNoAnim = Transaction()
                tNoAnim.animation = nil
                withTransaction(tNoAnim) {
                    progressTextValue = target
                }

                // Animation duration should also adapt to backlog.
                let dynamicAnimDuration = qCount > 2
                    ? 0.10
                    : min(max(0.20, 0.25 + deltaForInterval * 0.7), 0.90)
                withAnimation(.easeInOut(duration: dynamicAnimDuration)) {
                    progress = target
                }
                lastProgressApplyInstant = clock.now
            }
        }
    }
}

