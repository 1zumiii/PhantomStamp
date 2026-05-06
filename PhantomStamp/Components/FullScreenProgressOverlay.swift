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
struct FullScreenDemoProgressOverlay: View {
    @State private var isVisible = false
    @State private var title: String = "Processing"
    @State private var detail: String = "Please wait…"
    @State private var progress: Double = 0

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

                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.headline.weight(.semibold))
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()
                    }

                    ProgressView(value: progress, total: 1.0)
                        .tint(.accentColor)

                    HStack {
                        Text("\(Int(progress * 100))%")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
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
            title = "Processing"
            detail = "Please wait…"
            progress = 0
            isVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.demoProgressOverlayDidEnd)) { _ in
            isVisible = false
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.demoProgressDidUpdate)) { notification in
            guard isVisible,
                  let payload = notification.userInfo?["payload"] as? DemoProgressPayload else { return }
            title = payload.title
            detail = payload.detail
            progress = min(max(payload.percentage, 0), 1)
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    ZStack {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        FullScreenDemoProgressOverlay()
    }
}

