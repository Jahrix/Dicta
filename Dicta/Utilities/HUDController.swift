import AppKit
import SwiftUI

final class HUDController {
    private var window: NSPanel?

    func show(text: String, mode: HUDMode = .neutral) {
        if window == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 64),
                                styleMask: [.nonactivatingPanel],
                                backing: .buffered,
                                defer: false)
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = false
            panel.contentView = NSHostingView(rootView: HUDView(text: text, mode: mode))
            window = panel
        }

        if let panel = window {
            if let hosting = panel.contentView as? NSHostingView<HUDView> {
                hosting.rootView = HUDView(text: text, mode: mode)
            }
            position(panel: panel)
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func position(panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let screenFrame = screen?.frame ?? .zero
        let x = min(max(screenFrame.minX + 12, mouse.x - panel.frame.width / 2), screenFrame.maxX - panel.frame.width - 12)
        let y = min(max(screenFrame.minY + 12, mouse.y - panel.frame.height - 20), screenFrame.maxY - panel.frame.height - 12)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

enum HUDMode {
    case listening
    case processing
    case neutral
    case error
}

struct HUDView: View {
    let text: String
    let mode: HUDMode

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .cornerRadius(12)
            HStack(spacing: 10) {
                indicator
                Text(text)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 200, minHeight: 56)
    }

    @ViewBuilder
    private var indicator: some View {
        switch mode {
        case .listening:
            WaveformIndicator(color: .white)
        case .processing:
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.white)
        case .neutral:
            Circle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 8, height: 8)
        }
    }
}

struct WaveformIndicator: View {
    let color: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    let phase = t * 2.2 + Double(index) * 0.6
                    let height = 6 + (sin(phase) + 1) * 6
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: height)
                }
            }
        }
        .frame(width: 22, height: 18)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
