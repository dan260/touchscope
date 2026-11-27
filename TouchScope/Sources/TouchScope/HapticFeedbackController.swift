import AppKit
import CoreFoundation

@MainActor
final class HapticFeedbackController {
    static let shared = HapticFeedbackController()

    private enum Event: String {
        case gesture
        case fingerCount
        case windowEnter
        case windowExit
        case windowChange
        case boundary
        case scroll
        case dragStart
        case dragEnd

        var waveform: Int32 {
            switch self {
            case .gesture: return 4
            case .fingerCount: return 1
            case .windowEnter: return 6
            case .windowExit: return 2
            case .windowChange: return 4
            case .boundary: return 5
            case .scroll: return 1
            case .dragStart: return 2
            case .dragEnd: return 4
            }
        }

        var fallback: NSHapticFeedbackManager.FeedbackPattern {
            switch self {
            case .gesture, .dragStart, .dragEnd: return .generic
            case .fingerCount, .windowExit, .scroll: return .levelChange
            case .windowEnter, .windowChange, .boundary: return .alignment
            }
        }

        var isEnabled: Bool {
            switch self {
            case .gesture: return SettingsStore.shared.hapticGesture
            case .fingerCount: return SettingsStore.shared.hapticFingerCount
            case .windowEnter: return SettingsStore.shared.hapticWindowEnter
            case .windowExit: return SettingsStore.shared.hapticWindowExit
            case .windowChange: return SettingsStore.shared.hapticWindowChange
            case .boundary: return SettingsStore.shared.hapticBoundary
            case .scroll: return SettingsStore.shared.hapticScroll
            case .dragStart: return SettingsStore.shared.hapticDragStart
            case .dragEnd: return SettingsStore.shared.hapticDragEnd
            }
        }
    }

    private static func waveform(forWindowDepth depth: Int) -> Int32 {
        switch depth {
        case 0...1: return 4
        case 2...3: return 5
        default: return 3
        }
    }

    private static func fallback(forWindowDepth depth: Int) -> NSHapticFeedbackManager.FeedbackPattern {
        switch depth {
        case 0...1: return .levelChange
        case 2...3: return .alignment
        default: return .generic
        }
    }

    private let performer = NSHapticFeedbackManager.defaultPerformer
    private let actuator: MultitouchHapticActuator?
    private var lastFire: [Event: CFTimeInterval] = [:]

    private init() {
        actuator = MultitouchHapticActuator()
    }

    func gestureConfirmed() {
        fire(.gesture, minInterval: 0.08)
    }

    func fingerCountChanged() {
        fire(.fingerCount, minInterval: 0.1)
    }

    func windowModeEntered() {
        fire(.windowEnter, minInterval: 0.12)
    }

    func windowModeExited() {
        fire(.windowExit, minInterval: 0.12)
    }

    func windowChanged(depth: Int) {
        let baseStrength = SettingsStore.shared.hapticWindowChangeStrength
        let depthFactor = 1.0 + min(0.3, Double(max(0, depth)) * 0.08)
        fire(
            .windowChange,
            minInterval: 0.12,
            waveform: Self.waveform(forWindowDepth: depth),
            strength: min(1.0, baseStrength * depthFactor),
            fallback: Self.fallback(forWindowDepth: depth)
        )
    }

    func boundaryReached() {
        fire(.boundary, minInterval: 0.2)
    }

    func scrolled(intensity: Double) {
        let strength = SettingsStore.shared.hapticStrength * max(0, min(1, intensity))
        fire(.scroll, minInterval: 0.05, strength: strength)
    }

    func dragStarted() {
        fire(.dragStart, minInterval: 0.1)
    }

    func dragEnded() {
        fire(.dragEnd, minInterval: 0.1)
    }

    func preview() {
        guard SettingsStore.shared.hapticFeedback else { return }
        lastFire[.gesture] = nil
        fire(.gesture, minInterval: 0, ignoreEventSetting: true)
    }

    func previewWindowChange() {
        guard SettingsStore.shared.hapticFeedback, SettingsStore.shared.hapticWindowChange else { return }
        lastFire[.windowChange] = nil
        windowChanged(depth: 1)
    }

    private func fire(
        _ event: Event,
        minInterval: CFTimeInterval,
        ignoreEventSetting: Bool = false,
        waveform: Int32? = nil,
        strength: Double? = nil,
        fallback: NSHapticFeedbackManager.FeedbackPattern? = nil
    ) {
        guard SettingsStore.shared.hapticFeedback, ignoreEventSetting || event.isEnabled else { return }
        let now = CFAbsoluteTimeGetCurrent()
        if let last = lastFire[event], now - last < minInterval { return }
        lastFire[event] = now

        let selectedWaveform = waveform ?? event.waveform
        let selectedStrength = strength ?? SettingsStore.shared.hapticStrength
        if let actuator, actuator.actuate(waveform: selectedWaveform, strength: selectedStrength) {
            return
        }
        performer.perform(fallback ?? event.fallback, performanceTime: .now)
    }
}
