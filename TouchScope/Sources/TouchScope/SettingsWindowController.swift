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
        }
        .padding(20)
        .frame(width: 540, height: 430)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage(SettingsKeys.startCGMouse) private var startCGMouse = SettingsDefaults.startCGMouse
    @AppStorage(SettingsKeys.threeFingerDoubleTap) private var threeFingerDoubleTap = SettingsDefaults.threeFingerDoubleTap
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
        }
    }

    private func openAccessibility() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
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
        window.setContentSize(NSSize(width: 540, height: 430))
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
