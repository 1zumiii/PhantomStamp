//
//  UserSettingsStore.swift
//  PhantomStamp
//
//  Preference surface for SwiftUI. `@Observable` does not compose with a second
//  `@propertyWrapper` on the same declaration, so each `AppUserDefault` lives in
//  `@ObservationIgnored` storage and the public `Bool` is a computed property that
//  forwards Observation `access` / `withMutation` for `$settings.toggle` bindings.
//

import Foundation
import Observation

@MainActor
@Observable
final class UserSettingsStore {

    // MARK: - Existing properties (unchanged)

    @ObservationIgnored
    private var _autoLogWatermarkEmbedToHistory: AppUserDefault<Bool>

    @ObservationIgnored
    private var _compactHistoryList: AppUserDefault<Bool>

    @ObservationIgnored
    private var _watermarkOperationNotificationsEnabled: AppUserDefault<Bool>

    var autoLogWatermarkEmbedToHistory: Bool {
        get {
            access(keyPath: \.autoLogWatermarkEmbedToHistory)
            return _autoLogWatermarkEmbedToHistory.wrappedValue
        }
        set {
            withMutation(keyPath: \.autoLogWatermarkEmbedToHistory) {
                _autoLogWatermarkEmbedToHistory.wrappedValue = newValue
            }
        }
    }

    var compactHistoryList: Bool {
        get {
            access(keyPath: \.compactHistoryList)
            return _compactHistoryList.wrappedValue
        }
        set {
            withMutation(keyPath: \.compactHistoryList) {
                _compactHistoryList.wrappedValue = newValue
            }
        }
    }

    var watermarkOperationNotificationsEnabled: Bool {
        get {
            access(keyPath: \.watermarkOperationNotificationsEnabled)
            return _watermarkOperationNotificationsEnabled.wrappedValue
        }
        set {
            withMutation(keyPath: \.watermarkOperationNotificationsEnabled) {
                _watermarkOperationNotificationsEnabled.wrappedValue = newValue
            }
        }
    }

    // MARK: - Watermark Defaults (new — added for SettingsView)

    @ObservationIgnored
    private var _defaultWatermarkText: AppUserDefault<String>

    @ObservationIgnored
    private var _embeddingStrength: AppUserDefault<Double>

    @ObservationIgnored
    private var _exportQualityIndex: AppUserDefault<Int>

    @ObservationIgnored
    private var _saveToPhotos: AppUserDefault<Bool>

    var defaultWatermarkText: String {
        get {
            access(keyPath: \.defaultWatermarkText)
            return _defaultWatermarkText.wrappedValue
        }
        set {
            withMutation(keyPath: \.defaultWatermarkText) {
                _defaultWatermarkText.wrappedValue = newValue
            }
        }
    }

    var embeddingStrength: Double {
        get {
            access(keyPath: \.embeddingStrength)
            return _embeddingStrength.wrappedValue
        }
        set {
            withMutation(keyPath: \.embeddingStrength) {
                _embeddingStrength.wrappedValue = newValue
            }
        }
    }

    var exportQualityIndex: Int {
        get {
            access(keyPath: \.exportQualityIndex)
            return _exportQualityIndex.wrappedValue
        }
        set {
            withMutation(keyPath: \.exportQualityIndex) {
                _exportQualityIndex.wrappedValue = newValue
            }
        }
    }

    var saveToPhotos: Bool {
        get {
            access(keyPath: \.saveToPhotos)
            return _saveToPhotos.wrappedValue
        }
        set {
            withMutation(keyPath: \.saveToPhotos) {
                _saveToPhotos.wrappedValue = newValue
            }
        }
    }

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        // Existing
        _autoLogWatermarkEmbedToHistory = AppUserDefault(
            key: AppConstants.UserDefaultsKey.autoLogWatermarkEmbed,
            legacyKey: AppConstants.UserDefaultsKey.legacyAutoLogWatermarkEmbed,
            defaultValue: AppConstants.SettingsDefault.autoLogWatermarkEmbed,
            defaults: defaults
        )
        _compactHistoryList = AppUserDefault(
            key: AppConstants.UserDefaultsKey.compactHistoryList,
            defaultValue: AppConstants.SettingsDefault.compactHistoryList,
            defaults: defaults
        )
        _watermarkOperationNotificationsEnabled = AppUserDefault(
            key: AppConstants.UserDefaultsKey.watermarkOperationNotifications,
            defaultValue: AppConstants.SettingsDefault.watermarkOperationNotifications,
            defaults: defaults
        )
        // New
        _defaultWatermarkText = AppUserDefault(
            key: AppConstants.UserDefaultsKey.defaultWatermarkText,
            defaultValue: AppConstants.SettingsDefault.defaultWatermarkText,
            defaults: defaults
        )
        _embeddingStrength = AppUserDefault(
            key: AppConstants.UserDefaultsKey.embeddingStrength,
            defaultValue: AppConstants.SettingsDefault.embeddingStrength,
            defaults: defaults
        )
        _exportQualityIndex = AppUserDefault(
            key: AppConstants.UserDefaultsKey.exportQualityIndex,
            defaultValue: AppConstants.SettingsDefault.exportQualityIndex,
            defaults: defaults
        )
        _saveToPhotos = AppUserDefault(
            key: AppConstants.UserDefaultsKey.saveToPhotos,
            defaultValue: AppConstants.SettingsDefault.saveToPhotos,
            defaults: defaults
        )
    }
}
