import AppKit
import SwiftUI

final class HUDController {
    private var window: NSPanel?

    func show(text: String) {
        if window == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
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
            panel.contentView = NSHostingView(rootView: HUDView(text: text))
            window = panel
        }

        if let panel = window {
            if let hosting = panel.contentView as? NSHostingView<HUDView> {
                hosting.rootView = HUDView(text: text)
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

struct HUDView: View {
    let text: String

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .cornerRadius(12)
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
        }
        .frame(width: 200, height: 60)
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
