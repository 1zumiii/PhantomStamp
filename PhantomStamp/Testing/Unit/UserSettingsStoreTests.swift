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
        let freshDefaults = makeDefaults()
        let freshStore = UserSettingsStore(defaults: freshDefaults)
        let freshPassed = freshStore.embeddingStrength == 10

        let legacyDefaults = makeDefaults()
        legacyDefaults.set(
            AppConstants.EmbeddingStrength.legacyBuggyDefault,
            forKey: AppConstants.UserDefaultsKey.embeddingStrength
        )
        let migratedStore = UserSettingsStore(defaults: legacyDefaults)
        let migrationPassed = migratedStore.embeddingStrength == 10

        let customDefaults = makeDefaults()
        customDefaults.set(4.5, forKey: AppConstants.UserDefaultsKey.embeddingStrength)
        let customStore = UserSettingsStore(defaults: customDefaults)
        let customPassed = customStore.embeddingStrength == 4.5

        let postMigrationDefaults = makeDefaults()
        postMigrationDefaults.set(
            true,
            forKey: AppConstants.UserDefaultsKey.embeddingStrengthDefault10Migration
        )
        postMigrationDefaults.set(1.0, forKey: AppConstants.UserDefaultsKey.embeddingStrength)
        let postMigrationStore = UserSettingsStore(defaults: postMigrationDefaults)
        let postMigrationPassed = postMigrationStore.embeddingStrength == 1.0

        let passed = freshPassed && migrationPassed && customPassed && postMigrationPassed
        print("[UserSettingsStoreTests] \(passed ? "PASS" : "FAIL") Embedding strength default/migration")
        #endif
    }

    private static func makeDefaults() -> UserDefaults {
        let suiteName = "phantomstamp.testing.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
