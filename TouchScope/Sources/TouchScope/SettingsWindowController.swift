import AppKit
import ApplicationServices
import Combine
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            PointerSettingsView()
                .tabItem { Label("Pointer", systemImage: "cursorarrow") }
            HapticsSettingsView()
                .tabItem { Label("Haptics", systemImage: "waveform") }
        }
        .padding(20)
        .frame(width: 540, height: 580)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage(SettingsKeys.startCGMouse) private var startCGMouse = SettingsDefaults.startCGMouse
    @AppStorage(SettingsKeys.threeFingerDoubleTap) private var threeFingerDoubleTap = SettingsDefaults.threeFingerDoubleTap
    @AppStorage(SettingsKeys.windowOutlineColor) private var windowOutlineColorHex = SettingsDefaults.windowOutlineColor
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Enable CG mouse when TouchScope launches", isOn: $startCGMouse)
                Text("Requires Accessibility permission. The mode can still be toggled from the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Gestures") {
                Toggle("Three-finger double-tap toggles CG mouse", isOn: $threeFingerDoubleTap)
            }

            Section("Window mode") {
                ColorPicker("Window outline color", selection: windowOutlineColorBinding, supportsOpacity: false)
                Text("Press ⌃⌥W, or tap two fingers and then three fingers, to lock the cursor to the window under the pointer. Repeat to unlock.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                HStack(spacing: 8) {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                    Text(trusted ? "Accessibility granted" : "Accessibility required")
                    Spacer()
                    Button(trusted ? "Open System Settings" : "Grant…") {
                        openAccessibility()
                    }
                }
            }

            Section("Diagnostics") {
                HStack {
                    Button("Open Log") {
                        NSWorkspace.shared.open(Log.fileURL)
                    }
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Log.fileURL])
                    }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        SettingsStore.shared.reset()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            trusted = AXIsProcessTrusted()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            trusted = AXIsProcessTrusted()
        }
        .onReceive(NotificationCenter.default.publisher(for: .touchScopeSettingsReset)) { _ in
            startCGMouse = SettingsDefaults.startCGMouse
            threeFingerDoubleTap = SettingsDefaults.threeFingerDoubleTap
            windowOutlineColorHex = SettingsDefaults.windowOutlineColor
        }
    }

    private var windowOutlineColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: windowOutlineColorHex) ?? .systemBlue) },
            set: { windowOutlineColorHex = NSColor($0).hexString }
        )
    }

    private func openAccessibility() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct HapticsSettingsView: View {
    @AppStorage(SettingsKeys.hapticFeedback) private var enabled = SettingsDefaults.hapticFeedback
    @AppStorage(SettingsKeys.hapticStrength) private var strength = SettingsDefaults.hapticStrength
    @AppStorage(SettingsKeys.hapticGesture) private var gesture = SettingsDefaults.hapticGesture
    @AppStorage(SettingsKeys.hapticFingerCount) private var fingerCount = SettingsDefaults.hapticFingerCount
    @AppStorage(SettingsKeys.hapticWindowEnter) private var windowEnter = SettingsDefaults.hapticWindowEnter
    @AppStorage(SettingsKeys.hapticWindowExit) private var windowExit = SettingsDefaults.hapticWindowExit
    @AppStorage(SettingsKeys.hapticWindowChange) private var windowChange = SettingsDefaults.hapticWindowChange
    @AppStorage(SettingsKeys.hapticWindowChangeStrength) private var windowChangeStrength = SettingsDefaults.hapticWindowChangeStrength
    @AppStorage(SettingsKeys.hapticBoundary) private var boundary = SettingsDefaults.hapticBoundary
    @AppStorage(SettingsKeys.hapticScroll) private var scroll = SettingsDefaults.hapticScroll
    @AppStorage(SettingsKeys.hapticScrollInertia) private var scrollInertia = SettingsDefaults.hapticScrollInertia
    @AppStorage(SettingsKeys.hapticDragStart) private var dragStart = SettingsDefaults.hapticDragStart
    @AppStorage(SettingsKeys.hapticDragEnd) private var dragEnd = SettingsDefaults.hapticDragEnd

    var body: some View {
        Form {
            Section("Feedback") {
                Toggle("Enable haptic feedback", isOn: $enabled)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Strength")
                        Spacer()
                        Text("\(Int((strength * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $strength, in: 0.1...1.0, step: 0.05)
                        .disabled(!enabled)
                    Text("Strength uses the Force Touch actuator. If MultitouchSupport is unavailable, fixed AppKit taps are used instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Test feedback") {
                    HapticFeedbackController.shared.preview()
                }
                .disabled(!enabled)
            }

            Section("Events") {
                Toggle("Gesture confirmation", isOn: $gesture)
                Toggle("Finger count change", isOn: $fingerCount)
                Toggle("Window mode on", isOn: $windowEnter)
                Toggle("Window mode off", isOn: $windowExit)
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Window-to-window move", isOn: $windowChange)
                    HStack {
                        Text("Window-to-window strength")
                        Spacer()
                        Text("\(Int((windowChangeStrength * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $windowChangeStrength, in: 0.1...1.0, step: 0.05)
                        .disabled(!enabled || !windowChange)
                    Text("Deeper windows use a different tap and a little more strength.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Test window-to-window") {
                        HapticFeedbackController.shared.previewWindowChange()
                    }
                    .disabled(!enabled || !windowChange)
                }
                Toggle("Window or screen edge", isOn: $boundary)
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Scroll", isOn: $scroll)
                    HStack {
                        Text("Scroll inertia length")
                        Spacer()
                        Text(String(format: "%.2f s", scrollInertia))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $scrollInertia, in: 0.1...0.8, step: 0.05)
                        .disabled(!enabled || !scroll)
                    Text("Fading ticks after two-finger scrolling stops.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Drag start", isOn: $dragStart)
                Toggle("Drag end", isOn: $dragEnd)
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: .touchScopeSettingsReset)) { _ in
            enabled = SettingsDefaults.hapticFeedback
            strength = SettingsDefaults.hapticStrength
            gesture = SettingsDefaults.hapticGesture
            fingerCount = SettingsDefaults.hapticFingerCount
            windowEnter = SettingsDefaults.hapticWindowEnter
            windowExit = SettingsDefaults.hapticWindowExit
            windowChange = SettingsDefaults.hapticWindowChange
            windowChangeStrength = SettingsDefaults.hapticWindowChangeStrength
            boundary = SettingsDefaults.hapticBoundary
            scroll = SettingsDefaults.hapticScroll
            scrollInertia = SettingsDefaults.hapticScrollInertia
            dragStart = SettingsDefaults.hapticDragStart
            dragEnd = SettingsDefaults.hapticDragEnd
        }
    }
}

private struct PointerSettingsView: View {
    @AppStorage(SettingsKeys.smoothingFactor) private var smoothing = SettingsDefaults.smoothingFactor
    @AppStorage(SettingsKeys.retouchStickyRadius) private var stickyRadius = SettingsDefaults.retouchStickyRadius
    @AppStorage(SettingsKeys.dragThreshold) private var dragThreshold = SettingsDefaults.dragThreshold

    var body: some View {
        Form {
            Section("Motion") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Smoothing")
                        Spacer()
                        Text(String(format: "%.2f", smoothing))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $smoothing, in: 0.05...1.0, step: 0.01)
                    Text("Lower values are smoother but lag more. 1.0 follows the finger exactly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Sticky retouch zone")
                        Spacer()
                        Text(String(format: "%.1f%%", stickyRadius * 100))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $stickyRadius, in: 0...0.05, step: 0.001)
                    Text("Prevents the cursor from jumping when you lift and quickly touch the same spot again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Click and drag") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Drag threshold")
                        Spacer()
                        Text("\(Int(dragThreshold.rounded())) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $dragThreshold, in: 1...20, step: 1)
                    Text("Movement below this distance stays a click; movement above it becomes a drag.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: .touchScopeSettingsReset)) { _ in
            smoothing = SettingsDefaults.smoothingFactor
            stickyRadius = SettingsDefaults.retouchStickyRadius
            dragThreshold = SettingsDefaults.dragThreshold
        }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    init() {
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "TouchScope Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 540, height: 520))
        window.center()
        window.setFrameAutosaveName("TouchScopeSettings")
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
