import AppKit
import CoreGraphics
import ApplicationServices

/// Phase III fallback (branch A): map trackpad touches to global mouse events.
///
/// This is NOT Direct Touch: apps receive a mouse, not `NSTouch`. The only
/// goal is a working "trackpad as absolute pointing surface" prototype.
///
/// While active the hardware mouse is disassociated from the cursor
/// (`CGAssociateMouseAndMouseCursorPosition(0)`), so the physical trackpad
/// no longer fights the synthetic absolute position. Touches only move the
/// cursor; clicking is left to the system's physical/tap-to-click handling.
/// The association MUST be restored on deactivate/terminate; if the process
/// is force-killed the cursor can stay disassociated until the next login.
final class CGMouseController: @unchecked Sendable {
    var logHandler: ((String) -> Void)?

    private(set) var isEnabled = false
    private var activeTouch = false
    private var screenFrame: NSRect = .zero
    private var mainScreenMaxY: CGFloat = 0
    private var lastPoint: CGPoint = .zero
    private var lastPostedPoint: CGPoint = .zero
    private var smoothedPoint: CGPoint = .zero
    private var hasSmoothedPoint = false
    private var lastNormalized: CGPoint = .zero
    private var hasLastNormalized = false
    private var dragAnchor: CGPoint?
    private var isDragging = false
    private var buttonTimer: Timer?

    private let smoothingFactor: CGFloat = 0.35
    private let retouchStickyRadius: CGFloat = 0.012
    private let clickDragThreshold: CGFloat = 5

    @discardableResult
    func activate() -> Bool {
        if isEnabled { return true }

        let prompt = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(prompt) else {
            log("Accessibility permission required. Enable TouchScope in System Settings → Privacy & Security → Accessibility, then toggle CG mouse again.")
            return false
        }

        let cursor = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(cursor, $0.frame, false) })
                ?? NSScreen.main ?? NSScreen.screens.first else {
            log("no screen found")
            return false
        }
        screenFrame = screen.frame
        mainScreenMaxY = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        lastPostedPoint = CGPoint(x: cursor.x, y: mainScreenMaxY - cursor.y)

        let err = CGAssociateMouseAndMouseCursorPosition(0)
        guard err == .success else {
            log("CGAssociateMouseAndMouseCursorPosition(0) failed: \(err.rawValue)")
            return false
        }

        isEnabled = true
        activeTouch = false
        hasSmoothedPoint = false
        hasLastNormalized = false
        dragAnchor = nil
        isDragging = false
        buttonTimer?.invalidate()
        buttonTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.pollButton()
        }
        log("ACTIVE — screen \(Int(screenFrame.width))×\(Int(screenFrame.height)); hardware cursor disassociated; touch moves, click the trackpad to click")
        return true
    }

    func deactivate() {
        guard isEnabled else { return }
        activeTouch = false
        dragAnchor = nil
        isDragging = false
        buttonTimer?.invalidate()
        buttonTimer = nil
        let err = CGAssociateMouseAndMouseCursorPosition(1)
        isEnabled = false
        if err == .success {
            log("OFF — hardware cursor re-associated")
        } else {
            log("OFF — re-associate failed: \(err.rawValue)")
        }
    }

    func handle(multitouchFingerID: Int32, normalized: CGPoint, down: Bool) {
        guard isEnabled else { return }
        let mapped = map(normalized)

        if down {
            if !activeTouch {
                let point: CGPoint
                if hasSmoothedPoint, hasLastNormalized,
                   hypot(normalized.x - lastNormalized.x, normalized.y - lastNormalized.y) < retouchStickyRadius {
                    point = lastPoint
                } else {
                    point = mapped
                }
                activeTouch = true
                lastPoint = point
                smoothedPoint = point
                hasSmoothedPoint = true
                lastNormalized = normalized
                hasLastNormalized = true
                postMove(point)
            } else {
                let point = smoothed(mapped)
                lastPoint = point
                lastNormalized = normalized
                hasLastNormalized = true
                postMove(point)
            }
        } else if activeTouch {
            let point = smoothed(mapped)
            lastPoint = point
            lastNormalized = normalized
            hasLastNormalized = true
            postMove(point)
            activeTouch = false
        }
    }

    private func smoothed(_ target: CGPoint) -> CGPoint {
        let s = smoothedPoint
        let p = CGPoint(x: s.x + (target.x - s.x) * smoothingFactor,
                        y: s.y + (target.y - s.y) * smoothingFactor)
        smoothedPoint = p
        return p
    }

    private func map(_ n: CGPoint) -> CGPoint {
        let x = max(0, min(1, n.x))
        let y = max(0, min(1, n.y))
        let cocoaX = screenFrame.minX + x * screenFrame.width
        let cocoaY = screenFrame.minY + y * screenFrame.height
        return CGPoint(x: cocoaX, y: mainScreenMaxY - cocoaY)
    }

    private func postMove(_ p: CGPoint) {
        let buttonDown = CGEventSource.buttonState(.combinedSessionState, button: .left)

        if buttonDown {
            if dragAnchor == nil {
                dragAnchor = lastPostedPoint
                isDragging = false
            }
            if !isDragging {
                guard let anchor = dragAnchor,
                      hypot(p.x - anchor.x, p.y - anchor.y) >= clickDragThreshold else {
                    return
                }
                isDragging = true
            }
            if post(.leftMouseDragged, at: p) {
                lastPostedPoint = p
            }
        } else {
            dragAnchor = nil
            isDragging = false
            if post(.mouseMoved, at: p) {
                lastPostedPoint = p
            }
        }
    }

    @discardableResult
    private func post(_ type: CGEventType, at p: CGPoint) -> Bool {
        guard let e = CGEvent(mouseEventSource: nil, mouseType: type,
                              mouseCursorPosition: p, mouseButton: .left) else {
            log("CGEvent creation failed (type \(type.rawValue))")
            return false
        }
        e.setIntegerValueField(.mouseEventClickState, value: 1)
        e.post(tap: .cghidEventTap)
        return true
    }

    private func pollButton() {
        if !CGEventSource.buttonState(.combinedSessionState, button: .left) {
            dragAnchor = nil
            isDragging = false
        }
    }

    private func log(_ s: String) {
        logHandler?(s)
    }
}
