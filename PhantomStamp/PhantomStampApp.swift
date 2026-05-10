//
//  PhantomStampApp.swift
//  PhantomStamp
//
//  Created by Orion on 4/5/2026.
//

import SwiftData
import SwiftUI
import UIKit

@main
struct PhantomStampApp: App {
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var appNotificationDelegate

    private let watermarkService: any WatermarkServiceProtocol = WatermarkService()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            HistoryEntry.self,
            WatermarkHistoryRecord.self,
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
//        print(AppConstants.Debug.launchLogPrefix + AppVersion.marketing)
//        ImagePipelineTests.runAllBundledAndPrint()
//        MatrixOperationsTests.runAllAndPrint()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(watermarkService: watermarkService)
                .task {
                    await PhotoLibraryExporter.preflightAddOnlyAuthorizationIfNeeded()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
