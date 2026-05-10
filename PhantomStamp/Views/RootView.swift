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

  var body: some View {
    let items: [BottomNavItem<AnyHashable>] = [
      BottomNavItem(
        id: AnyHashable("watermark"),
        title: AppConstants.Copy.Tab.watermark,
        systemImage: AppConstants.Symbol.tabWatermark
      ) {
        NavigationStack {
          WatermarkInsertView(watermarkService: watermarkService, settingsStore: settingsStore)
        }
      },
      BottomNavItem(
        id: AnyHashable("history"),
        title: AppConstants.Copy.Tab.history,
        systemImage: AppConstants.Symbol.tabHistory
      ) {
        HistoryView(settingsStore: settingsStore)
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
      guard let svc = watermarkService as? WatermarkService else { return }
      svc.historyModelContext = modelContext
      svc.settingsStore = settingsStore
    }
  }
}

#Preview {
  let schema = Schema([HistoryEntry.self, WatermarkHistoryRecord.self])
  let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
  let container = try! ModelContainer(for: schema, configurations: [config])
  return RootView(watermarkService: WatermarkService())
    .modelContainer(container)
}
