import SwiftUI
import AppKit

struct HotkeyRecorderView: View {
    let current: Hotkey
    let onChange: (Hotkey) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 12) {
            Text(current.displayString)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .windowBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

            Button(isRecording ? "Press shortcut…" : "Record Shortcut") {
                toggleRecording()
            }
        }
        .onDisappear {
            stopMonitoring()
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopMonitoring()
        } else {
            startMonitoring()
        }
        isRecording.toggle()
    }

    private func startMonitoring() {
        stopMonitoring()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let flags = ModifierFlags.from(eventFlags: event.modifierFlags)
            let keyCode = UInt32(event.keyCode)
            let isFunctionKey = KeyCodeTranslator.shared.string(for: keyCode).hasPrefix("F")
            if flags.isEmpty && !isFunctionKey {
                return nil
            }
            onChange(Hotkey(keyCode: keyCode, modifiers: flags.rawValue))
            stopMonitoring()
            isRecording = false
            return nil
        }
    }

    private func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
