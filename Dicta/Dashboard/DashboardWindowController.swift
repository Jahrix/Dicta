import AppKit
import SwiftUI

@MainActor
final class DashboardWindowController {
    static let shared = DashboardWindowController()

    private var window: NSWindow?
    private var settingsModel: SettingsModel?
    private let store = AppDataStore()

    private init() {}

    func configure(settings: SettingsModel) {
        self.settingsModel = settings
    }

    func show() {
        if window == nil {
            let settings = settingsModel ?? SettingsModel()
            let view = DashboardView(settings: settings)
                .environmentObject(store)
            let hostingView = NSHostingView(rootView: view)

            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered,
                                  defer: false)
            window.title = "Dicta"
            window.contentView = hostingView
            window.center()
            window.setFrameAutosaveName("DictaDashboardWindow")
            window.isReleasedWhenClosed = false
            self.window = window
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
