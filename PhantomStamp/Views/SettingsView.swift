//
//  SettingsView.swift
//  PhantomStamp
//

import SwiftUI

struct SettingsView: View {
    @Bindable var settingsStore: UserSettingsStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(AppConstants.Copy.Settings.toggleAutoLogWatermark, isOn: $settingsStore.autoLogWatermarkToHistory)
                    Text(AppConstants.Copy.Settings.footnoteAutoLogWatermark)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(AppConstants.Copy.Settings.sectionHistory)
                }

                Section {
                    Toggle(AppConstants.Copy.Settings.toggleCompactHistory, isOn: $settingsStore.compactHistoryList)
                    Text(AppConstants.Copy.Settings.footnoteCompactHistory)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(AppConstants.Copy.Settings.sectionAppearance)
                }
            }
            .navigationTitle(AppConstants.Copy.Settings.navigationTitle)
        }
    }
}

#Preview {
    SettingsView(settingsStore: UserSettingsStore())
}
