//
//  SettingsView.swift
//  PhantomStamp
//

import SwiftUI

struct SettingsView: View {
    @Bindable var settingsStore: UserSettingsStore
    @State private var showAbout = false
    @State private var showDebugTools = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(AppConstants.Copy.Settings.toggleAutoLogWatermarkEmbed, isOn: $settingsStore.autoLogWatermarkEmbedToHistory)
                    Text(AppConstants.Copy.Settings.footnoteAutoLogWatermarkEmbed)
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

                // MARK: - Card-style rows (UI examples)

                Section {
                    settingsNavCard(
                        title: "Account",
                        subtitle: "Profile, subscription, and devices",
                        systemImage: "person.crop.circle",
                        tint: .blue
                    ) {
                        showAbout = true
                    }

                    settingsNavCard(
                        title: "Notifications",
                        subtitle: "Progress alerts and reminders",
                        systemImage: "bell.badge",
                        tint: .orange
                    ) {
                        // UI-only placeholder
                    }
                } header: {
                    Text("Quick links")
                } footer: {
                    Text("These are UI-only examples of card-style settings rows.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "bolt.heart")
                                .foregroundStyle(.purple)
                            Text("Tips")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                        Text("Keep watermark payload short for robustness. Use high-detail images for better concealment.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Info card")
                }

                Section {
                    Button {
                        showDebugTools.toggle()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "hammer.fill")
                                .foregroundStyle(.teal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Debug tools")
                                    .font(.subheadline.weight(.semibold))
                                Text("Run UI and algorithm smoke checks")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        // UI-only placeholder (no real destructive action).
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "trash")
                            Text("Clear demo data")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                    }
                } header: {
                    Text("Actions")
                } footer: {
                    Text("Destructive actions should always confirm before proceeding.")
                }

                Section {
                    VStack(spacing: 10) {
                        Button {
                            // UI-only placeholder
                        } label: {
                            Label("Send feedback", systemImage: "paperplane.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            // UI-only placeholder
                        } label: {
                            Label("Rate the app", systemImage: "star.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Buttons")
                }
            }
            .navigationTitle(AppConstants.Copy.Settings.navigationTitle)
            .alert("Account", isPresented: $showAbout) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("UI-only placeholder.")
            }
            .alert("Debug tools", isPresented: $showDebugTools) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("UI-only placeholder.")
            }
        }
    }

    private func settingsNavCard(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(tint)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView(settingsStore: UserSettingsStore())
}
