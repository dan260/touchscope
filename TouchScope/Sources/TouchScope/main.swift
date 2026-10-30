import AppKit
import ApplicationServices

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var cgItem: NSMenuItem!
    private var mtItem: NSMenuItem!
    private var accessItem: NSMenuItem!
    private let cgMouse = CGMouseController()
    private let mtTouch = MultitouchTouchSource()

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

        mtItem = NSMenuItem(title: "Global trackpad", action: nil, keyEquivalent: "")
        mtItem.isEnabled = false
        menu.addItem(mtItem)

        let gestureItem = NSMenuItem(title: "3-finger double-tap toggles CG mouse", action: nil, keyEquivalent: "")
        gestureItem.isEnabled = false
        menu.addItem(gestureItem)

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
                guard let self else { return }
                self.setCGMouse(!self.cgMouse.isEnabled)
            }
        }

        Log.write("Accessibility trusted: \(AXIsProcessTrusted())")
        if mtTouch.start() {
            Log.write("Global trackpad listener started")
        } else {
            Log.write("Global trackpad listener failed to start")
        }
        refreshStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        mtTouch.stop()
        cgMouse.deactivate()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshStatus()
    }

    @objc private func toggleCGMouse() {
        setCGMouse(!cgMouse.isEnabled)
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
            mtTouch.onTouch = nil
            mtTouch.cancelPointer()
            cgMouse.deactivate()
        }
        refreshStatus()
    }

    private func refreshStatus() {
        let on = cgMouse.isEnabled
        cgItem?.state = on ? .on : .off
        mtItem?.title = mtTouch.isRunning ? "Global trackpad: Ready" : "Global trackpad: Unavailable"

        let trusted = AXIsProcessTrusted()
        accessItem?.title = trusted ? "Accessibility: Granted" : "Grant Accessibility…"
        accessItem?.isEnabled = !trusted

        if let button = statusItem?.button {
            button.image = symbol(on ? "cursorarrow.rays" : "cursorarrow")
            button.toolTip = on ? "TouchScope — CG mouse on" : "TouchScope — CG mouse off"
        }
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
