import AppKit
import SwiftUI

@MainActor
final class PillHUDController: NSObject, NSWindowDelegate {
    private let settings: SettingsModel
    private let viewModel = PillHUDViewModel()
    private var panel: FloatingPillPanel?

    init(settings: SettingsModel) {
        self.settings = settings
        super.init()
    }

    func show(mode: PillHUDMode, waveformLevel: Double, theme: Theme) {
        let panel = ensurePanel()
        viewModel.state = PillHUDRenderState(mode: mode, waveformLevel: waveformLevel, theme: theme)
        if !panel.isVisible {
            restorePosition(from: settings)
            panel.orderFront(nil)
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func restorePosition(from settings: SettingsModel) {
        let panel = ensurePanel()
        if settings.hasCustomHUDPosition {
            let origin = NSPoint(x: settings.hudPositionX, y: settings.hudPositionY)
            panel.setFrameOrigin(clamp(origin: origin, size: panel.frame.size))
        } else {
            panel.setFrameOrigin(defaultOrigin(for: panel.frame.size))
        }
    }

    func resetPosition(in settings: SettingsModel) {
        settings.hasCustomHUDPosition = false
        let panel = ensurePanel()
        panel.setFrameOrigin(defaultOrigin(for: panel.frame.size))
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        let clamped = clamp(origin: panel.frame.origin, size: panel.frame.size)
        if clamped != panel.frame.origin {
            panel.setFrameOrigin(clamped)
        }
        settings.hudPositionX = clamped.x
        settings.hudPositionY = clamped.y
        settings.hasCustomHUDPosition = true
    }

    private func ensurePanel() -> FloatingPillPanel {
        if let panel {
            return panel
        }
        let panel = FloatingPillPanel(contentRect: NSRect(x: 0, y: 0, width: 170, height: 44),
                                      styleMask: [.nonactivatingPanel, .fullSizeContentView],
                                      backing: .buffered,
                                      defer: false)
        panel.delegate = self
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = NSHostingView(rootView: PillHUDView(viewModel: viewModel))
        self.panel = panel
        return panel
    }

    private func defaultOrigin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero
        let x = mouse.x - size.width / 2
        let y = mouse.y - size.height - 20
        return clamp(origin: NSPoint(x: x, y: y), in: visibleFrame, size: size)
    }

    private func clamp(origin: NSPoint, size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(NSRect(origin: origin, size: size)) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero
        return clamp(origin: origin, in: visibleFrame, size: size)
    }

    private func clamp(origin: NSPoint, in visibleFrame: NSRect, size: NSSize) -> NSPoint {
        let inset: CGFloat = 12
        let minX = visibleFrame.minX + inset
        let maxX = visibleFrame.maxX - size.width - inset
        let minY = visibleFrame.minY + inset
        let maxY = visibleFrame.maxY - size.height - inset
        let x = min(max(origin.x, minX), maxX)
        let y = min(max(origin.y, minY), maxY)
        return NSPoint(x: x, y: y)
    }
}

private final class FloatingPillPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
