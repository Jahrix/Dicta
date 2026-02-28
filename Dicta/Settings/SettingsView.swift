import SwiftUI
import Speech

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    let permissions: PermissionsManager
    let logger: DiagnosticsLogger

    private var locales: [Locale] {
        SFSpeechRecognizer.supportedLocales().sorted { $0.identifier < $1.identifier }
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
                        ForEach(locales, id: \.identifier) { locale in
                            Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                                .tag(locale.identifier)
                        }
                    }
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
    }
}
