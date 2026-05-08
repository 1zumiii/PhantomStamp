//
//  FullScreenDemoProgressOverlay.swift
//  PhantomStamp
//
//  Full-screen demo overlay driven by notifications.
//

import SwiftUI

/// Full-screen progress overlay for UI demos (e.g. `WatermarkInsertDemoView`).
///
/// Control via notifications:
/// - Show: `AppConstants.Notifications.demoProgressOverlayDidStart`
/// - Update: `AppConstants.Notifications.demoProgressDidUpdate` with `userInfo["payload"] as DemoProgressPayload`
/// - Hide: `AppConstants.Notifications.demoProgressOverlayDidEnd`
// NOTE: The app now uses `FullScreenWatermarkProgressOverlay` for both demos and real operations.
// `FullScreenDemoProgressOverlay` is kept only for reference and can be removed later.
struct FullScreenDemoProgressOverlay: View {
    @State private var isVisible = false
    @State private var title: String = "Processing"
    @State private var detail: String = "Please wait…"
    @State private var progress: Double = 0
    @State private var hideWorkItem: DispatchWorkItem?
    
    // Sequentially animate updates so each step stays visible briefly.
    @State private var pendingUpdates: [DemoProgressPayload] = []
    @State private var updateLoopTask: Task<Void, Never>?
    private let minStepDisplaySeconds: Double = 0.5
    
    // Extra "liveness" signals (so slow steps don't look frozen).
    @State private var dotsPhase: Int = 0
    @State private var dotsTask: Task<Void, Never>?
    @State private var shimmerPhase: CGFloat = -1

    var body: some View {
        ZStack {
            if isVisible {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
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
                            // Subtle shimmer sweep over the bar to signal activity.
                            GeometryReader { geo in
                                let w = geo.size.width
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                .clear,
                                                Color.white.opacity(0.18),
                                                .clear
                                            ],
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
                            .frame(width: 56, alignment: .trailing) // keep layout stable to avoid visual overlap
                            .transaction { $0.animation = nil } // avoid numeric ghosting during fast updates
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
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.demoProgressOverlayDidStart)) { _ in
            hideWorkItem?.cancel()
            hideWorkItem = nil
            updateLoopTask?.cancel()
            updateLoopTask = nil
            pendingUpdates.removeAll(keepingCapacity: true)
            title = "Processing"
            detail = "Please wait…"
            progress = 0
            isVisible = true
            
            // Kick off "liveness" animations.
            dotsTask?.cancel()
            dotsTask = Task { @MainActor in
                dotsPhase = 0
                while isVisible, !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s
                    dotsPhase = (dotsPhase + 1) % 4
                }
            }
            withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.demoProgressOverlayDidEnd)) { _ in
            // Keep the overlay visible briefly at completion to reduce flicker.
            hideWorkItem?.cancel()
            let item = DispatchWorkItem {
                withAnimation(.easeOut(duration: 0.18)) {
                    isVisible = false
                }
            }
            hideWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: item)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.demoProgressDidUpdate)) { notification in
            guard isVisible,
                  let payload = notification.userInfo?["payload"] as? DemoProgressPayload else { return }
            pendingUpdates.append(payload)
            if updateLoopTask == nil {
                updateLoopTask = Task { @MainActor in
                    await drainUpdateQueue()
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
    
    private var detailWithDots: String {
        let dots = String(repeating: "·", count: dotsPhase) // visually subtle and language-neutral
        return dots.isEmpty ? detail : "\(detail) \(dots)"
    }
    
    @MainActor
    private func drainUpdateQueue() async {
        while !pendingUpdates.isEmpty, !Task.isCancelled {
            let payload = pendingUpdates.removeFirst()
            title = payload.title
            detail = payload.detail
            
            let target = min(max(payload.percentage, 0), 1)
            let delta = abs(target - progress)
            let duration = min(max(0.25, 0.35 + delta * 0.9), 1.10)
            withAnimation(.easeInOut(duration: duration)) {
                progress = target
            }
            
            // Ensure the user can perceive this step (even if the producer sends updates too fast).
            let wait = max(minStepDisplaySeconds, duration)
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
        updateLoopTask = nil
    }
}

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
            startIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.watermarkProgressOverlayDidEnd)) { _ in
            scheduleHide()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.watermarkProgress)) { notification in
            guard let payload = notification.userInfo?["payload"] as? ProgressPayload else { return }
            // If callers forgot to post start, show on first progress event.
            if !isVisible { startIfNeeded() }
            detail = payload.step.rawValue
            let target = min(max(payload.percentage, 0), 1)
            let delta = abs(target - progress)
            let duration = min(max(0.25, 0.35 + delta * 0.9), 1.10)
            withAnimation(.easeInOut(duration: duration)) {
                progress = target
            }
            if target >= 1.0 - 1e-9 {
                scheduleHide()
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
}

#Preview {
    ZStack {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        FullScreenDemoProgressOverlay()
    }
}

