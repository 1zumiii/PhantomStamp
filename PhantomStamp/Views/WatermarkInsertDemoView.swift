//
//  WatermarkInsertDemoView.swift
//  PhantomStamp
//
//  UI-only demo: modern "Insert Watermark" screen with simulated progress.
//

import SwiftUI
import UIKit

struct WatermarkInsertDemoView: View {
    let watermarkService: any WatermarkServiceProtocol
    var settingsStore: UserSettingsStore

    // UI-only placeholders (no real upload logic in this demo).
    @State private var uploadedSkeletons: [Color] = [
        Color.pink.opacity(0.35),
        Color.blue.opacity(0.30),
        Color.green.opacity(0.28),
        Color.orange.opacity(0.30),
        Color.purple.opacity(0.30),
        Color.teal.opacity(0.30),
        Color.indigo.opacity(0.30),
    ]
    @State private var watermarkText: String = "Hello PhantomStamp"

    @State private var isRunning = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    uploadCard

                    inputCard

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Insert Watermark")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        TestPage(watermarkService: watermarkService, settingsStore: settingsStore)
                    } label: {
                        Label("Tools", systemImage: "wrench.and.screwdriver")
                    }
                }
            }

            floatingActions
                .padding(.horizontal, 18)
                // Lift above the Tab Bar to avoid visual overlap.
                .padding(.bottom, 16)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Demo mode")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                }

            Text("Design a clean, modern embed flow.")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            Text("This page simulates an insert operation and a determinate progress bar. No watermark logic runs here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var uploadCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Upload", systemImage: "arrow.up.doc")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            // Big dashed drop-zone (tap-to-upload affordance).
            Button {
                // UI-only: no upload action in this demo.
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))

                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            Color.primary.opacity(0.28),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 7])
                        )

                    VStack(spacing: 10) {
                        Image(systemName: "photo.badge.plus")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                        Text("Tap to upload a photo")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("PNG or JPEG • Up to 4K")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 18)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 320)
            }
            .buttonStyle(.plain)
            .disabled(isRunning)

            Divider()
                .opacity(0.35)

            HStack(alignment: .center, spacing: 10) {
                Label("Uploaded", systemImage: "rectangle.stack")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Demo skeletons")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            uploadedThumbnailsRow
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 22, x: 0, y: 12)
    }

    private var uploadedThumbnailsRow: some View {
        let maxVisible = 6
        let visible = Array(uploadedSkeletons.prefix(maxVisible))
        let overflow = max(0, uploadedSkeletons.count - visible.count)

        return ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, color in
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(color)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        }
                        .frame(width: 58, height: 58)
                        .redacted(reason: .placeholder)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                }

                if overflow > 0 {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                        }
                        .frame(width: 58, height: 58)
                        .overlay {
                            Text("…")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("More uploaded items")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }


    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Payload", systemImage: "character.cursor.ibeam")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Text("Watermark text")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Type something…", text: $watermarkText)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isRunning)

                Text("Tip: keep it short for robustness.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        }
    }

    private var floatingActions: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Spacer()

                Button {
                    resetDemo()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.body.weight(.semibold))
                        .frame(width: 52, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.14), radius: 18, x: 0, y: 10)
                .disabled(isRunning)
                .accessibilityLabel("Reset")

                Button {
                    Task { await runSimulatedInsert() }
                } label: {
                    Image(systemName: isRunning ? "hourglass" : "sparkles")
                        .font(.body.weight(.semibold))
                        .frame(width: 52, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.32, green: 0.55, blue: 1.00),
                                    Color(red: 0.35, green: 0.85, blue: 0.95),
                                    Color(red: 0.88, green: 0.42, blue: 0.98),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 14)
                .disabled(isRunning)
                .accessibilityLabel("Insert watermark")
            }
        }
    }

    private func resetDemo() {
        watermarkText = "Hello PhantomStamp"
    }

    private func runSimulatedInsert() async {
        isRunning = true
        NotificationCenter.default.post(name: AppConstants.Notifications.demoProgressOverlayDidStart, object: nil)
        defer { isRunning = false }

        let phases: [(String, ClosedRange<Double>, UInt64)] = [
            ("Preparing payload…", 0.00...0.18, 450_000_000),
            ("Transforming blocks…", 0.18...0.72, 1_200_000_000),
            ("Reassembling image…", 0.72...0.93, 500_000_000),
            ("Finalizing…", 0.93...1.00, 350_000_000),
        ]

        for (label, range, duration) in phases {
            await animateProgress(title: "Inserting watermark", detail: label, from: range.lowerBound, to: range.upperBound, durationNs: duration)
        }

        NotificationCenter.default.post(
            name: AppConstants.Notifications.demoProgressDidUpdate,
            object: nil,
            userInfo: ["payload": DemoProgressPayload(title: "Completed", detail: "UI-only simulation.", percentage: 1)]
        )
        try? await Task.sleep(nanoseconds: 450_000_000)
        NotificationCenter.default.post(name: AppConstants.Notifications.demoProgressOverlayDidEnd, object: nil)
    }

    private func animateProgress(title: String, detail: String, from: Double, to: Double, durationNs: UInt64) async {
        let steps = 45
        let stepNs = max(UInt64(1), durationNs / UInt64(steps))
        for i in 1...steps {
            try? await Task.sleep(nanoseconds: stepNs)
            let t = Double(i) / Double(steps)
            let p = from + (to - from) * t
            NotificationCenter.default.post(
                name: AppConstants.Notifications.demoProgressDidUpdate,
                object: nil,
                userInfo: ["payload": DemoProgressPayload(title: title, detail: detail, percentage: p)]
            )
        }
    }
}

#Preview {
    NavigationStack {
        WatermarkInsertDemoView(watermarkService: PreviewWatermarkService(), settingsStore: UserSettingsStore())
    }
}

