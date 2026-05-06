//
//  WatermarkDemoView.swift
//  PhantomStamp
//
//  依赖注入示例：只持有 `any WatermarkServiceProtocol`，不绑定 Mock / Real 具体类型。
//

import SwiftData
import SwiftUI
import UIKit

struct WatermarkDemoView: View {
    let watermarkService: any WatermarkServiceProtocol
    var settingsStore: UserSettingsStore

    @Environment(\.modelContext) private var modelContext

    @State private var currentImage: UIImage = WatermarkSampleImage.make()
    @State private var isLoading = false
    /// Enables ``WatermarkEmbedProgressDemo`` subscription + determinate bar only during embed (not extract).
    @State private var isEmbedSessionActive = false
    @State private var lastExtractedText: String?
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    modernHeader
                    // Moved the action buttons card to where the photo preview used to be.
                    actionsCard

                    payloadCard

                    Label(AppConstants.Copy.Watermark.sectionExtractResult, systemImage: "doc.plaintext")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    WatermarkExtractResultCard(text: lastExtractedText)

                    WatermarkTipsCard(
                        historyDetail: settingsStore.autoLogWatermarkEmbedToHistory
                            ? AppConstants.Copy.Watermark.captionHistoryHintWhenLogging
                            : AppConstants.Copy.Watermark.captionHistoryHintWhenNotLogging
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(AppConstants.Copy.Watermark.navigationTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        WatermarkInsertDemoView(watermarkService: watermarkService, settingsStore: settingsStore)
                    } label: {
                        Label("Insert", systemImage: "wand.and.stars")
                    }
                }
            }
            .alert(AppConstants.Copy.Watermark.alertTitle, isPresented: $showAlert) {
                Button(AppConstants.Copy.Watermark.okButton, role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }

    private func runEmbed() async {
        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidStart, object: nil)
        isLoading = true
        isEmbedSessionActive = true
        defer {
            isLoading = false
            isEmbedSessionActive = false
            NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)
        }

        do {
            let text = AppConstants.Watermark.embedSampleText
            let output = try await watermarkService.embedWatermark(into: currentImage, text: text)
            currentImage = output
            lastExtractedText = nil

            if settingsStore.autoLogWatermarkEmbedToHistory {
                HistoryRecordService.append(
                    modelContext,
                    kind: AppConstants.HistoryRecordKind.watermarkEmbedded,
                    message: String(format: AppConstants.Copy.History.logWatermarkEmbeddedFormat, text)
                )
            }
        } catch {
            present(error)
        }
    }

    private func runExtract() async {
        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidStart, object: nil)
        isLoading = true
        isEmbedSessionActive = false
        defer {
            isLoading = false
            NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)
        }

        do {
            let text = try await watermarkService.extractWatermark(from: currentImage)
            lastExtractedText = text
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        alertMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        showAlert = true
    }

    private var modernHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Demo")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                }

            Text(AppConstants.Copy.Watermark.navigationTitle)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Embed and extract are fully functional. This screen focuses on a clean, modern layout.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var payloadCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Payload", systemImage: "character.cursor.ibeam")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Text(String(format: AppConstants.Copy.Watermark.embedChipFormat, AppConstants.Watermark.embedSampleText))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(0.14))
                    }

                Text("Tip: keep the text short for robustness.")
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
        .shadow(color: Color.black.opacity(0.04), radius: 16, x: 0, y: 10)
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(AppConstants.Copy.Watermark.sectionActions, systemImage: "wand.and.stars")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                Task { await runEmbed() }
            } label: {
                Label(AppConstants.Copy.Watermark.embedButton, systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoading)

            Button {
                Task { await runExtract() }
            } label: {
                Label(AppConstants.Copy.Watermark.extractButton, systemImage: "text.magnifyingglass")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isLoading)
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
        .shadow(color: Color.black.opacity(0.05), radius: 18, x: 0, y: 10)
    }
}

// MARK: - Subviews

private struct WatermarkSectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}

private struct WatermarkPreviewCard: View {
    let image: UIImage
    let isLoading: Bool
    @Binding var isEmbedSessionActive: Bool

    var body: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 280)

            if isLoading {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                Group {
                    if isEmbedSessionActive {
                        WatermarkEmbedProgressDemo(isEmbedSessionActive: $isEmbedSessionActive)
                    } else {
                        VStack(spacing: 10) {
                            ProgressView()
                                .scaleEffect(1.12)
                                .tint(.accentColor)
                            Text(AppConstants.Copy.Watermark.processing)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }
        }
        .padding(14)
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
}

private struct WatermarkExtractResultCard: View {
    let text: String?

    var body: some View {
        Group {
            if let text {
                Text(text)
                    .font(.body.monospaced())
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text(AppConstants.Copy.Watermark.extractPlaceholder)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
        .shadow(color: Color.black.opacity(0.04), radius: 16, x: 0, y: 10)
    }
}

private struct WatermarkTipsCard: View {
    let historyDetail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            tipRow(
                icon: "arrow.triangle.branch",
                title: AppConstants.Copy.Watermark.tipArchitectureTitle,
                detail: AppConstants.Copy.Watermark.captionDependencyInjection
            )
            Divider().opacity(0.35)
            tipRow(
                icon: "clock.arrow.circlepath",
                title: AppConstants.Copy.Watermark.tipHistoryTitle,
                detail: historyDetail
            )
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.92))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.03), radius: 14, x: 0, y: 10)
    }

    @ViewBuilder
    private func tipRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 26, alignment: .center)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    let schema = Schema([HistoryEntry.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    return WatermarkDemoView(
        watermarkService: PreviewWatermarkService(),
        settingsStore: UserSettingsStore()
    )
    .modelContainer(container)
}
