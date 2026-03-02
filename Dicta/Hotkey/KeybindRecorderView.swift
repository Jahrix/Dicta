import SwiftUI

struct KeybindRecorderView: View {
    let current: Keybind
    let onChange: (Keybind) -> Void

    @StateObject private var recorder = KeybindRecorder()

    var body: some View {
        HStack(spacing: 12) {
            Text(current.displayString)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))

            Button(recorder.isRecording ? "Cancel" : "Record") {
                if recorder.isRecording {
                    recorder.stop()
                } else {
                    recorder.start { newBinding in
                        onChange(newBinding)
                    }
                }
            }

            if recorder.isRecording {
                Text(recorder.helperText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .onDisappear {
            recorder.stop()
        }
    }
}
