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
    @State private var ghostIsFloating = false

    var body: some View {
        ZStack {
            if vm.isVisible {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()

                ZStack(alignment: .topTrailing) {
                    PhantomGhost()
                        .frame(width: 74, height: 94)
                        .offset(x: 16, y: ghostIsFloating ? -64 : -61)
                        .shadow(color: Color.white.opacity(0.72), radius: 1.5)
                        .shadow(color: Color.black.opacity(0.22), radius: 7, x: 0, y: 3)

                    VStack(spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "wand.and.stars")
                                .font(.title2)
                                .foregroundStyle(Color.phantomAccent)
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
                            .tint(.phantomAccent)
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
                            // Generic UI pacing copy: this is shown while the progress pump
                            // deliberately gives each pipeline stage enough time to be readable.
                            Text("Giving the pixels a moment.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: 420)
                    .background {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.phantomCardBackground)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.20), radius: 30, x: 0, y: 18)
                }
                .padding(.horizontal, 22)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: vm.isVisible)
        .onDisappear {
            // Ensure background tasks stop if the view is removed.
            vm.cancel()
            dotsTask?.cancel()
            dotsTask = nil
            isShimmerRunning = false
        }
        .accessibilityElement(children: .contain)
        .task {
            vm.bindNotificationsIfNeeded()

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
                ghostIsFloating = false

                // Reset shimmer position without animation; then start a single repeating animation.
                var t = Transaction()
                t.animation = nil
                withTransaction(t) {
                    shimmerPhase = -1
                }
                withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                    shimmerPhase = 1.0
                }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    ghostIsFloating = true
                }
            } else {
                isShimmerRunning = false
                ghostIsFloating = false
                var t = Transaction()
                t.animation = nil
                withTransaction(t) {
                    shimmerPhase = -1
                }
            }
        }
        .onChange(of: vm.presentationSequence) { _, _ in
            Task { @MainActor in
                // Release CPU-heavy producers only after the 180 ms entrance transition has
                // completed, so the overlay never has to animate while extraction is ramping up.
                try? await Task.sleep(nanoseconds: 220_000_000)
                guard vm.isVisible else { return }
                NotificationCenter.default.post(
                    name: AppConstants.Notifications.watermarkProgressOverlayDidPresent,
                    object: nil
                )
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
                        colors: [Color.phantomAccent.opacity(0.55), Color.phantomAccent],
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
        Color.phantomPageBackground.ignoresSafeArea()
        FullScreenWatermarkProgressOverlay()
    }
}
