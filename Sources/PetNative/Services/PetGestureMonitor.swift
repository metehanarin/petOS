import AppKit
import Foundation

extension NSEvent {
    /// Safely returns the set of touches associated with the event.
    /// Calling `touches(matching:in:)` on certain event types (like non-trackpad ScrollWheel)
    /// can cause an assertion failure/exception in AppKit.
    func allTouches() -> Set<NSTouch> {
        let touchTypes: [NSEvent.EventType] = [
            .gesture, .magnify, .rotate, .swipe, 
            .beginGesture, .endGesture, .smartMagnify,
            .pressure, .tabletPoint, .tabletProximity
        ]
        
        // ScrollWheel events only support touches if they come from a trackpad (have a phase)
        if type == .scrollWheel {
            if phase != [] || momentumPhase != [] {
                return touches(matching: .any, in: nil)
            }
            return []
        }
        
        if touchTypes.contains(type) {
            return touches(matching: .any, in: nil)
        }
        
        return []
    }
}

@MainActor
final class PetGestureMonitor {
    typealias Handler = @MainActor () -> Void

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private let onSwipeDown: Handler
    private var panFingerCount = 0
    private var panAccumulatedDeltaY: CGFloat = 0

    init(onSwipeDown: @escaping Handler) {
        self.onSwipeDown = onSwipeDown
    }

    func start() {
        guard localMonitor == nil, globalMonitor == nil else {
            return
        }

        let mask: NSEvent.EventTypeMask = [.swipe, .scrollWheel]

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event: event, source: "local")
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event: event, source: "global")
        }

        NSLog("[PetNative] PetGestureMonitor started; local=\(localMonitor != nil) global=\(globalMonitor != nil)")
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        localMonitor = nil
        globalMonitor = nil
    }

    private func handle(event: NSEvent, source: String) {
        switch event.type {
        case .swipe:
            NSLog("[PetNative] \(source) .swipe deltaY=\(event.deltaY)")
            if event.deltaY == -1 {
                onSwipeDown()
            }
        case .scrollWheel:
            let touches = event.allTouches().count
            if touches > 0 || event.phase == .began || event.phase == .ended {
                NSLog("[PetNative] \(source) .scrollWheel touches=\(touches) deltaY=\(event.scrollingDeltaY) phase=\(event.phase.rawValue)")
            }
            handleScroll(event: event)
        default:
            break
        }
    }

    private func handleScroll(event: NSEvent) {
        let touches = event.allTouches().count

        switch event.phase {
        case .began:
            panFingerCount = touches
            panAccumulatedDeltaY = 0
        case .changed:
            if touches > panFingerCount {
                panFingerCount = touches
            }
            panAccumulatedDeltaY += event.scrollingDeltaY
        case .ended:
            NSLog("[PetNative] pan ended fingers=\(panFingerCount) totalDeltaY=\(panAccumulatedDeltaY)")
            if panFingerCount >= 3, panAccumulatedDeltaY < -40 {
                onSwipeDown()
            }
            panFingerCount = 0
            panAccumulatedDeltaY = 0
        case .cancelled:
            panFingerCount = 0
            panAccumulatedDeltaY = 0
        default:
            break
        }
    }
}
