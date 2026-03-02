import SwiftUI
import Speech
import AppKit

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    let permissions: PermissionsManager
    let logger: DiagnosticsLogger

    @State private var duplicateWarning: String?

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
        let extras = supported.subtracting(common).sorted { displayName(for: $0) < displayName(for: $1) }
        let selected = normalizeLocaleIdentifier(model.languageIdentifier)
        var options = common + extras
        if !options.contains(selected) {
            options.insert(selected, at: 0)
        }
        return options
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Dicta Settings")
                    .font(.system(size: 20, weight: .bold))

                hotkeysSection
                themeSection
                hudSection
                inputMonitoringSection
                insertionSection
                transcriptionSection
                interfaceSection
                permissionsSection
            }
            .padding(20)
        }
        .frame(minWidth: 560, minHeight: 680)
        .tint(model.themeTintColor)
        .onAppear {
            let normalized = normalizeLocaleIdentifier(model.languageIdentifier)
            if normalized != model.languageIdentifier {
                model.languageIdentifier = normalized
            }
        }
    }

    private var hotkeysSection: some View {
        GroupBox(label: Text("Keybinds")) {
            VStack(alignment: .leading, spacing: 12) {
                keybindRow(title: "Push-to-Talk", current: model.pushToTalkKeybind) { newBinding in
                    applyPushToTalk(newBinding)
                }

                keybindRow(title: "Long Dictation", current: model.longDictationKeybind) { newBinding in
                    applyLongDictation(newBinding)
                }

                HStack(spacing: 8) {
                    Text("Quick presets")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Button("⌥Space") { applyPushToTalk(.defaultPushToTalk) }
                    Button("⌥⇧Space") { applyLongDictation(.defaultLongDictation) }
                    Button("Right Shift") { applyLongDictation(.rightShift) }
                    Button("Left Shift") { applyPushToTalk(.leftShift) }
                }
                .buttonStyle(.bordered)

                if let duplicateWarning {
                    Text(duplicateWarning)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                }
            }
            .padding(.top, 4)
        }
    }

    private var themeSection: some View {
        GroupBox(label: Text("Theme")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Picker("Preset", selection: $model.selectedThemeID) {
                        ForEach(RoyalThemes.all) { theme in
                            Text(theme.name).tag(theme.id)
                        }
                    }
                    .frame(maxWidth: 260)

                    ThemeSwatch(theme: model.effectiveTheme)
                }

                Toggle("Use custom accent hex", isOn: $model.customThemeEnabled)

                HStack(spacing: 12) {
                    TextField("#4F6DFF", text: $model.customThemeHex)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                    ThemeSwatch(theme: model.effectiveTheme)
                }

                if model.customThemeEnabled && !model.customThemeHex.isEmpty && !model.customThemeHexIsValid {
                    Text("Enter a valid 6-digit hex color like #4F6DFF.")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
            }
            .padding(.top, 4)
        }
    }

    private var hudSection: some View {
        GroupBox(label: Text("HUD")) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Show waveform pill HUD", isOn: $model.showHUD)
                Button("Reset HUD Position") {
                    model.hasCustomHUDPosition = false
                    model.hudPositionX = 0
                    model.hudPositionY = 0
                }
            }
            .padding(.top, 4)
        }
    }

    private var inputMonitoringSection: some View {
        GroupBox(label: Text("Input Monitoring")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Standalone keys and hold-to-talk use Input Monitoring on macOS.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Button("Open Input Monitoring Settings") {
                    openInputMonitoringSettings()
                }
            }
            .padding(.top, 4)
        }
    }

    private var insertionSection: some View {
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
    }

    private var transcriptionSection: some View {
        GroupBox(label: Text("Transcription")) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Language", selection: $model.languageIdentifier) {
                    ForEach(languageOptions, id: \.self) { identifier in
                        Text(displayName(for: identifier)).tag(identifier)
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
                        .frame(width: 180)
                    Text(String(format: "%.3f", model.vadThresholdRMS))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                Text("Higher values ignore background noise but may miss quiet speech.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                HStack {
                    Text("Speech grace period")
                    Spacer()
                    Stepper(value: $model.vadGraceSeconds, in: 0.2...2.0, step: 0.2) {
                        Text(String(format: "%.1fs", model.vadGraceSeconds))
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var interfaceSection: some View {
        GroupBox(label: Text("Interface")) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Verbose logging", isOn: $model.verboseLogging)
            }
            .padding(.top, 4)
        }
    }

    private var permissionsSection: some View {
        GroupBox(label: Text("Permissions")) {
            VStack(alignment: .leading, spacing: 8) {
                permissionRow(title: "Microphone", status: permissions.microphoneStatus()) {
                    permissions.openSystemSettings(for: .microphone)
                }
                permissionRow(title: "Speech Recognition", status: permissions.speechStatus()) {
                    permissions.openSystemSettings(for: .speech)
                }
                permissionRow(title: "Accessibility", status: permissions.accessibilityStatus()) {
                    permissions.openSystemSettings(for: .accessibility)
                }
            }
            .padding(.top, 4)
        }
    }

    private func keybindRow(title: String, current: Keybind, onChange: @escaping (Keybind) -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .frame(width: 120, alignment: .leading)
            KeybindRecorderView(current: current, onChange: onChange)
            Spacer(minLength: 0)
        }
    }

    private func permissionRow(title: String, status: PermissionStatus, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(statusLabel(for: status))
                .foregroundColor(.secondary)
            Button("Open Settings", action: action)
        }
    }

    private func applyPushToTalk(_ binding: Keybind) {
        guard binding != model.longDictationKeybind else {
            duplicateWarning = "Push-to-Talk and Long Dictation cannot use the same binding."
            return
        }
        duplicateWarning = nil
        model.pushToTalkKeybind = binding
    }

    private func applyLongDictation(_ binding: Keybind) {
        guard binding != model.pushToTalkKeybind else {
            duplicateWarning = "Push-to-Talk and Long Dictation cannot use the same binding."
            return
        }
        duplicateWarning = nil
        model.longDictationKeybind = binding
    }

    private func statusLabel(for status: PermissionStatus) -> String {
        switch status {
        case .granted: return "Granted"
        case .denied: return "Not granted"
        case .notDetermined: return "Not requested"
        }
    }

    private func displayName(for identifier: String) -> String {
        let locale = Locale(identifier: identifier)
        return locale.localizedString(forIdentifier: identifier) ?? identifier
    }

    private func normalizeLocaleIdentifier(_ identifier: String) -> String {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-")
        let parts = normalized.split(separator: "-")
        guard parts.count >= 2 else { return normalized }
        return "\(parts[0].lowercased())-\(parts[1].uppercased())"
    }

    private func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct ThemeSwatch: View {
    let theme: Theme

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ThemeManager.swiftUIColor(from: theme.primaryHex))
                .frame(width: 16, height: 16)
            Circle()
                .fill(ThemeManager.swiftUIColor(from: theme.waveformHex))
                .frame(width: 16, height: 16)
            Circle()
                .fill(ThemeManager.swiftUIColor(from: theme.backgroundHex))
                .frame(width: 16, height: 16)
        }
    }
}
