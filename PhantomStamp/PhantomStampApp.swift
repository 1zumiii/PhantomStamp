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
    // 依赖注入，开发UI的时候用 PreviewWatermarkService()，正式发布用WatermarkService()
//    private let watermarkService: any WatermarkServiceProtocol = PreviewWatermarkService()
    private let watermarkService: any WatermarkServiceProtocol = WatermarkService()

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
        ImagePipelineTests.runAllBundledAndPrint()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(watermarkService: watermarkService)
        }
        .modelContainer(sharedModelContainer)
    }
}
