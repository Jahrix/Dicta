import Foundation
import AVFoundation

final class AudioSessionGuard {
    private var observer: NSObjectProtocol?
    var onConfigurationChange: (() -> Void)?

    func start() {
        stop()
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            self?.onConfigurationChange?()
        }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }
}
