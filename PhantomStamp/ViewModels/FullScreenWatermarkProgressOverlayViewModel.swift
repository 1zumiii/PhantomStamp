//
//  FullScreenWatermarkProgressOverlayViewModel.swift
//  PhantomStamp
//  Created by Orion on 9/5/2026.
//

import Foundation
import Observation
import SwiftUI


/// ViewModel owns all progress buffering / throttling / batch state.
///
/// Design goals:
/// - The View only renders and provides lightweight UI liveness (shimmer/dots).
/// - The ViewModel binds to NotificationCenter and converts notifications into state updates.
/// - The pump is event-driven: no polling loops when there are no pending events.
@MainActor
@Observable
final class FullScreenWatermarkProgressOverlayViewModel {
    var title: String = "Watermark"
    var detail: String = AppConstants.WatermarkStep.preparation.rawValue
    var progress: Double = 0
    var progressTextValue: Double = 0

    private var hideTask: Task<Void, Never>?

    // Progress event buffering / throttling (adaptive)
    private var pendingProgress = MinHeap<QueuedProgress>(areSorted: QueuedProgress.priorityOrder)
    private var progressPumpTask: Task<Void, Never>?
    private var lastProgressApplyInstant: ContinuousClock.Instant?
    private var pumpSignal: PumpSignal = .init()

    // Notification binding
    private var isBoundToNotifications: Bool = false
    private var notificationTasks: [Task<Void, Never>] = []

    // MARK: - State machine

    enum OverlayState: Equatable, Sendable {
        case hidden
        case running(batch: BatchState)
        case finishing(batch: BatchState)

        var batch: BatchState {
            switch self {
            case .hidden:
                return .init()
            case .running(let b), .finishing(let b):
                return b
            }
        }
    }

    struct BatchState: Equatable, Sendable {
        // Public-facing batch progress
        var completed: Int = 0
        var total: Int = 0

        /// Logical batch index reported by the service (may advance before UI finishes animating).
        var current: Int = 0
        /// The file index currently shown by the per-file progress bar.
        var displayFileIndex: Int = 0

        /// Last `displayFileIndex` for which we have already sent a drain ACK.
        var lastDrainAckCurrent: Int = -1
    }

    private(set) var state: OverlayState = .hidden

    var isVisible: Bool {
        switch state {
        case .hidden: return false
        case .running, .finishing: return true
        }
    }

    var batchCompleted: Int { state.batch.completed }
    var batchTotal: Int { state.batch.total }

    func cancel() {
        hideTask?.cancel()
        hideTask = nil
        progressPumpTask?.cancel()
        progressPumpTask = nil
        for t in notificationTasks { t.cancel() }
        notificationTasks.removeAll(keepingCapacity: true)
        isBoundToNotifications = false
    }

