import SwiftUI

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
            Text("Dicta needs a few permissions to work everywhere.")
                .font(.system(size: 13))

            permissionRow(title: "Microphone", status: microphoneStatus, actionTitle: "Grant") {
                Task {
                    microphoneStatus = await permissions.requestMicrophone()
                }
            }

            permissionRow(title: "Speech Recognition", status: speechStatus, actionTitle: "Grant") {
                Task {
                    speechStatus = await permissions.requestSpeech()
                }
            }

            permissionRow(title: "Accessibility (optional)", status: accessibilityStatus, actionTitle: "Enable") {
                permissions.requestAccessibilityPrompt()
                accessibilityStatus = permissions.accessibilityStatus()
            }

            Spacer()

            HStack {
                Spacer()
                Button("Open System Settings") {
                    permissions.openSystemSettings(for: .microphone)
                }
                Button("Done") {
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
    }

    private func permissionRow(title: String, status: PermissionStatus, actionTitle: String, action: @escaping () -> Void) -> some View {
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
