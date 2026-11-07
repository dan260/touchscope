import AppKit
import Foundation

extension Notification.Name {
    static let touchScopeSettingsReset = Notification.Name("TouchScopeSettingsReset")
}

enum SettingsKeys {
    static let smoothingFactor = "smoothingFactor"
    static let retouchStickyRadius = "retouchStickyRadius"
    static let dragThreshold = "dragThreshold"
    static let threeFingerDoubleTap = "threeFingerDoubleTap"
    static let startCGMouse = "startCGMouse"
    static let windowOutlineColor = "windowOutlineColor"
}

enum SettingsDefaults {
    static let smoothingFactor = 0.35
    static let retouchStickyRadius = 0.012
    static let dragThreshold = 5.0
    static let threeFingerDoubleTap = true
    static let startCGMouse = false
    static let windowOutlineColor = "#0A84FF"
}

final class SettingsStore: @unchecked Sendable {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    var smoothingFactor: Double {
        get { defaults.object(forKey: SettingsKeys.smoothingFactor) as? Double ?? SettingsDefaults.smoothingFactor }
        set { defaults.set(newValue, forKey: SettingsKeys.smoothingFactor) }
    }

    var retouchStickyRadius: Double {
        get { defaults.object(forKey: SettingsKeys.retouchStickyRadius) as? Double ?? SettingsDefaults.retouchStickyRadius }
        set { defaults.set(newValue, forKey: SettingsKeys.retouchStickyRadius) }
    }

    var dragThreshold: Double {
        get { defaults.object(forKey: SettingsKeys.dragThreshold) as? Double ?? SettingsDefaults.dragThreshold }
        set { defaults.set(newValue, forKey: SettingsKeys.dragThreshold) }
    }

    var threeFingerDoubleTap: Bool {
        get { defaults.object(forKey: SettingsKeys.threeFingerDoubleTap) as? Bool ?? SettingsDefaults.threeFingerDoubleTap }
        set { defaults.set(newValue, forKey: SettingsKeys.threeFingerDoubleTap) }
    }

    var startCGMouse: Bool {
        get { defaults.object(forKey: SettingsKeys.startCGMouse) as? Bool ?? SettingsDefaults.startCGMouse }
        set { defaults.set(newValue, forKey: SettingsKeys.startCGMouse) }
    }

    var windowOutlineColorHex: String {
        get { defaults.string(forKey: SettingsKeys.windowOutlineColor) ?? SettingsDefaults.windowOutlineColor }
        set { defaults.set(newValue, forKey: SettingsKeys.windowOutlineColor) }
    }

    var windowOutlineColor: NSColor {
        NSColor(hex: windowOutlineColorHex) ?? .systemBlue
    }

    func reset() {
        for key in [
            SettingsKeys.smoothingFactor,
            SettingsKeys.retouchStickyRadius,
            SettingsKeys.dragThreshold,
            SettingsKeys.threeFingerDoubleTap,
            SettingsKeys.startCGMouse,
            SettingsKeys.windowOutlineColor,
        ] {
            defaults.removeObject(forKey: key)
        }
        NotificationCenter.default.post(name: .touchScopeSettingsReset, object: nil)
    }
}
