import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var model: SettingsModel
    let permissions: PermissionsManager
    let logger: DiagnosticsLogger
    let selectPermissions: Bool

    @State private var microphoneStatus: PermissionStatus = .notDetermined
    @State private var speechStatus: PermissionStatus = .notDetermined
    @State private var accessibilityStatus: PermissionStatus = .denied

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Diagnostics")
                .font(.system(size: 20, weight: .bold))

            GroupBox(label: Text("Permissions")) {
                VStack(alignment: .leading, spacing: 10) {
                    permissionRow(title: "Microphone", status: microphoneStatus) {
                        permissions.openSystemSettings(for: .microphone)
                    }
                    permissionRow(title: "Speech Recognition", status: speechStatus) {
                        permissions.openSystemSettings(for: .speech)
                    }
                    permissionRow(title: "Accessibility", status: accessibilityStatus) {
                        permissions.openSystemSettings(for: .accessibility)
                    }
                }
                .padding(.top, 4)
            }

            GroupBox(label: Text("Export")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Export a debug bundle with logs, recent audio, and settings.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Button("Export Debug Bundle") {
                        Task { await DiagnosticsManager.shared.exportDebugBundle() }
                    }
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 520)
        .onAppear {
            refresh()
        }
    }

    private func refresh() {
        microphoneStatus = permissions.microphoneStatus()
        speechStatus = permissions.speechStatus()
        accessibilityStatus = permissions.accessibilityStatus()
    }

    private func permissionRow(title: String, status: PermissionStatus, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(statusLabel(for: status))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Open System Settings", action: action)
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
