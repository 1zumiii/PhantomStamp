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
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        #if DEBUG
        print("[PhantomStamp] launch, marketing version = \(AppVersion.marketing)")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
