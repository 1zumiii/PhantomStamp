//
//  AppUserDefault.swift
//  PhantomStamp
//
//  Property wrapper for plist-backed UserDefaults values: typed read/write, defaults,
//  and optional one-time migration from a legacy key (then legacy is removed).
//
//  Note: `@Observable` types cannot stack another `@propertyWrapper` on the same stored
//  property. Hold `AppUserDefault` behind `@ObservationIgnored` and expose a computed
//  `var` using Observation `access` / `withMutation` (see `UserSettingsStore`).
//

import Foundation

@propertyWrapper
struct AppUserDefault<Value> {
    let key: String
    let legacyKey: String?
    let defaultValue: Value
    let defaults: UserDefaults

    init(
        key: String,
        legacyKey: String? = nil,
        defaultValue: Value,
        defaults: UserDefaults = .standard
    ) {
        self.key = key
        self.legacyKey = legacyKey
        self.defaultValue = defaultValue
        self.defaults = defaults
    }

    var wrappedValue: Value {
        get { Self.read(key: key, legacyKey: legacyKey, defaultValue: defaultValue, defaults: defaults) }
        set { Self.write(newValue, key: key, defaults: defaults) }
    }

    // MARK: - Read path

    private static func read(
        key: String,
        legacyKey: String?,
        defaultValue: Value,
        defaults: UserDefaults
    ) -> Value {
        if let v = typedValue(defaults: defaults, key: key, template: defaultValue) {
            return v
        }
        if let legacy = legacyKey,
           let migrated = typedValue(defaults: defaults, key: legacy, template: defaultValue) {
            write(migrated, key: key, defaults: defaults)
            defaults.removeObject(forKey: legacy)
            return migrated
        }
        return defaultValue
    }

    /// Returns a value only when the key exists (`object(forKey:)` is non-nil), so `false` / `0` are not confused with “missing”.
    private static func typedValue(defaults: UserDefaults, key: String, template: Value) -> Value? {
        guard defaults.object(forKey: key) != nil else { return nil }

        let templateAny = template as Any
        if templateAny is Bool {
            return defaults.bool(forKey: key) as? Value
        }
        if templateAny is Int {
            return defaults.integer(forKey: key) as? Value
        }
        if templateAny is Double {
            return defaults.double(forKey: key) as? Value
        }
        if templateAny is String {
            return defaults.string(forKey: key) as? Value
        }
        if templateAny is Data {
            return defaults.data(forKey: key) as? Value
        }
        return defaults.object(forKey: key) as? Value
    }

    // MARK: - Write path

    private static func write(_ value: Value, key: String, defaults: UserDefaults) {
        switch value as Any {
        case let v as Bool:
            defaults.set(v, forKey: key)
        case let v as Int:
            defaults.set(v, forKey: key)
        case let v as Double:
            defaults.set(v, forKey: key)
        case let v as String:
            defaults.set(v, forKey: key)
        case let v as Data:
            defaults.set(v, forKey: key)
        case let v as Float:
            defaults.set(v, forKey: key)
        default:
            defaults.set(value as Any, forKey: key)
        }
    }
}
