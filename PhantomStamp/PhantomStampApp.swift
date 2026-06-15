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
        if let svc = watermarkService as? WatermarkService {
            svc.modelContainer = sharedModelContainer
        }
        #if DEBUG
//        ImagePipelineTests.runAllBundledAndPrint()
//        MatrixOperationsTests.runAllAndPrint()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(watermarkService: watermarkService)
                .task {
                    await PhotoLibraryExporter.preflightAddOnlyAuthorizationIfNeeded()
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--run-local-damage-test") {
                        await WatermarkLocalDamageAttackTests.runAndPrint()
                    }
                    if ProcessInfo.processInfo.arguments.contains("--run-geometric-candidate-test") {
                        await WatermarkLocalDamageAttackTests.runRotationAndPrint()
                    }
                    if ProcessInfo.processInfo.arguments.contains("--run-downscaled-damage-test") {
                        await WatermarkLocalDamageAttackTests.runDownscaledScribbleAndPrint()
                    }
                    if ProcessInfo.processInfo.arguments.contains("--run-core-unit-tests") {
                        ExtractionAndVotingTests.runAllAndPrint()
                        DataProcessingTests.runAllAndPrint()
                        ImagePipelineTests.runAllBundledAndPrint()
                        UserSettingsStoreTests.runAllAndPrint()
                    }
                    #endif
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
