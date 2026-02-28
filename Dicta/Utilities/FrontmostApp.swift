import Foundation
import AppKit

struct FrontmostApp: Sendable {
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let name: String

    static func captureCurrent(excludingBundleID: String?) -> FrontmostApp? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        if let excludingBundleID, app.bundleIdentifier == excludingBundleID {
            return nil
        }
        return FrontmostApp(bundleIdentifier: app.bundleIdentifier,
                            processIdentifier: app.processIdentifier,
                            name: app.localizedName ?? "Unknown")
    }
}
