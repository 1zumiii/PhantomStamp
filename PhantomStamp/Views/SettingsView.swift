//
//  SettingsView.swift
//  PhantomStamp
//

import SwiftUI

struct SettingsView: View {
    let watermarkService: any WatermarkServiceProtocol
    @Bindable var settingsStore: UserSettingsStore

    // Matches the light-purple accent in the prototype
    private let accentPurple = Color(red: 0.47, green: 0.38, blue: 0.85)
    // Matches the blue toggle ON colour in the prototype
    private let toggleBlue   = Color(red: 0.25, green: 0.52, blue: 0.96)

    var body: some View {
        NavigationStack {
            Form {
                pageHeaderSection
                generalSection
                watermarkDefaultsSection
                aboutSection
                testingSection
            }
            .navigationTitle(AppConstants.Copy.Settings.navigationTitle)
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Page Header

    private var pageHeaderSection: some View {
        Section {
            Text(AppConstants.Copy.Settings.pageSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
        }
        .listSectionSpacing(0)
    }

    // MARK: - General
    // Bindings:
    //   Save history   → $settingsStore.autoLogWatermarkEmbedToHistory   (existing)
    //   Show alerts    → $settingsStore.watermarkOperationNotificationsEnabled (existing)
    //   Save to Photos → $settingsStore.saveToPhotos                     (new)

    private var generalSection: some View {
        Section {
            toggleRow(
                systemImage: AppConstants.Symbol.settingsHistory,
                title: AppConstants.Copy.Settings.toggleSaveHistory,
                isOn: $settingsStore.autoLogWatermarkEmbedToHistory
            )
            toggleRow(
                systemImage: AppConstants.Symbol.settingsNotifications,
                title: AppConstants.Copy.Settings.toggleShowAlerts,
                isOn: $settingsStore.watermarkOperationNotificationsEnabled
            )
            toggleRow(
                systemImage: AppConstants.Symbol.settingsSaveToPhotos,
                title: AppConstants.Copy.Settings.toggleSaveToPhotos,
                isOn: $settingsStore.saveToPhotos
            )
        } header: {
            sectionHeader(
                title: AppConstants.Copy.Settings.sectionGeneral,
                systemImage: AppConstants.Symbol.settingsGeneral,
                tint: accentPurple
            )
        }
    }

    // MARK: - Watermark Defaults
    // Bindings:
    //   Default text       → $settingsStore.defaultWatermarkText  (new)
    //   Embedding strength → $settingsStore.embeddingStrength      (new, Double 0–100 step 25)
    //   Export quality     → $settingsStore.exportQualityIndex     (new, Int 0/1/2)

    private var watermarkDefaultsSection: some View {
        Section {
            watermarkTextFieldRow
            embeddingStrengthRow
            exportQualityRow
        } header: {
            sectionHeader(
                title: AppConstants.Copy.Settings.sectionWatermarkDefaults,
                systemImage: AppConstants.Symbol.settingsWatermarkDefaults,
                tint: .orange
            )
        } footer: {
            Text(AppConstants.Copy.Settings.footnoteWatermarkDefaults)
        }
    }

    private var watermarkTextFieldRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppConstants.Copy.Settings.labelDefaultWatermarkText)
                .font(.subheadline.weight(.medium))
            // Bound to settingsStore — persisted via AppUserDefault<String>
            TextField(
                AppConstants.Copy.Settings.placeholderWatermarkText,
                text: $settingsStore.defaultWatermarkText
            )
            .font(.subheadline)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
        .padding(.vertical, 4)
    }

    private var embeddingStrengthRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(AppConstants.Copy.Settings.labelEmbeddingStrength)
                    .font(.subheadline.weight(.medium))
                Spacer()
                // Reads live from settingsStore so the label always matches the slider
                Text("\(Int(settingsStore.embeddingStrength))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            // Bound to settingsStore — persisted via AppUserDefault<Double>
            Slider(
                value: $settingsStore.embeddingStrength,
                in: 0...100,
                step: 25
            )
            .tint(accentPurple)
        }
        .padding(.vertical, 4)
    }

    private var exportQualityRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppConstants.Copy.Settings.labelExportQuality)
                .font(.subheadline.weight(.medium))
            // Custom segmented control — bound to settingsStore.exportQualityIndex
            HStack(spacing: 0) {
                ForEach(
                    Array(AppConstants.Copy.Settings.exportQualityOptions.enumerated()),
                    id: \.offset
                ) { index, label in
                    let selected = index == settingsStore.exportQualityIndex
                    Button {
                        settingsStore.exportQualityIndex = index
                    } label: {
                        Text(label)
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background {
                                if selected {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(accentPurple)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Text(AppConstants.Copy.Settings.rowAppVersion)
                Spacer()
                Text(AppConstants.appVersionString)
                    .foregroundStyle(.secondary)
            }
            chevronRow(title: AppConstants.Copy.Settings.rowPrivacyStorage) {}
            chevronRow(title: AppConstants.Copy.Settings.rowLearnMore) {}
        } header: {
            sectionHeader(
                title: AppConstants.Copy.Settings.sectionAbout,
                systemImage: AppConstants.Symbol.settingsAbout,
                tint: .blue
            )
        }
    }

    // MARK: - Testing

    private var testingSection: some View {
        Section {
            NavigationLink {
                RobustnessTestingView(
                    watermarkService: watermarkService,
                    settingsStore: settingsStore
                )
            } label: {
                Text(AppConstants.Copy.Settings.rowRobustnessTests)
            }
        } header: {
            sectionHeader(
                title: AppConstants.Copy.Settings.sectionTesting,
                systemImage: AppConstants.Symbol.settingsTesting,
                tint: .green
            )
        }
    }

    // MARK: - Row helpers

    private func toggleRow(
        systemImage: String,
        title: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .center)
            Toggle(title, isOn: isOn)
                .font(.subheadline)
                .tint(toggleBlue)
        }
    }

    private func sectionHeader(title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint.opacity(0.15))
                }
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .textCase(nil)
        }
        .padding(.bottom, 4)
    }

    private func chevronRow(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView(watermarkService: WatermarkService(), settingsStore: UserSettingsStore())
}
