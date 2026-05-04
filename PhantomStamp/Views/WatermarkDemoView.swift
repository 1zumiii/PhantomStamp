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
    @State private var lastExtractedText: String?
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppConstants.Layout.watermarkSectionSpacing) {
                    Image(uiImage: currentImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: AppConstants.Layout.watermarkPreviewMaxHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    if isLoading {
                        ProgressView()
                    }

                    Button(AppConstants.Copy.Watermark.embedButton) {
                        Task { await runEmbed() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)

                    Button(AppConstants.Copy.Watermark.extractButton) {
                        Task { await runExtract() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)

                    if let text = lastExtractedText {
                        Text(text)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    SectionCaption(text: AppConstants.Copy.Watermark.captionDependencyInjection)

                    SectionCaption(
                        text: settingsStore.autoLogWatermarkToHistory
                            ? AppConstants.Copy.Watermark.captionHistoryHintWhenLogging
                            : AppConstants.Copy.Watermark.captionHistoryHintWhenNotLogging
                    )
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(AppConstants.Copy.Watermark.navigationTitle)
            .alert(AppConstants.Copy.Watermark.alertTitle, isPresented: $showAlert) {
                Button(AppConstants.Copy.Watermark.okButton, role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }

    private func runEmbed() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let text = AppConstants.Watermark.embedSampleText
            let output = try await watermarkService.embedWatermark(into: currentImage, text: text)
            currentImage = output
            lastExtractedText = nil

            if settingsStore.autoLogWatermarkToHistory {
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
        isLoading = true
        defer { isLoading = false }

        do {
            let text = try await watermarkService.extractWatermark(from: currentImage)
            lastExtractedText = text

            if settingsStore.autoLogWatermarkToHistory {
                HistoryRecordService.append(
                    modelContext,
                    kind: AppConstants.HistoryRecordKind.watermarkExtracted,
                    message: String(format: AppConstants.Copy.History.logWatermarkExtractedFormat, text)
                )
            }
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        alertMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        showAlert = true
    }
}

#Preview {
    let schema = Schema([HistoryEntry.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    return WatermarkDemoView(
        watermarkService: MockWatermarkService(),
        settingsStore: UserSettingsStore()
    )
    .modelContainer(container)
}
