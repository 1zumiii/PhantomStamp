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

    init(defaults: UserDefaults = .standard) {
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
    }
}
