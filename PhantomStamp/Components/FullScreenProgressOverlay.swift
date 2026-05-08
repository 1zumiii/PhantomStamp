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
    @State private var hideWorkItem: DispatchWorkItem?

    // Liveness signals
    @State private var dotsPhase: Int = 0
    @State private var dotsTask: Task<Void, Never>?
    @State private var shimmerPhase: CGFloat = -1

    // Progress event buffering / throttling
    private let minProgressUpdateIntervalSeconds: Double = 0.4
    @State private var pendingProgress: [QueuedProgress] = []
    @State private var progressPumpTask: Task<Void, Never>?
    @State private var lastProgressApplyInstant: ContinuousClock.Instant?
    @State private var endRequested: Bool = false

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
                        Text("\(Int(progress * 100))%")
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
        .accessibilityElement(children: .contain)
    }

    private var detailWithDots: String {
        let dots = String(repeating: "·", count: dotsPhase)
        return dots.isEmpty ? detail : "\(detail) \(dots)"
    }

    @MainActor
    private func startIfNeeded() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        title = "Watermark"
        progress = max(0, min(progress, 1))
        isVisible = true
        endRequested = false
        lastProgressApplyInstant = nil

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

        if target >= 1.0 - 1e-9 {
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
                    if endRequested {
                        scheduleHide()
                        break
                    }
                    // Idle briefly; avoid a tight loop.
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    continue
                }

                // Priority behavior: always take the smallest progress first.
                pendingProgress.sort {
                    if $0.percentage != $1.percentage { return $0.percentage < $1.percentage }
                    return $0.enqueuedAt < $1.enqueuedAt
                }
                let next = pendingProgress.removeFirst()

                // Enforce minimum time between *applied* updates.
                if let last = lastProgressApplyInstant {
                    let elapsed = last.duration(to: clock.now)
                    let minInterval = Duration.seconds(minProgressUpdateIntervalSeconds)
                    if elapsed < minInterval {
                        try? await clock.sleep(for: (minInterval - elapsed))
                    }
                }

                detail = next.step.rawValue

                let target = next.percentage
                let delta = abs(target - progress)
                // Keep animation bounded; overall cadence is controlled by min interval.
                let duration = min(max(0.20, 0.25 + delta * 0.7), 0.90)
                withAnimation(.easeInOut(duration: duration)) {
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

