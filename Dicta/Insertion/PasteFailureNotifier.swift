import Foundation

final class PasteFailureNotifier {
    static let shared = PasteFailureNotifier()
    private var didNotify = false

    private init() {}

    func notifyClipboardOnlyOnce() {
        guard !didNotify else { return }
        didNotify = true
        NotificationPresenter.shared.notify(title: "Paste Failed",
                                           body: "Paste failed - transcript copied to clipboard. Use 'Paste Again' from the menu.")
    }
}
