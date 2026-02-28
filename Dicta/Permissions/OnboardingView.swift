import SwiftUI
import AppKit

struct OnboardingView: View {
    @ObservedObject var model: SettingsModel
    let permissions: PermissionsManager
    let logger: DiagnosticsLogger
    let onComplete: () -> Void

    @State private var microphoneStatus: PermissionStatus = .notDetermined
    @State private var speechStatus: PermissionStatus = .notDetermined
    @State private var accessibilityStatus: PermissionStatus = .denied

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Dicta")
                .font(.system(size: 22, weight: .bold))
            Text("Dicta needs a few permissions to work everywhere. You can continue without them and enable later.")
                .font(.system(size: 13))

            permissionRow(title: "Microphone", status: microphoneStatus, actionTitle: "Grant", openSettings: {
                permissions.openSystemSettings(for: .microphone)
            }) {
                Task {
                    microphoneStatus = await permissions.requestMicrophone()
                }
            }

            permissionRow(title: "Speech Recognition", status: speechStatus, actionTitle: "Grant", openSettings: {
                permissions.openSystemSettings(for: .speech)
            }) {
                Task {
                    speechStatus = await permissions.requestSpeech()
                }
            }

            permissionRow(title: "Accessibility (optional)", status: accessibilityStatus, actionTitle: "Enable", openSettings: {
                permissions.openSystemSettings(for: .accessibility)
            }) {
                permissions.requestAccessibilityPrompt()
                accessibilityStatus = permissions.accessibilityStatus()
            }

            Spacer()

            HStack {
                Spacer()
                Button("Continue") {
                    model.hasCompletedOnboarding = true
                    onComplete()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .onAppear {
            microphoneStatus = permissions.microphoneStatus()
            speechStatus = permissions.speechStatus()
            accessibilityStatus = permissions.accessibilityStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            microphoneStatus = permissions.microphoneStatus()
            speechStatus = permissions.speechStatus()
            accessibilityStatus = permissions.accessibilityStatus()
        }
    }

    private func permissionRow(title: String, status: PermissionStatus, actionTitle: String, openSettings: @escaping () -> Void, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(statusLabel(for: status))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(actionTitle, action: action)
                .disabled(status == .granted)
            Button("Open Settings", action: openSettings)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
    }

    private func statusLabel(for status: PermissionStatus) -> String {
        switch status {
        case .granted: return "Granted"
        case .denied: return "Not granted"
        case .notDetermined: return "Not requested"
        }
    }
}
