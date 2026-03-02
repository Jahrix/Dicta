import Foundation

protocol HotkeyEngine: AnyObject {
    var onEvent: ((HotkeyEvent) -> Void)? { get set }
    var requiresInputMonitoring: Bool { get }
    func start(bindings: [ManagedBinding]) throws
    func stop()
}

enum HotkeyEngineError: Error, LocalizedError {
    case inputMonitoringRequired
    case registrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .inputMonitoringRequired:
            return "Input Monitoring permission is required for this keybind."
        case .registrationFailed(let message):
            return message
        }
    }
}
