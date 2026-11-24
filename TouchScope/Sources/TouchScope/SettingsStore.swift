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
    static let hapticFeedback = "hapticFeedback"
    static let hapticStrength = "hapticStrength"
    static let hapticGesture = "hapticGesture"
    static let hapticFingerCount = "hapticFingerCount"
    static let hapticWindowEnter = "hapticWindowEnter"
    static let hapticWindowExit = "hapticWindowExit"
    static let hapticWindowChange = "hapticWindowChange"
    static let hapticWindowChangeStrength = "hapticWindowChangeStrength"
    static let hapticBoundary = "hapticBoundary"
    static let hapticScroll = "hapticScroll"
    static let hapticDragStart = "hapticDragStart"
    static let hapticDragEnd = "hapticDragEnd"
    static let startCGMouse = "startCGMouse"
    static let windowOutlineColor = "windowOutlineColor"
}

enum SettingsDefaults {
    static let smoothingFactor = 0.35
    static let retouchStickyRadius = 0.012
    static let dragThreshold = 5.0
    static let threeFingerDoubleTap = true
    static let hapticFeedback = true
    static let hapticStrength = 0.7
    static let hapticGesture = true
    static let hapticFingerCount = true
    static let hapticWindowEnter = true
    static let hapticWindowExit = true
    static let hapticWindowChange = true
    static let hapticWindowChangeStrength = 0.7
    static let hapticBoundary = true
    static let hapticScroll = true
    static let hapticDragStart = true
    static let hapticDragEnd = true
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

    var hapticFeedback: Bool {
        get { defaults.object(forKey: SettingsKeys.hapticFeedback) as? Bool ?? SettingsDefaults.hapticFeedback }
        set { defaults.set(newValue, forKey: SettingsKeys.hapticFeedback) }
    }

    var hapticStrength: Double {
        get { defaults.object(forKey: SettingsKeys.hapticStrength) as? Double ?? SettingsDefaults.hapticStrength }
        set { defaults.set(newValue, forKey: SettingsKeys.hapticStrength) }
    }

    var hapticGesture: Bool {
        get { defaults.object(forKey: SettingsKeys.hapticGesture) as? Bool ?? SettingsDefaults.hapticGesture }
        set { defaults.set(newValue, forKey: SettingsKeys.hapticGesture) }
    }

    var hapticFingerCount: Bool {
        get { defaults.object(forKey: SettingsKeys.hapticFingerCount) as? Bool ?? SettingsDefaults.hapticFingerCount }
        set { defaults.set(newValue, forKey: SettingsKeys.hapticFingerCount) }
    }

    var hapticWindowEnter: Bool {
        get { defaults.object(forKey: SettingsKeys.hapticWindowEnter) as? Bool ?? SettingsDefaults.hapticWindowEnter }
        set { defaults.set(newValue, forKey: SettingsKeys.hapticWindowEnter) }
    }

    var hapticWindowExit: Bool {
        get { defaults.object(forKey: SettingsKeys.hapticWindowExit) as? Bool ?? SettingsDefaults.hapticWindowExit }
        set { defaults.set(newValue, forKey: SettingsKeys.hapticWindowExit) }
    }

    var hapticWindowChange: Bool {
        get { defaults.object(forKey: SettingsKeys.hapticWindowChange) as? Bool ?? SettingsDefaults.hapticWindowChange }
        set { defaults.set(newValue, forKey: SettingsKeys.hapticWindowChange) }
    }

    var hapticWindowChangeStrength: Double {
        get { defaults.object(forKey: SettingsKeys.hapticWindowChangeStrength) as? Double ?? SettingsDefaults.hapticWindowChangeStrength }
        set { defaults.set(newValue, forKey: SettingsKeys.hapticWindowChangeStrength) }
    }

    var hapticBoundary: Bool {
        get { defaults.object(forKey: SettingsKeys.hapticBoundary) as? Bool ?? SettingsDefaults.hapticBoundary }
        set { defaults.set(newValue, forKey: SettingsKeys.hapticBoundary) }
    }

    var hapticScroll: Bool {
        get { defaults.object(forKey: SettingsKeys.hapticScroll) as? Bool ?? SettingsDefaults.hapticScroll }
        set { defaults.set(newValue, forKey: SettingsKeys.hapticScroll) }
    }

    var hapticDragStart: Bool {
        get { defaults.object(forKey: SettingsKeys.hapticDragStart) as? Bool ?? SettingsDefaults.hapticDragStart }
        set { defaults.set(newValue, forKey: SettingsKeys.hapticDragStart) }
    }

    var hapticDragEnd: Bool {
        get { defaults.object(forKey: SettingsKeys.hapticDragEnd) as? Bool ?? SettingsDefaults.hapticDragEnd }
        set { defaults.set(newValue, forKey: SettingsKeys.hapticDragEnd) }
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
            SettingsKeys.hapticFeedback,
            SettingsKeys.hapticStrength,
            SettingsKeys.hapticGesture,
            SettingsKeys.hapticFingerCount,
            SettingsKeys.hapticWindowEnter,
            SettingsKeys.hapticWindowExit,
            SettingsKeys.hapticWindowChange,
            SettingsKeys.hapticWindowChangeStrength,
            SettingsKeys.hapticBoundary,
            SettingsKeys.hapticScroll,
            SettingsKeys.hapticDragStart,
            SettingsKeys.hapticDragEnd,
            SettingsKeys.startCGMouse,
            SettingsKeys.windowOutlineColor,
        ] {
            defaults.removeObject(forKey: key)
        }
        NotificationCenter.default.post(name: .touchScopeSettingsReset, object: nil)
    }
}