    /// Bind to NotificationCenter once.
    /// Call this from the View's `.task` modifier.
    func bindNotificationsIfNeeded() {
        guard !isBoundToNotifications else { return }
        isBoundToNotifications = true

        let center = NotificationCenter.default

        // Show
        notificationTasks.append(
            Task { @MainActor in
                for await _ in center.notifications(named: AppConstants.Notifications.watermarkProgressOverlayDidStart) {
                    // Some callers may post `didStart` after the first progress update.
                    // Restarting while already running would rewind the visible progress (e.g. 15% -> 0%).
                    // Only start/reset when we are not currently running.
                    switch state {
                    case .hidden, .finishing:
                        startIfNeeded()
                    case .running:
                        break
                    }
                }
            }
        )

        // Hide request
        notificationTasks.append(
            Task { @MainActor in
                for await _ in center.notifications(named: AppConstants.Notifications.watermarkProgressOverlayDidEnd) {
                    requestEndAndHideWhenDrained()
                }
            }
        )

        // Per-step progress updates
        notificationTasks.append(
            Task { @MainActor in
                for await n in center.notifications(named: AppConstants.Notifications.watermarkProgress) {
                    guard let payload = n.userInfo?["payload"] as? ProgressPayload else { continue }
                    // If callers forgot to post start, show on first progress event.
                    if !isVisible { startIfNeeded() }
                    enqueueProgress(payload)
                }
            }
        )

        // Batch progress updates
        notificationTasks.append(
            Task { @MainActor in
                for await n in center.notifications(named: AppConstants.Notifications.watermarkBatchProgress) {
                    guard let payload = n.userInfo?["payload"] as? BatchProgressPayload else { continue }
                    handleBatchProgress(payload)
                }
            }
        )
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
        lastProgressApplyInstant = nil

        // Transition to running.
        var b = state.batch
        b.lastDrainAckCurrent = -1
        b.displayFileIndex = b.current
        state = .running(batch: b)

        ensureProgressPump()
        pumpSignal.signal()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            // Keep visible briefly at completion.
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                self.state = .hidden
            }
            // Clear batch state when the overlay ends.
            // (state.batch getter will provide a fresh default.)
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
            requestEndAndHideWhenDrained()
        }

        ensureProgressPump()
        pumpSignal.signal()
    }

    func requestEndAndHideWhenDrained() {
        switch state {
        case .hidden:
            // Nothing to finish.
            break
        case .running(let b):
            state = .finishing(batch: b)
        case .finishing:
            break
        }
        ensureProgressPump()
        pumpSignal.signal()
    }

    func handleBatchProgress(_ payload: BatchProgressPayload) {
        let nextCurrent = max(0, payload.current)
        var b = state.batch
        b.current = nextCurrent

        // With strict backend pacing (awaiting drain ACK), it's safe to switch immediately.
        let hasNextFile = nextCurrent < max(0, payload.total)
        if hasNextFile, nextCurrent != b.displayFileIndex {
            pendingProgress.removeAll(keepingCapacity: true)
            progressPumpTask?.cancel()
            progressPumpTask = nil
            lastProgressApplyInstant = nil
            b.lastDrainAckCurrent = -1

            var t = Transaction()
            t.animation = nil
            withTransaction(t) {
                progress = 0
                progressTextValue = 0
            }
            b.displayFileIndex = nextCurrent
            ensureProgressPump()
        }

        b.completed = max(0, payload.completed)
        b.total = max(0, payload.total)

        // Preserve running/finishing mode while updating batch state.
        switch state {
        case .hidden:
            state = .running(batch: b)
        case .running:
            state = .running(batch: b)
        case .finishing:
            state = .finishing(batch: b)
        }

        pumpSignal.signal()
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
                    let b = state.batch
                    if b.total > 1,
                       progress >= 1.0 - 1e-9,
                       b.lastDrainAckCurrent != b.displayFileIndex
                    {
                        var bb = b
                        bb.lastDrainAckCurrent = bb.displayFileIndex
                        switch state {
                        case .running:
                            state = .running(batch: bb)
                        case .finishing:
                            state = .finishing(batch: bb)
                        case .hidden:
                            break
                        }
                        NotificationCenter.default.post(
                            name: AppConstants.Notifications.watermarkPerFileProgressDidDrain,
                            object: nil,
                            userInfo: ["payload": PerFileProgressDrainPayload(current: bb.displayFileIndex)]
                        )
                    }

                    if case .finishing = state {
                        scheduleHide()
                        break
                    }

                    // Event-driven: wait until someone signals new work or a state change.
                    await pumpSignal.wait()
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

// MARK: - Pump signal (event-driven wakeups)

/// A minimal async "signal" used to wake the pump when new work arrives.
///
/// `wait()` suspends until a `signal()` happens after it started waiting.
@MainActor
private final class PumpSignal {
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func signal() {
        guard !continuations.isEmpty else { return }
        let toResume = continuations
        continuations.removeAll(keepingCapacity: true)
        for c in toResume { c.resume() }
    }

    func wait() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            continuations.append(c)
        }
    }
}

