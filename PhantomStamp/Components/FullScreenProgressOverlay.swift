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
    @State private var vm = FullScreenWatermarkProgressOverlayViewModel()

    // Liveness signals
    @State private var dotsPhase: Int = 0
    @State private var dotsTask: Task<Void, Never>?
    @State private var shimmerPhase: CGFloat = -1
    @State private var isShimmerRunning: Bool = false

    var body: some View {
        ZStack {
            if vm.isVisible {
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
                            Text(vm.title)
                                .font(.headline.weight(.semibold))
                            Text(detailWithDots)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        if vm.batchTotal > 1 {
                            batchBadge
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }
                    }

                    ProgressView(value: vm.progress, total: 1.0)
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
                            .mask(ProgressView(value: vm.progress, total: 1.0).tint(.white))
                        }

                    HStack {
                        Text("\(Int(vm.progressTextValue * 100))%")
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
        .animation(.easeOut(duration: 0.18), value: vm.isVisible)
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.watermarkProgressOverlayDidStart)) { _ in
            Task { @MainActor in
                vm.startIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.watermarkProgressOverlayDidEnd)) { _ in
            Task { @MainActor in
                vm.requestEndAndHideWhenDrained()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.watermarkProgress)) { notification in
            guard let payload = notification.userInfo?["payload"] as? ProgressPayload else { return }
            Task { @MainActor in
                // If callers forgot to post start, show on first progress event.
                if !vm.isVisible { vm.startIfNeeded() }
                vm.enqueueProgress(payload)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.watermarkBatchProgress)) { notification in
            guard let payload = notification.userInfo?["payload"] as? BatchProgressPayload else { return }
            Task { @MainActor in
                vm.handleBatchProgress(payload)
            }
        }
        .onDisappear {
            // Ensure background tasks stop if the view is removed.
            vm.cancel()
            dotsTask?.cancel()
            dotsTask = nil
            isShimmerRunning = false
        }
        .accessibilityElement(children: .contain)
        .task {
            // Start liveness animations once.
            if dotsTask == nil {
                dotsTask = Task { @MainActor in
                    dotsPhase = 0
                    while !Task.isCancelled {
                        if vm.isVisible {
                            try? await Task.sleep(nanoseconds: 250_000_000)
                            dotsPhase = (dotsPhase + 1) % 4
                        } else {
                            if dotsPhase != 0 { dotsPhase = 0 }
                            try? await Task.sleep(nanoseconds: 200_000_000)
                        }
                    }
                }
            }
        }
        .onChange(of: vm.isVisible) { _, newValue in
            if newValue {
                guard !isShimmerRunning else { return }
                isShimmerRunning = true

                // Reset shimmer position without animation; then start a single repeating animation.
                var t = Transaction()
                t.animation = nil
                withTransaction(t) {
                    shimmerPhase = -1
                }
                withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                    shimmerPhase = 1.0
                }
            } else {
                isShimmerRunning = false
                var t = Transaction()
                t.animation = nil
                withTransaction(t) {
                    shimmerPhase = -1
                }
            }
        }
    }

    private var detailWithDots: String {
        let dots = String(repeating: "·", count: dotsPhase)
        let base = vm.detail
        return dots.isEmpty ? base : "\(base) \(dots)"
    }

    private var batchBadge: some View {
        let total = max(vm.batchTotal, 1)
        let completedClamped = min(max(vm.batchCompleted, 0), total)
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
        .accessibilityLabel("File \(completedClamped) / \(total)")
    }
}

#Preview {
    ZStack {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        FullScreenWatermarkProgressOverlay()
    }
}

