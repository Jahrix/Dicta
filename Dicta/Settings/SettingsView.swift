import SwiftUI
import Speech

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    let permissions: PermissionsManager
    let logger: DiagnosticsLogger

    private let commonLocaleIdentifiers = [
        "en-US", "en-GB", "en-AU", "en-CA",
        "es-ES", "es-MX",
        "fr-FR", "fr-CA",
        "de-DE", "it-IT",
        "pt-BR", "pt-PT",
        "nl-NL", "sv-SE", "no-NO", "da-DK", "fi-FI",
        "pl-PL", "cs-CZ", "tr-TR", "ru-RU", "uk-UA",
        "ar-SA", "he-IL", "hi-IN",
        "ja-JP", "ko-KR", "zh-CN", "zh-TW"
    ]

    private var languageOptions: [String] {
        let supported = Set(SFSpeechRecognizer.supportedLocales().map { normalizeLocaleIdentifier($0.identifier) })
        let common = commonLocaleIdentifiers.filter { supported.contains($0) }
        let extras = supported.subtracting(common).sorted {
            displayName(for: $0) < displayName(for: $1)
        }
        let selected = normalizeLocaleIdentifier(model.languageIdentifier)
        var options = common + extras
        if !options.contains(selected) {
            options.insert(selected, at: 0)
        }
        return options
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dicta Settings")
                .font(.system(size: 20, weight: .bold))

            GroupBox(label: Text("Hotkey")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current: \(model.hotkey.displayString)")
                        .font(.system(size: 13, weight: .semibold))
                    HotkeyRecorderView(current: model.hotkey) { newHotkey in
                        model.hotkey = newHotkey
                    }
                    Text("Tip: Map Fn+Delete to F18 in Karabiner, then bind Dicta to F18.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }

            GroupBox(label: Text("Insertion")) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Mode", selection: $model.insertionMode) {
                        ForEach(InsertionMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    Toggle("Restore clipboard after paste", isOn: $model.restoreClipboard)
                }
                .padding(.top, 4)
            }

            GroupBox(label: Text("Transcription")) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Language", selection: $model.languageIdentifier) {
                        ForEach(languageOptions, id: \.self) { identifier in
                            Text(displayName(for: identifier))
                                .tag(identifier)
                        }
                    }
                    Text("Common languages are listed first. Dicta picks the closest supported locale.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Toggle("Prefer on-device recognition", isOn: $model.preferOnDevice)

                    HStack {
                        Text("Max recording length")
                        Spacer()
                        Stepper(value: $model.maxRecordingSeconds, in: 10...180, step: 5) {
                            Text("\(Int(model.maxRecordingSeconds))s")
                        }
                    }

                    HStack {
                        Text("Transcription timeout")
                        Spacer()
                        Stepper(value: $model.transcriptionTimeoutSeconds, in: 5...60, step: 5) {
                            Text("\(Int(model.transcriptionTimeoutSeconds))s")
                        }
                    }

                    HStack {
                        Text("Insertion timeout")
                        Spacer()
                        Stepper(value: $model.insertionTimeoutSeconds, in: 1...10, step: 1) {
                            Text("\(Int(model.insertionTimeoutSeconds))s")
                        }
                    }

                    HStack {
                        Text("Silence timeout")
                        Spacer()
                        Stepper(value: $model.silenceTimeoutSeconds, in: 1...10, step: 1) {
                            Text("\(Int(model.silenceTimeoutSeconds))s")
                        }
                    }

                    HStack {
                        Text("Speech detection threshold")
                        Spacer()
                        Slider(value: $model.vadThresholdRMS, in: 0.005...0.05, step: 0.001)
                            .frame(width: 160)
                        Text(String(format: "%.3f", model.vadThresholdRMS))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Speech grace period")
                        Spacer()
                        Stepper(value: $model.vadGraceSeconds, in: 0.2...2.0, step: 0.2) {
                            Text(String(format: "%.1fs", model.vadGraceSeconds))
                        }
                    }

                    Button("Apply Noisy Room Preset") {
                        model.silenceTimeoutSeconds = 5.0
                        model.vadThresholdRMS = 0.025
                        model.vadGraceSeconds = 1.0
                    }
                    .buttonStyle(.link)
                }
                .padding(.top, 4)
            }

            GroupBox(label: Text("Interface")) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Show floating HUD", isOn: $model.showHUD)
                    Toggle("Verbose logging", isOn: $model.verboseLogging)
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 520)
        .onAppear {
            let normalized = normalizeLocaleIdentifier(model.languageIdentifier)
            if normalized != model.languageIdentifier {
                model.languageIdentifier = normalized
            }
        }
    }

    private func displayName(for identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    private func normalizeLocaleIdentifier(_ identifier: String) -> String {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-")
        let parts = normalized.split(separator: "-")
        guard parts.count >= 2 else { return normalized }
        let language = parts[0].lowercased()
        let region = parts[1].uppercased()
        return "\(language)-\(region)"
    }
}
