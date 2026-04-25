import AppKit
import SwiftUI

@MainActor
final class PetWindowManager: NSObject, NSWindowDelegate {
    private let persistence: PetPersistence
    private weak var window: NSWindow?
    private var didApplyInitialConfiguration = false

    init(persistence: PetPersistence) {
        self.persistence = persistence
    }

    func attach(window: NSWindow) {
        guard self.window !== window else {
            return
        }

        self.window?.delegate = nil
        self.window = window
        window.delegate = self
        configure(window)
    }

    func recenter() {
        guard let window else {
            return
        }

        let origin = defaultOrigin(for: window.screen)
        let frame = NSRect(origin: origin, size: AppConstants.windowSize)
        window.setFrame(frame, display: true, animate: true)
        persistence.savePosition(frame.origin)
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        window?.level = enabled ? .screenSaver : .floating
    }

    private func configure(_ window: NSWindow) {
        window.styleMask = [.borderless]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = persistence.currentSnapshot.preferences.alwaysOnTop ? .screenSaver : .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false

        guard !didApplyInitialConfiguration else {
            return
        }

        didApplyInitialConfiguration = true
        let origin = persistence.currentSnapshot.position?.point ?? defaultOrigin(for: window.screen)
        let frame = NSRect(origin: origin, size: AppConstants.windowSize)
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        persistence.savePosition(window.frame.origin)
    }

    private func defaultOrigin(for screen: NSScreen?) -> CGPoint {
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        return CGPoint(
            x: visibleFrame.maxX - AppConstants.windowSize.width - AppConstants.windowMargin,
            y: visibleFrame.minY + AppConstants.windowMargin
        )
    }
}

struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = AccessorView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class AccessorView: NSView {
    var onResolve: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard let window else {
            return
        }

        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else {
                return
            }

            self.onResolve?(window)
        }
    }
}
