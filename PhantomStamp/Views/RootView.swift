//
//  RootView.swift
//  PhantomStamp
//

import SwiftData
import SwiftUI

struct RootView: View {
    let watermarkService: any WatermarkServiceProtocol

    @State private var settingsStore = UserSettingsStore()

    var body: some View {
        TabView {
            WatermarkDemoView(watermarkService: watermarkService, settingsStore: settingsStore)
                .tabItem {
                    Label(AppConstants.Copy.Tab.watermark, systemImage: AppConstants.Symbol.tabWatermark)
                }

            HistoryView(settingsStore: settingsStore)
                .tabItem {
                    Label(AppConstants.Copy.Tab.history, systemImage: AppConstants.Symbol.tabHistory)
                }

            SettingsView(settingsStore: settingsStore)
                .tabItem {
                    Label(AppConstants.Copy.Tab.settings, systemImage: AppConstants.Symbol.tabSettings)
                }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SectionCaption(text: AppConstants.Copy.Footer.versionPrefix + AppVersion.marketing)
        }
    }
}

#Preview {
    let schema = Schema([HistoryEntry.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    return RootView(watermarkService: MockWatermarkService())
        .modelContainer(container)
}
