//
//  RootView.swift
//  PhantomStamp
//

import SwiftData
import SwiftUI

struct RootView: View {
  let watermarkService: any WatermarkServiceProtocol

  @Environment(\.modelContext) private var modelContext
  @State private var settingsStore = UserSettingsStore()
  @State private var tab: AnyHashable = AnyHashable("watermark")
  @State private var historyListRefreshToken = 0

  var body: some View {
    let items: [BottomNavItem<AnyHashable>] = [
      BottomNavItem(
        id: AnyHashable("watermark"),
        title: AppConstants.Copy.Tab.watermark,
        systemImage: AppConstants.Symbol.tabEmbed
      ) {
        NavigationStack {
          WatermarkInsertView(watermarkService: watermarkService, settingsStore: settingsStore)
        }
      },
      BottomNavItem(
        id: AnyHashable("extract"),
        title: "Extract",
        systemImage: AppConstants.Symbol.tabExtract
      ) {
        NavigationStack {
          WatermarkExtractView(watermarkService: watermarkService)
        }
      },
      BottomNavItem(
        id: AnyHashable("history"),
        title: AppConstants.Copy.Tab.history,
        systemImage: AppConstants.Symbol.tabHistory
      ) {
        HistoryView(settingsStore: settingsStore, listRefreshToken: historyListRefreshToken)
      },
      BottomNavItem(
        id: AnyHashable("settings"),
        title: AppConstants.Copy.Tab.settings,
        systemImage: AppConstants.Symbol.tabSettings
      ) {
        SettingsView(watermarkService: watermarkService, settingsStore: settingsStore)
      },
    ]

    ZStack {
      PhantomThemeBackdrop()

      VStack(spacing: 0) {
        ZStack {
          ForEach(items) { item in
            item.content
              .opacity(tab == item.id ? 1 : 0)
              .allowsHitTesting(tab == item.id)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        BottomNavBar(items: items, selection: $tab)
      }

      // Full-screen overlay (used for both demos and real watermark operations).
      FullScreenWatermarkProgressOverlay()
        .zIndex(1000)
    }
    .onAppear {
      wireWatermarkServiceDependencies()
    }
    .onChange(of: modelContext) { _, _ in
      wireWatermarkServiceDependencies()
    }
    .onChange(of: tab) { _, newValue in
      if newValue == AnyHashable("history") {
        historyListRefreshToken += 1
      }
    }
    .tint(.phantomAccent)
    .preferredColorScheme(settingsStore.darkThemeEnabled ? .dark : .light)
  }

  /// Binds SwiftData + settings to the shared `WatermarkService` singleton.
  /// Called from `onAppear` and whenever SwiftUI refreshes the environment `modelContext`.
  private func wireWatermarkServiceDependencies() {
    guard let svc = watermarkService as? WatermarkService else {
      #if DEBUG
      print("[RootView] watermarkService is not WatermarkService — history wiring skipped")
      #endif
      return
    }
    svc.modelContainer = modelContext.container
    svc.settingsStore = settingsStore
  }
}

#Preview {
  let schema = Schema([HistoryEntry.self, WatermarkHistoryRecord.self])
  let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
  let container = try! ModelContainer(for: schema, configurations: [config])
  return RootView(watermarkService: WatermarkService())
    .modelContainer(container)
}
