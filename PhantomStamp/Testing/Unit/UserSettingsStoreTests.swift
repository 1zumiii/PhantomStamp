//
//  UserSettingsStoreTests.swift
//  PhantomStamp
//
//  Lightweight DEBUG checks for settings defaults and one-time migrations.
//

import Foundation

@MainActor
enum UserSettingsStoreTests {
    static func runAllAndPrint() {
        #if DEBUG
        let defaults = makeDefaults()
        let store = UserSettingsStore(defaults: defaults)

        let defaultsPassed = store.autoLogWatermarkEmbedToHistory == AppConstants.SettingsDefault.autoLogWatermarkEmbed
            && store.exportQualityIndex == AppConstants.SettingsDefault.exportQualityIndex
            && store.saveToPhotos == AppConstants.SettingsDefault.saveToPhotos

        store.defaultWatermarkText = "Tester_01"
        store.exportQualityIndex = 2

        let persistenceStore = UserSettingsStore(defaults: defaults)
        let persistencePassed = persistenceStore.defaultWatermarkText == "Tester_01"
            && persistenceStore.exportQualityIndex == 2

        let passed = defaultsPassed && persistencePassed
        print("[UserSettingsStoreTests] \(passed ? "PASS" : "FAIL") Settings defaults/persistence")
        #endif
    }

    private static func makeDefaults() -> UserDefaults {
        let suiteName = "phantomstamp.testing.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
