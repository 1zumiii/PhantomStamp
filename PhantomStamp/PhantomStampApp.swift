//
//  PhantomStampApp.swift
//  PhantomStamp
//
//  Created by Orion on 4/5/2026.
//

import SwiftData
import SwiftUI

@main
struct PhantomStampApp: App {
    /// 集成阶段切换实现：`DEBUG` 使用 Mock 便于 UI 联调，`Release` 使用算法实现。
    private let watermarkService: any WatermarkServiceProtocol = {
        #if DEBUG
        MockWatermarkService()
        #else
        WatermarkService()
        #endif
    }()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            HistoryEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError(AppConstants.ErrorMessage.modelContainerPrefix + "\(error)")
        }
    }()

    init() {
        #if DEBUG
        print(AppConstants.Debug.launchLogPrefix + AppVersion.marketing)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(watermarkService: watermarkService)
        }
        .modelContainer(sharedModelContainer)
    }
}
