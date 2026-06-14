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
    // Pump tuning — three tiers: live (readable steps), moderate (mild backlog), catch-up (deep backlog only).
    private static let catchUpBacklogThreshold = 10
    private static let completionHoldNanoseconds: UInt64 = 1_000_000_000

    // Embed strip phase (matches WatermarkService colorEnd…stripsEnd budget).
    private static let embedStripsPhaseStart = 0.50
    private static let embedStripsPhaseEnd = 0.75
    private static let stripHeavyBacklogThreshold = 8
    private static let stripMilestoneAdvance = 0.10

    private enum PumpPacing {
        case live
        case moderate
        case catchUp

        var minIntervalSeconds: Double {
            switch self {
            case .live: 0.1
            case .moderate: 0.06
            case .catchUp: 0.03
            }
        }

        var maxIntervalSeconds: Double {
            switch self {
            case .live: 0.55
            case .moderate: 0.42
            case .catchUp: 0.28
            }
        }

        var intervalDeltaMultiplier: Double {
            switch self {
            case .live: 7.0
            case .moderate: 6.0
            case .catchUp: 4.5
            }
        }

        func animationDuration(delta: Double) -> Double {
            switch self {
            case .live:
                return min(max(0.22, 0.28 + delta * 0.75), 0.55)
            case .moderate:
                return min(max(0.16, 0.20 + delta * 0.55), 0.34)
            case .catchUp:
                return 0.13
            }
        }

        static func resolve(backlogCount: Int, isFinishing: Bool, inStripPhase: Bool) -> PumpPacing {
            if inStripPhase {
                // Strip embedding is the longest stage — never rush or skip to catch-up pacing.
                if backlogCount > 0 || isFinishing { return .moderate }
                return .live
            }
            if backlogCount >= FullScreenWatermarkProgressOverlayViewModel.catchUpBacklogThreshold - 1 {
                return .catchUp
            }
            if backlogCount > 0 || isFinishing {
                return .moderate
            }
            return .live
        }
    }

    var title: String = "A little pixel magic"
    var detail: String = AppConstants.WatermarkStep.preparation.rawValue
    var progress: Double = 0
    var progressTextValue: Double = 0
    private(set) var presentationSequence: Int = 0

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

        // Robustness / internal test page
        notificationTasks.append(
            Task { @MainActor in
                for await n in center.notifications(named: AppConstants.Notifications.robustnessTestProgressOverlayDidStart) {
                    guard let payload = n.userInfo?["payload"] as? RobustnessTestProgressPayload else { continue }
                    startRobustnessTestIfNeeded(payload)
                }
            }
        )
        notificationTasks.append(
            Task { @MainActor in
                for await _ in center.notifications(named: AppConstants.Notifications.robustnessTestProgressOverlayDidEnd) {
                    requestEndAndHideWhenDrained()
                }
            }
        )
        notificationTasks.append(
            Task { @MainActor in
                for await n in center.notifications(named: AppConstants.Notifications.robustnessTestProgressDidUpdate) {
                    guard let payload = n.userInfo?["payload"] as? RobustnessTestProgressPayload else { continue }
                    if !isVisible { startRobustnessTestIfNeeded(payload) }
                    enqueueRobustnessTestProgress(payload)
                }
            }
        )
    }

    private func startRobustnessTestIfNeeded(_ payload: RobustnessTestProgressPayload) {
        switch state {
        case .hidden, .finishing:
            startIfNeeded()
        case .running:
            break
        }
        title = payload.kind.rawValue
        detail = payload.phase
    }

    func enqueueRobustnessTestProgress(_ payload: RobustnessTestProgressPayload) {
        title = payload.kind.rawValue
        pendingProgress.insert(
            .init(
                step: .preparation,
                percentage: min(max(payload.percentage, 0), 1),
                enqueuedAt: DispatchTime.now().uptimeNanoseconds,
                detailOverride: payload.phase
            )
        )
        if payload.percentage >= 1.0 - 1e-9 {
            requestEndAndHideWhenDrained()
        }
        ensureProgressPump()
        pumpSignal.signal()
    }

    func startIfNeeded() {
        hideTask?.cancel()
        hideTask = nil
        presentationSequence &+= 1
        title = "A little pixel magic"
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
            try? await Task.sleep(nanoseconds: Self.completionHoldNanoseconds)
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
                enqueuedAt: DispatchTime.now().uptimeNanoseconds,
                detailOverride: nil
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

    private func isProcessingStripsEvent(_ item: QueuedProgress) -> Bool {
        item.step == .processingStrips
    }

    private func isInEmbedStripsPhase(_ percentage: Double) -> Bool {
        percentage >= Self.embedStripsPhaseStart - 1e-9 && percentage < Self.embedStripsPhaseEnd - 1e-9
    }

    private func pendingQueueHasStripWork() -> Bool {
        pendingProgress.contains { isProcessingStripsEvent($0) }
    }

    private func isInStripPlaybackPhase(for next: QueuedProgress) -> Bool {
        isProcessingStripsEvent(next)
            || isInEmbedStripsPhase(progress)
            || pendingQueueHasStripWork()
    }

    private func shouldCoalescePendingProgress() -> Bool {
        guard pendingProgress.count >= Self.catchUpBacklogThreshold else { return false }
        // Never merge strip-phase ticks — that stage should remain visible on the bar.
        if pendingQueueHasStripWork() || isInEmbedStripsPhase(progress) { return false }
        return true
    }

    /// When strip ticks pile up, play ~15% milestones instead of every strip completion or one big jump.
    private func popProgressEvent() -> QueuedProgress? {
        guard let first = pendingProgress.popMin() else { return nil }

        let heavyStripBacklog = pendingProgress.count >= Self.stripHeavyBacklogThreshold - 1
            && isProcessingStripsEvent(first)
        guard heavyStripBacklog else { return first }

        var chosen = first
        let milestoneTarget = min(chosen.percentage + Self.stripMilestoneAdvance, Self.embedStripsPhaseEnd)

        while let item = pendingProgress.popMin() {
            if isProcessingStripsEvent(item) {
                chosen = item
                if item.percentage >= milestoneTarget - 1e-9 || item.percentage >= Self.embedStripsPhaseEnd - 1e-9 {
                    break
                }
            } else {
                pendingProgress.insert(item)
                break
            }
        }
        return chosen
    }

    /// Collapse the queue to a single highest-percentage event (latest detail wins ties).
    private func coalescePendingProgress() -> QueuedProgress? {
        var best: QueuedProgress?
        while let item = pendingProgress.popMin() {
            guard let current = best else {
                best = item
                continue
            }
            if item.percentage > current.percentage + 1e-9 {
                best = item
            } else if abs(item.percentage - current.percentage) <= 1e-9, item.enqueuedAt >= current.enqueuedAt {
                best = item
            }
        }
        return best
    }

    private var isFinishing: Bool {
        if case .finishing = state { return true }
        return false
    }

    private func applyProgressUpdate(_ next: QueuedProgress, clock: ContinuousClock) async {
        let backlogCount = pendingProgress.count
        let inStripPhase = isInStripPlaybackPhase(for: next)
        let pacing = PumpPacing.resolve(
            backlogCount: backlogCount,
            isFinishing: isFinishing,
            inStripPhase: inStripPhase
        )

        let deltaForInterval = abs(next.percentage - progress)
        let intervalSeconds = min(
            max(deltaForInterval * pacing.intervalDeltaMultiplier, pacing.minIntervalSeconds),
            pacing.maxIntervalSeconds
        )
        if let last = lastProgressApplyInstant {
            let elapsed = last.duration(to: clock.now)
            let wait = Duration.seconds(intervalSeconds)
            if elapsed < wait {
                try? await clock.sleep(for: wait - elapsed)
            }
        }

        if next.detailOverride == nil {
            title = next.step.isExtraction ? "Finding the watermark" : "Hiding the watermark"
        }
        detail = next.detailOverride ?? next.step.rawValue

        let target = next.percentage
        if target < progress - 1e-9 {
            return
        }

        var tNoAnim = Transaction()
        tNoAnim.animation = nil
        withTransaction(tNoAnim) {
            progressTextValue = target
        }

        let animDuration = pacing.animationDuration(delta: deltaForInterval)
        withAnimation(.easeInOut(duration: animDuration)) {
            progress = target
        }
        lastProgressApplyInstant = clock.now
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

                if shouldCoalescePendingProgress() {
                    guard let merged = coalescePendingProgress() else { continue }
                    await applyProgressUpdate(merged, clock: clock)
                    continue
                }

                guard let next = popProgressEvent() else {
                    continue
                }
                await applyProgressUpdate(next, clock: clock)
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
