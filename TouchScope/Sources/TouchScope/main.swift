import AppKit
import ApplicationServices

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var cgItem: NSMenuItem!
    private var mtItem: NSMenuItem!
    private var accessItem: NSMenuItem!
    private var gestureItem: NSMenuItem!
    private var windowItem: NSMenuItem!
    private let cgMouse = CGMouseController()
    private let mtTouch = MultitouchTouchSource()
    private let windowLock = WindowLockController()
    private let windowHotKey = GlobalHotKey()
    private lazy var settingsWindow = SettingsWindowController()
    private var retargetTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = symbol("cursorarrow")
            button.toolTip = "TouchScope"
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        cgItem = NSMenuItem(title: "CG mouse", action: #selector(toggleCGMouse), keyEquivalent: "")
        cgItem.target = self
        cgItem.isEnabled = true
        menu.addItem(cgItem)

        windowItem = NSMenuItem(title: "Lock to Window (⌃⌥W or 2+3 tap)", action: #selector(toggleWindowLock), keyEquivalent: "")
        windowItem.target = self
        menu.addItem(windowItem)

        mtItem = NSMenuItem(title: "Global trackpad", action: nil, keyEquivalent: "")
        mtItem.isEnabled = false
        menu.addItem(mtItem)

        gestureItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        gestureItem.isEnabled = false
        menu.addItem(gestureItem)

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)

        accessItem = NSMenuItem(title: "Grant Accessibility…", action: #selector(openAccessibility), keyEquivalent: "")
        accessItem.target = self
        menu.addItem(accessItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit TouchScope", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        statusItem.menu = menu

        Log.reset()
        cgMouse.logHandler = { Log.write("[CG] \($0)") }
        mtTouch.logHandler = { Log.write($0) }
        mtTouch.onThreeFingerDoubleTap = { [weak self] in
            Task { @MainActor in
                guard let self, SettingsStore.shared.threeFingerDoubleTap else { return }
                self.setCGMouse(!self.cgMouse.isEnabled)
            }
        }
        mtTouch.onTwoThenThreeFingerTap = { [weak self] in
            Task { @MainActor in
                self?.toggleWindowLock()
            }
        }

        windowLock.onTargetChanged = { [weak self] bounds in
            self?.cgMouse.setLockedWindowBounds(bounds)
            self?.refreshStatus()
        }
        windowLock.onTargetLost = { [weak self] reason in
            Log.write("[WL] \(reason)")
            self?.refreshStatus()
        }
        windowHotKey.onPress = { [weak self] in
            self?.toggleWindowLock()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        Log.write("Accessibility trusted: \(AXIsProcessTrusted())")
        if mtTouch.start() {
            Log.write("Global trackpad listener started")
        } else {
            Log.write("Global trackpad listener failed to start")
        }
        refreshStatus()
        if SettingsStore.shared.startCGMouse {
            setCGMouse(true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        retargetTask?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        windowLock.unlock()
        mtTouch.stop()
        cgMouse.deactivate()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshStatus()
    }

    @objc private func toggleCGMouse() {
        setCGMouse(!cgMouse.isEnabled)
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        guard windowLock.isActive,
              let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != getpid() else {
            return
        }

        let pid = app.processIdentifier
        retargetTask?.cancel()
        retargetTask = Task { @MainActor [weak self] in
            for delay in [120, 250, 400, 700] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled, let self, self.windowLock.isActive else { return }
                if self.windowLock.switchToFrontmostWindow(ofPID: pid) {
                    self.centerCursorIfNeeded(in: self.windowLock.target?.bounds)
                    Log.write("[WL] switched to window of pid \(pid)")
                    return
                }
            }
            Log.write("[WL] no window found for newly active pid \(pid)")
        }
    }

    private func centerCursorIfNeeded(in bounds: CGRect?) {
        guard let bounds else { return }
        let cursor = CGEvent(source: nil)?.location ?? .zero
        guard !bounds.contains(cursor) else { return }
        cgMouse.warp(to: CGPoint(x: bounds.midX, y: bounds.midY))
    }

    private func setCGMouse(_ on: Bool) {
        if on {
            guard !cgMouse.isEnabled else {
                refreshStatus()
                return
            }
            if !mtTouch.isRunning, !mtTouch.start() {
                Log.write("Global trackpad unavailable; CG mouse not activated")
                refreshStatus()
                return
            }
            let mouse = cgMouse
            mtTouch.onTouch = { id, point, down in
                mouse.handle(multitouchFingerID: id, normalized: point, down: down)
            }
            guard cgMouse.activate() else {
                mtTouch.onTouch = nil
                refreshStatus()
                return
            }
        } else {
            windowLock.unlock()
            mtTouch.onTouch = nil
            mtTouch.cancelPointer()
            cgMouse.deactivate()
        }
        refreshStatus()
    }

    @objc private func toggleWindowLock() {
        if windowLock.isActive {
            windowLock.unlock()
            refreshStatus()
            return
        }

        if !cgMouse.isEnabled {
            setCGMouse(true)
            guard cgMouse.isEnabled else { return }
        }

        guard let cursor = CGEvent(source: nil)?.location else {
            Log.write("[WL] cursor location unavailable")
            return
        }

        if !windowLock.lock(at: cursor) {
            Log.write("[WL] no window under cursor")
            NSSound.beep()
        }
        refreshStatus()
    }

    private func refreshStatus() {
        let on = cgMouse.isEnabled
        cgItem?.state = on ? .on : .off
        mtItem?.title = mtTouch.isRunning ? "Global trackpad: Ready" : "Global trackpad: Unavailable"
        gestureItem?.title = SettingsStore.shared.threeFingerDoubleTap
            ? "3-finger double-tap: On"
            : "3-finger double-tap: Off"
        windowItem?.state = windowLock.isActive ? .on : .off
        windowItem?.title = windowLock.isActive
            ? "Window Mode: On (⌃⌥W or 2+3 tap)"
            : "Lock to Window (⌃⌥W or 2+3 tap)"

        let trusted = AXIsProcessTrusted()
        accessItem?.title = trusted ? "Accessibility: Granted" : "Grant Accessibility…"
        accessItem?.isEnabled = !trusted

        if let button = statusItem?.button {
            button.image = symbol(on ? "cursorarrow.rays" : "cursorarrow")
            button.toolTip = on ? "TouchScope — CG mouse on" : "TouchScope — CG mouse off"
        }
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func openAccessibility() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "TouchScope")
        image?.isTemplate = true
        return image
    }
}

let app = NSApplication.shared
let delegate = AppController()
app.delegate = delegate
app.run()
