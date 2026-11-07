import AppKit

struct LockedWindow {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let bounds: CGRect
}

@MainActor
final class WindowLockController {
    var onTargetChanged: ((CGRect?) -> Void)?
    var onTargetLost: ((String) -> Void)?

    private(set) var target: LockedWindow?
    var isActive: Bool { target != nil }

    private var refreshTimer: Timer?
    private let outlineView = WindowOutlineView()
    private let outlineWindow: WindowOutlineWindow

    private let excludedOwners: Set<String> = [
        "Window Server",
        "Dock",
        "Control Center",
        "Notification Center",
        "TextInputMenuAgent",
        "TouchScope",
    ]

    init() {
        outlineWindow = WindowOutlineWindow()
        outlineWindow.contentView = outlineView
    }

    @discardableResult
    func lock(at cgPoint: CGPoint) -> Bool {
        guard let found = findWindow(at: cgPoint) else {
            return false
        }

        target = found
        updateOutline()
        startRefreshing()
        onTargetChanged?(found.bounds)
        return true
    }

    func unlock() {
        guard target != nil else { return }
        target = nil
        stopRefreshing()
        outlineWindow.orderOut(nil)
        onTargetChanged?(nil)
    }

    @discardableResult
    func switchToFrontmostWindow(ofPID pid: pid_t) -> Bool {
        guard isActive, pid != getpid(), let found = findFrontmostWindow(ofPID: pid) else {
            return false
        }
        if target?.windowID == found.windowID {
            return false
        }

        target = found
        updateOutline()
        startRefreshing()
        onTargetChanged?(found.bounds)
        return true
    }

    func refresh() {
        guard let currentTarget = target else { return }

        guard let current = findWindow(id: currentTarget.windowID) else {
            unlock()
            onTargetLost?("target window disappeared")
            return
        }

        if current.bounds != currentTarget.bounds || current.ownerPID != currentTarget.ownerPID {
            target = current
            onTargetChanged?(current.bounds)
        }

        updateOutline()
    }

    private func startRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func updateOutline() {
        guard let target else {
            outlineWindow.orderOut(nil)
            return
        }

        outlineView.color = SettingsStore.shared.windowOutlineColor
        outlineWindow.setFrame(appKitFrame(for: target.bounds), display: true)
        outlineWindow.orderFrontRegardless()
    }

    private func appKitFrame(for cgBounds: CGRect) -> NSRect {
        let mainScreenMaxY = NSScreen.screens.first?.frame.maxY ?? NSScreen.main?.frame.maxY ?? 0
        let inset: CGFloat = 3
        return NSRect(
            x: cgBounds.minX - inset,
            y: mainScreenMaxY - cgBounds.maxY - inset,
            width: cgBounds.width + inset * 2,
            height: cgBounds.height + inset * 2
        )
    }

    private func findWindow(at point: CGPoint) -> LockedWindow? {
        guard let windows = windowList() else { return nil }
        let ownPID = getpid()

        for info in windows {
            guard let layer = info[kCGWindowLayer as String] as? NSNumber, layer.intValue == 0 else {
                continue
            }
            guard let alpha = info[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue > 0 else {
                continue
            }
            guard let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber else {
                continue
            }
            let pid = pid_t(pidNumber.int32Value)
            guard pid != ownPID else { continue }
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  !excludedOwners.contains(owner) else {
                continue
            }
            guard let windowIDNumber = info[kCGWindowNumber as String] as? NSNumber,
                  let bounds = bounds(from: info) else {
                continue
            }
            guard bounds.width > 40, bounds.height > 40, bounds.contains(point) else {
                continue
            }
            return LockedWindow(
                windowID: CGWindowID(windowIDNumber.uint32Value),
                ownerPID: pid,
                bounds: bounds
            )
        }
        return nil
    }

    private func findFrontmostWindow(ofPID pid: pid_t) -> LockedWindow? {
        guard let windows = windowList() else { return nil }

        for info in windows {
            guard let layer = info[kCGWindowLayer as String] as? NSNumber, layer.intValue == 0 else {
                continue
            }
            guard let alpha = info[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue > 0 else {
                continue
            }
            guard let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
                  pidNumber.int32Value == pid else {
                continue
            }
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  !excludedOwners.contains(owner) else {
                continue
            }
            guard let windowIDNumber = info[kCGWindowNumber as String] as? NSNumber,
                  let bounds = bounds(from: info),
                  bounds.width > 40, bounds.height > 40 else {
                continue
            }
            return LockedWindow(
                windowID: CGWindowID(windowIDNumber.uint32Value),
                ownerPID: pid,
                bounds: bounds
            )
        }
        return nil
    }

    private func findWindow(id: CGWindowID) -> LockedWindow? {
        guard let windows = windowList() else { return nil }

        for info in windows {
            guard let windowIDNumber = info[kCGWindowNumber as String] as? NSNumber,
                  windowIDNumber.uint32Value == id,
                  let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let bounds = bounds(from: info) else {
                continue
            }
            return LockedWindow(
                windowID: id,
                ownerPID: pid_t(pidNumber.int32Value),
                bounds: bounds
            )
        }
        return nil
    }

    private func windowList() -> [[String: Any]]? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        return CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
    }

    private func bounds(from info: [String: Any]) -> CGRect? {
        guard let dict = info[kCGWindowBounds as String] as? NSDictionary else {
            return nil
        }
        return CGRect(dictionaryRepresentation: dict)
    }
}

private final class WindowOutlineWindow: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class WindowOutlineView: NSView {
    var color: NSColor = .systemBlue {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 3, dy: 3)
        guard rect.width > 0, rect.height > 0 else { return }
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        color.withAlphaComponent(0.95).setStroke()
        path.lineWidth = 3
        path.stroke()
    }
}
