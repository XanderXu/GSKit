import AppKit
import Observation

@Observable
@MainActor
final class GSInputManager {
    static let shared = GSInputManager()

    var forward = false
    var backward = false
    var left = false
    var right = false
    var up = false
    var down = false

    var isRightDragging = false

    var rotateLeft = false
    var rotateRight = false

    var mouseDeltaX: Float = 0
    var mouseDeltaY: Float = 0
    private var eventMonitors: [Any] = []

    private init() {}

    func startMonitoring() {
        stopMonitoring()

        registerMonitor(for: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event, isDown: true) == true { return nil }
            return event
        }

        registerMonitor(for: .keyUp) { [weak self] event in
            if self?.handleKeyEvent(event, isDown: false) == true { return nil }
            return event
        }

        registerMonitor(for: .mouseMoved) { [weak self] event in
            guard self?.isRightDragging == true else { return event }
            self?.mouseDeltaX += Float(event.deltaX)
            self?.mouseDeltaY += Float(event.deltaY)
            return event
        }

        registerMonitor(for: .rightMouseDragged) { [weak self] event in
            self?.mouseDeltaX += Float(event.deltaX)
            self?.mouseDeltaY += Float(event.deltaY)
            return event
        }

        registerMonitor(for: .rightMouseDown) { [weak self] event in
            self?.isRightDragging = true
            return event
        }

        registerMonitor(for: .rightMouseUp) { [weak self] event in
            self?.isRightDragging = false
            return event
        }
    }

    func stopMonitoring() {
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
        clearInputs()
    }

    func resetDeltas() {
        mouseDeltaX = 0
        mouseDeltaY = 0
    }

    private func registerMonitor(
        for mask: NSEvent.EventTypeMask,
        handler: @escaping @MainActor (NSEvent) -> NSEvent?
    ) {
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler) {
            eventMonitors.append(monitor)
        }
    }

    private func clearInputs() {
        forward = false
        backward = false
        left = false
        right = false
        up = false
        down = false
        rotateLeft = false
        rotateRight = false
        isRightDragging = false
        resetDeltas()
    }

    private func handleKeyEvent(_ event: NSEvent, isDown: Bool) -> Bool {
        guard let chars = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        var handled = false

        switch chars {
        case "w", "z":
            forward = isDown
            handled = true
        case "s":
            backward = isDown
            handled = true
        case "q":
            left = isDown
            handled = true
        case "d":
            right = isDown
            handled = true
        case "e":
            up = isDown
            handled = true
        case "a":
            down = isDown
            handled = true
        default:
            break
        }

        if event.keyCode == 126 { forward = isDown; handled = true }
        if event.keyCode == 125 { backward = isDown; handled = true }
        if event.keyCode == 123 { rotateLeft = isDown; handled = true }
        if event.keyCode == 124 { rotateRight = isDown; handled = true }

        return handled
    }
}
