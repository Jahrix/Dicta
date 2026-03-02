import SwiftUI
import AppKit

struct SettingsPage: View {
    @ObservedObject var settings: SettingsModel

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $settings.themeMode) {
                    ForEach(SettingsModel.ThemeMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("General") {
                Toggle("Show HUD", isOn: $settings.showHUD)
                Toggle("Verbose Logging", isOn: $settings.verboseLogging)
            }

            if usesLocalASR {
                Section("Speech Model") {
                    Picker("Model Tier", selection: $settings.selectedModelTier) {
                        ForEach(SpeechModelTier.allCases) { tier in
                            Text(tier.displayName).tag(tier)
                        }
                    }
                    Text(settings.selectedModelTier.shortDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let modelsURL = ModelCatalog.resolveModelDirectoryURL(settings: settings) {
                        Button("Open Models Folder") {
                            NSWorkspace.shared.open(modelsURL)
                        }
                    }
                }

                if settings.showLocalPrivacyCopy {
                    Section("Privacy") {
                        Text("Processed locally on your device. Your voice data never leaves your computer.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Section("Privacy") {
                    Text("Using Apple Speech.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }

            Section("System") {
                Button("Open Accessibility Settings") {
                    openSystemSettings(path: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                }
                Button("Open Microphone Settings") {
                    openSystemSettings(path: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
                }
                Button("Open Speech Recognition Settings") {
                    openSystemSettings(path: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
                }
            }
        }
        .padding(16)
    }

    private func openSystemSettings(path: String) {
        guard let url = URL(string: path) else { return }
        NSWorkspace.shared.open(url)
    }

    private var usesLocalASR: Bool {
        settings.transcriptionBackend == SettingsModel.TranscriptionBackend.localWhisperCpp.rawValue
    }
}

extension SettingsModel.ThemeMode {
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}
