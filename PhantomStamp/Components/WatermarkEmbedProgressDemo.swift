//
//  WatermarkEmbedProgressDemo.swift
//  PhantomStamp
//
//  Demo-only UI: listens for algorithm ``ProgressPayload`` broadcasts and renders a determinate ``ProgressView``.
//

import SwiftUI

/// Embeddable demo HUD that subscribes to ``AppConstants.Notifications/watermarkProgress`` while ``isEmbedSessionActive`` is true.
///
/// Parent should flip ``isEmbedSessionActive`` when an embed task starts / ends (extract flows leave it false).
struct WatermarkEmbedProgressDemo: View {
    @Binding var isEmbedSessionActive: Bool

    @State private var fraction: Double?
    @State private var stepDescription: String = ""

    var body: some View {
        VStack(spacing: 12) {
            if let fraction {
                ProgressView(value: fraction, total: 1.0)
                    .tint(.accentColor)
                Text(stepDescription.isEmpty ? AppConstants.Copy.Watermark.processing : stepDescription)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.horizontal, 24)
        .onAppear {
            applyEmbedSessionActive(isEmbedSessionActive)
        }
        .onChange(of: isEmbedSessionActive) { _, active in
            applyEmbedSessionActive(active)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.watermarkProgress)) { notification in
            guard let payload = notification.userInfo?["payload"] as? ProgressPayload else { return }
            Task { @MainActor in
                fraction = payload.percentage
                stepDescription = payload.step.rawValue
            }
        }
    }

    private func applyEmbedSessionActive(_ active: Bool) {
        if active {
            fraction = 0
            stepDescription = AppConstants.WatermarkStep.preparation.rawValue
        } else {
            fraction = nil
            stepDescription = ""
        }
    }
}
