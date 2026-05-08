//
//  FullScreenProgressOverlay.swift
//  PhantomStamp
//
//

import SwiftUI

// MARK: - Watermark progress overlay (real embed/extract)

/// Full-screen progress overlay for real watermark operations.
///
/// Control via notifications:
/// - Show: `AppConstants.Notifications.watermarkProgressOverlayDidStart`
/// - Update: `AppConstants.Notifications.watermarkProgress` with `userInfo["payload"] as ProgressPayload`
/// - Hide: `AppConstants.Notifications.watermarkProgressOverlayDidEnd`
struct FullScreenWatermarkProgressOverlay: View {
    @State private var isVisible = false
    @State private var title: String = "Watermark"
    @State private var detail: String = AppConstants.WatermarkStep.preparation.rawValue
    @State private var progress: Double = 0
    @State private var progressTextValue: Double = 0
    @State private var hideWorkItem: DispatchWorkItem?

    // Liveness signals
    @State private var dotsPhase: Int = 0
    @State private var dotsTask: Task<Void, Never>?
    @State private var shimmerPhase: CGFloat = -1

    // Progress event buffering / throttling (adaptive)
    @State private var pendingProgress: [QueuedProgress] = []
    @State private var progressPumpTask: Task<Void, Never>?
    @State private var lastProgressApplyInstant: ContinuousClock.Instant?
    @State private var endRequested: Bool = false

    // Batch (multi-file) progress
    @State private var batchCompleted: Int = 0
    @State private var batchTotal: Int = 0
    /// Logical batch index reported by the service (may advance before UI finishes animating).
    @State private var batchCurrent: Int = 0
    /// The file index currently shown by the per-file progress bar.
    @State private var displayFileIndex: Int = 0
    @State private var lastDrainAckCurrent: Int = -1

    var body: some View {
        ZStack {
            if isVisible {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                            .symbolEffect(.pulse, options: .repeating)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.headline.weight(.semibold))
                            Text(detailWithDots)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        if batchTotal > 1 {
                            batchBadge
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }
                    }

                    ProgressView(value: progress, total: 1.0)
                        .tint(.accentColor)
                        .overlay {
                            GeometryReader { geo in
                                let w = geo.size.width
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.clear, Color.white.opacity(0.18), .clear],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: max(24, w * 0.18))
                                    .offset(x: shimmerPhase * w)
                                    .blendMode(.plusLighter)
                                    .allowsHitTesting(false)
                            }
                            .mask(ProgressView(value: progress, total: 1.0).tint(.white))
                        }

                    HStack {
                        Text("\(Int(progressTextValue * 100))%")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.secondary)
                        Spacer()
                        Text("Keep the app open.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: 420)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.20), radius: 30, x: 0, y: 18)
                .padding(.horizontal, 22)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: isVisible)
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.watermarkProgressOverlayDidStart)) { _ in
            Task { @MainActor in
                startIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.watermarkProgressOverlayDidEnd)) { _ in
            Task { @MainActor in
                requestEndAndHideWhenDrained()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.watermarkProgress)) { notification in
            guard let payload = notification.userInfo?["payload"] as? ProgressPayload else { return }
            Task { @MainActor in
                // If callers forgot to post start, show on first progress event.
                if !isVisible { startIfNeeded() }
                enqueueProgress(payload)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.watermarkBatchProgress)) { notification in
            guard let payload = notification.userInfo?["payload"] as? BatchProgressPayload else { return }
            Task { @MainActor in
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
        }
        .accessibilityElement(children: .contain)
    }

    private var detailWithDots: String {
        let dots = String(repeating: "·", count: dotsPhase)
        return dots.isEmpty ? detail : "\(detail) \(dots)"
    }

    private var batchBadge: some View {
        let total = max(batchTotal, 1)
        let completedClamped = min(max(batchCompleted, 0), total)
        let p = Double(completedClamped) / Double(total)

        return ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.10), lineWidth: 3)
            Circle()
                .trim(from: 0, to: p)
                .stroke(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.55), Color.accentColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(completedClamped)/\(total)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 28, height: 28)
        .accessibilityLabel("文件 \(completedClamped) / \(total)")
    }

    @MainActor
    private func startIfNeeded() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
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

        dotsTask?.cancel()
        dotsTask = Task { @MainActor in
            dotsPhase = 0
            while isVisible, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                dotsPhase = (dotsPhase + 1) % 4
            }
        }
        shimmerPhase = -1
        withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
            shimmerPhase = 1.0
        }

        ensureProgressPump()
    }

    @MainActor
    private func scheduleHide() {
        hideWorkItem?.cancel()
        let item = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.18)) {
                isVisible = false
            }
            // Clear batch state when the overlay ends.
            batchCompleted = 0
            batchTotal = 0
            batchCurrent = 0
        }
        hideWorkItem = item
        // Keep visible briefly at completion.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: item)
    }

    // MARK: - Progress queue (priority + throttling)

    private struct QueuedProgress: Sendable {
        let step: AppConstants.WatermarkStep
        let percentage: Double
        let enqueuedAt: UInt64
    }

    @MainActor
    private func enqueueProgress(_ payload: ProgressPayload) {
        let target = min(max(payload.percentage, 0), 1)
        pendingProgress.append(
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

    @MainActor
    private func requestEndAndHideWhenDrained() {
        endRequested = true
        ensureProgressPump()
    }

    @MainActor
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
                pendingProgress.sort {
                    if $0.percentage != $1.percentage { return $0.percentage < $1.percentage }
                    return $0.enqueuedAt < $1.enqueuedAt
                }
                let next: QueuedProgress
                next = pendingProgress.removeFirst()

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

#Preview {
    ZStack {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        FullScreenWatermarkProgressOverlay()
    }
}

