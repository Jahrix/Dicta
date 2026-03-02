import Foundation

@MainActor
final class HotkeyManager {
    var onBeginPushToTalk: (() -> Void)?
    var onEndPushToTalk: (() -> Void)?
    var onToggleLongDictation: (() -> Void)?
    var onInputMonitoringRequired: (() -> Void)?

    private let eventTapEngine = EventTapHotkeyEngine()
    private let carbonEngine = CarbonHotkeyEngine()
    private var pttBinding: Keybind?
    private var longBinding: Keybind?
    private var usingEventTap = false
    private var usingCarbonFallback = false

    init() {
        eventTapEngine.onEvent = { [weak self] event in
            self?.handle(event: event)
        }
        carbonEngine.onEvent = { [weak self] event in
            self?.handle(event: event)
        }
    }

    var currentConfigurationSummary: String {
        let ptt = pttBinding?.displayString ?? "unset"
        let long = longBinding?.displayString ?? "unset"
        let engines = [usingEventTap ? "eventTap" : nil, usingCarbonFallback ? "carbon" : nil]
            .compactMap { $0 }
            .joined(separator: ",")
        return "PTT=\(ptt), Long=\(long), engines=\(engines.isEmpty ? "none" : engines)"
    }

    func register(ptt: Keybind, long: Keybind) {
        unregister()
        pttBinding = ptt
        longBinding = long

        do {
            try eventTapEngine.start(bindings: [
                ManagedBinding(action: .pushToTalk, binding: ptt),
                ManagedBinding(action: .longDictation, binding: long)
            ])
            usingEventTap = true
        } catch {
            usingEventTap = false
            onInputMonitoringRequired?()
            if long.supportsCarbonHotkey {
                do {
                    try carbonEngine.start(bindings: [ManagedBinding(action: .longDictation, binding: long)])
                    usingCarbonFallback = true
                } catch {
                    usingCarbonFallback = false
                }
            }
        }
    }

    func unregister() {
        eventTapEngine.stop()
        carbonEngine.stop()
        usingEventTap = false
        usingCarbonFallback = false
    }

    func reloadIfNeeded() {
        guard let pttBinding, let longBinding else { return }
        register(ptt: pttBinding, long: longBinding)
    }

    private func handle(event: HotkeyEvent) {
        switch (event.action, event.phase) {
        case (.pushToTalk, .down):
            onBeginPushToTalk?()
        case (.pushToTalk, .up):
            onEndPushToTalk?()
        case (.longDictation, .down):
            onToggleLongDictation?()
        case (.longDictation, .up):
            break
        }
    }
}
