import Foundation
import CoreFoundation

private typealias MTFrameCallback = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
private typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>?
private typealias RegisterFn = @convention(c) (UnsafeRawPointer, MTFrameCallback) -> Void
private typealias StartFn = @convention(c) (UnsafeRawPointer, Int32) -> Void
private typealias StopFn = @convention(c) (UnsafeRawPointer) -> Void
private typealias IsBuiltInFn = @convention(c) (UnsafeRawPointer) -> Bool
private typealias IsRunningFn = @convention(c) (UnsafeRawPointer) -> Bool

private struct MTFinger: Sendable {
    var id: Int32
    var state: UInt32
    var x: Double
    var y: Double
    var z: Double
}

private nonisolated(unsafe) weak var sharedSource: MultitouchTouchSource?

private let frameCallback: MTFrameCallback = { _, touches, n, _, _ in
    guard let source = sharedSource else { return 0 }
    var fingers: [MTFinger] = []
    if let touches, n > 0 {
        fingers.reserveCapacity(Int(n))
        for i in 0..<Int(n) {
            let p = touches.advanced(by: i * 96)
            fingers.append(MTFinger(
                id: p.load(fromByteOffset: 24, as: Int32.self),
                state: p.load(fromByteOffset: 20, as: UInt32.self),
                x: Double(p.load(fromByteOffset: 32, as: Float.self)),
                y: Double(p.load(fromByteOffset: 36, as: Float.self)),
                z: Double(p.load(fromByteOffset: 48, as: Float.self))
            ))
        }
    }
    source.enqueue(fingers)
    return 0
}

final class MultitouchTouchSource: @unchecked Sendable {
    var logHandler: ((String) -> Void)?
    var onTouch: ((Int32, CGPoint, Bool) -> Void)?
    var onThreeFingerDoubleTap: (() -> Void)?
    var onTwoThenThreeFingerTap: (() -> Void)?
    var onGestureConfirmed: (() -> Void)?
    var onFingerCountChanged: ((Int) -> Void)?
    var onScroll: ((Double) -> Void)?

    private(set) var isRunning = false

    private var handle: UnsafeMutableRawPointer?
    private var deviceList: CFArray?
    private var device: UnsafeRawPointer?
    private var stopFn: StopFn?
    private var unregisterFn: RegisterFn?
    private var isRunningFn: IsRunningFn?

    private var pointerActive = false
    private var pointerSuppressed = false
    private var lastPoint: CGPoint = .zero
    private var releaseWork: DispatchWorkItem?

    private var pendingPointerWork: DispatchWorkItem?
    private var pendingPoint: CGPoint = .zero
    private var pendingContact = false

    private var lastFingerCount = 0
    private var gestureActive = false
    private var gestureEvaluated = false
    private var threeFingerStart: CFTimeInterval = 0
    private var threeFingerStartCentroid: CGPoint = .zero
    private var threeFingerMaxMovement: Double = 0
    private var lastThreeFingerTap: CFTimeInterval = 0

    private var twoFingerActive = false
    private var twoFingerEvaluated = false
    private var twoFingerStart: CFTimeInterval = 0
    private var twoFingerStartCentroid: CGPoint = .zero
    private var twoFingerMaxMovement: Double = 0
    private var lastTwoFingerTap: CFTimeInterval = 0

    private var lastScrollCentroid: CGPoint?
    private var scrollTravel: Double = 0
    private var lastScrollFire: CFTimeInterval = 0
    private var scrollActive = false
    private var didScroll = false
    private var lastScrollSample: CFTimeInterval = 0
    private var scrollVelocity: Double = 0
    private var inertiaStartIntensity: Double = 0
    private var inertiaStartedAt: CFTimeInterval = 0
    private var inertiaDuration: Double = 0
    private var inertiaTimer: Timer?

    deinit {
        stop()
    }

    @discardableResult
    func start() -> Bool {
        if isRunning { return true }

        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let h = dlopen(path, RTLD_NOW) else {
            log("dlopen failed: \(String(cString: dlerror()))")
            return false
        }
        handle = h

        func sym<T>(_ name: String, as type: T.Type) -> T? {
            guard let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }

        guard let createList = sym("MTDeviceCreateList", as: CreateListFn.self),
              let register = sym("MTRegisterContactFrameCallback", as: RegisterFn.self),
              let startDevice = sym("MTDeviceStart", as: StartFn.self) else {
            log("MultitouchSupport symbols missing")
            return false
        }
        stopFn = sym("MTDeviceStop", as: StopFn.self)
        unregisterFn = sym("MTUnregisterContactFrameCallback", as: RegisterFn.self)
        isRunningFn = sym("MTDeviceIsRunning", as: IsRunningFn.self)
        let isBuiltIn = sym("MTDeviceIsBuiltIn", as: IsBuiltInFn.self)

        guard let listRef = createList() else {
            log("MTDeviceCreateList returned nil")
            return false
        }
        let list = listRef.takeRetainedValue()
        let count = CFArrayGetCount(list)
        guard count > 0 else {
            log("MultitouchSupport found no devices")
            return false
        }

        var chosen: UnsafeRawPointer?
        for i in 0..<count {
            guard let dev = CFArrayGetValueAtIndex(list, i) else { continue }
            if isBuiltIn?(dev) == true {
                chosen = dev
                break
            }
            if chosen == nil { chosen = dev }
        }
        guard let dev = chosen else {
            log("no usable multitouch device")
            return false
        }

        deviceList = list
        device = dev
        sharedSource = self
        register(dev, frameCallback)
        startDevice(dev, 0)

        if let isRunningFn, isRunningFn(dev) == false {
            log("MTDeviceStart did not leave the device running")
            stopFn?(dev)
            unregisterFn?(dev, frameCallback)
            sharedSource = nil
            device = nil
            deviceList = nil
            return false
        }

        isRunning = true
        pointerActive = false
        pointerSuppressed = false
        releaseWork?.cancel()
        releaseWork = nil
        pendingPointerWork?.cancel()
        pendingPointerWork = nil
        pendingContact = false
        lastFingerCount = 0
        gestureActive = false
        gestureEvaluated = false
        lastThreeFingerTap = 0
        twoFingerActive = false
        twoFingerEvaluated = false
        lastTwoFingerTap = 0
        cancelInertia()
        lastScrollCentroid = nil
        scrollTravel = 0
        lastScrollFire = 0
        scrollActive = false
        didScroll = false
        lastScrollSample = 0
        scrollVelocity = 0
        log("started")
        return true
    }

    func stop() {
        guard isRunning || device != nil else { return }
        isRunning = false
        sharedSource = nil
        if let device {
            stopFn?(device)
            unregisterFn?(device, frameCallback)
        }
        device = nil
        deviceList = nil
        pointerActive = false
        pointerSuppressed = false
        releaseWork?.cancel()
        releaseWork = nil
        pendingPointerWork?.cancel()
        pendingPointerWork = nil
        pendingContact = false
        lastFingerCount = 0
        gestureActive = false
        gestureEvaluated = false
        lastThreeFingerTap = 0
        twoFingerActive = false
        twoFingerEvaluated = false
        lastTwoFingerTap = 0
        cancelInertia()
        lastScrollCentroid = nil
        scrollTravel = 0
        lastScrollFire = 0
        scrollActive = false
        didScroll = false
        lastScrollSample = 0
        scrollVelocity = 0
        log("stopped")
    }

    func cancelPointer() {
        pointerActive = false
        pointerSuppressed = false
        releaseWork?.cancel()
        releaseWork = nil
        pendingPointerWork?.cancel()
        pendingPointerWork = nil
        pendingContact = false
        cancelInertia()
        lastScrollCentroid = nil
        scrollTravel = 0
        scrollActive = false
        didScroll = false
        lastScrollSample = 0
        scrollVelocity = 0
    }

    fileprivate func enqueue(_ fingers: [MTFinger]) {
        DispatchQueue.main.async { [weak self] in
            self?.process(fingers)
        }
    }

    private func process(_ fingers: [MTFinger]) {
        guard isRunning else { return }

        let current = fingers.filter { $0.state == 3 || $0.state == 4 }
        let present = fingers.filter { $0.state == 1 || $0.state == 3 || $0.state == 4 }
        if current.count != lastFingerCount {
            lastFingerCount = current.count
            onFingerCountChanged?(current.count)
        }
        if onTouch == nil {
            cancelPointer()
        }

        if current.isEmpty {
            pointerSuppressed = false
        } else if current.count >= 2 {
            if pointerActive {
                releasePointer()
            }
            pointerSuppressed = true
        }

        updateTwoFingerScroll(current)
        updateTwoFingerTap(current)
        updateThreeFingerGesture(current, present: present)

        if gestureActive {
            cancelPendingPointerStart()
            return
        }

        guard onTouch != nil else {
            cancelPendingPointerStart()
            return
        }

        if pointerSuppressed {
            cancelPendingPointerStart()
            return
        }

        if current.isEmpty {
            cancelPendingPointerStart()
            scheduleRelease()
            return
        }

        if !pointerActive {
            let chosen = choose(from: current)
            schedulePointerStart(chosen)
            return
        }

        releaseWork?.cancel()
        releaseWork = nil

        let chosen = choose(from: current)
        let point = CGPoint(x: chosen.x, y: chosen.y)
        lastPoint = point
        onTouch?(0, point, true)
    }

    private func releasePointer() {
        guard pointerActive else { return }
        pointerActive = false
        releaseWork?.cancel()
        releaseWork = nil
        onTouch?(0, lastPoint, false)
    }

    private func schedulePointerStart(_ chosen: MTFinger) {
        pendingContact = true
        pendingPoint = CGPoint(x: chosen.x, y: chosen.y)
        guard pendingPointerWork == nil else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingPointerWork = nil
            guard self.isRunning, self.onTouch != nil,
                  self.pendingContact, !self.pointerActive else {
                self.pendingContact = false
                return
            }
            self.pendingContact = false
            self.pointerActive = true
            self.lastPoint = self.pendingPoint
            self.onTouch?(0, self.pendingPoint, true)
        }
        pendingPointerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: work)
    }

    private func cancelPendingPointerStart() {
        pendingPointerWork?.cancel()
        pendingPointerWork = nil
        pendingContact = false
    }

    private func updateTwoFingerScroll(_ contacts: [MTFinger]) {
        let now = CFAbsoluteTimeGetCurrent()
        guard contacts.count == 2, !gestureActive, onScroll != nil else {
            if gestureActive {
                cancelInertia()
                scrollActive = false
                didScroll = false
                lastScrollCentroid = nil
                scrollTravel = 0
            } else {
                finishScroll(now: now)
            }
            return
        }

        if !scrollActive {
            cancelInertia()
            scrollActive = true
            didScroll = false
            scrollVelocity = 0
            lastScrollFire = 0
            lastScrollSample = now
        }

        let c = centroid(contacts)
        guard let previous = lastScrollCentroid else {
            lastScrollCentroid = c
            lastScrollSample = now
            scrollTravel = 0
            return
        }

        let step = distance(c, previous)
        let dt = max(now - lastScrollSample, 0.001)
        lastScrollCentroid = c
        lastScrollSample = now
        if step > 0.001 {
            let instant = min(step / dt, 3.0)
            scrollVelocity = scrollVelocity == 0 ? instant : scrollVelocity * 0.7 + instant * 0.3
        } else {
            scrollVelocity *= exp(-dt / 0.12)
        }
        guard now - lastScrollFire >= 0.09, step > 0.001 else { return }

        scrollTravel += step
        guard scrollTravel >= 0.02 else { return }
        lastScrollFire = now
        scrollTravel = 0
        didScroll = true
        onScroll?(min(1, max(0.35, scrollVelocity / 1.2)))
    }

    private func finishScroll(now: CFTimeInterval) {
        guard scrollActive else { return }
        scrollActive = false
        lastScrollCentroid = nil
        scrollTravel = 0
        let velocity = scrollVelocity
        let shouldStart = didScroll && velocity > 0.08
        didScroll = false
        guard shouldStart else { return }
        inertiaStartIntensity = min(1, velocity / 1.2)
        inertiaDuration = max(0.05, SettingsStore.shared.hapticScrollInertia)
        inertiaStartedAt = now
        startInertiaTimer()
    }

    private func startInertiaTimer() {
        inertiaTimer?.invalidate()
        let interval = min(0.06, max(0.03, inertiaDuration / 6))
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tickInertia()
        }
        inertiaTimer = timer
    }

    private func tickInertia() {
        guard isRunning, inertiaDuration > 0 else {
            cancelInertia()
            return
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - inertiaStartedAt
        guard elapsed >= 0, elapsed < inertiaDuration else {
            cancelInertia()
            return
        }
        let intensity = inertiaStartIntensity * (1 - elapsed / inertiaDuration)
        guard intensity > 0.08 else {
            cancelInertia()
            return
        }
        onScroll?(intensity)
    }

    private func cancelInertia() {
        inertiaTimer?.invalidate()
        inertiaTimer = nil
        inertiaStartIntensity = 0
        inertiaStartedAt = 0
        inertiaDuration = 0
    }

    private func updateTwoFingerTap(_ contacts: [MTFinger]) {
        if twoFingerActive {
            if contacts.count > 2 {
                twoFingerActive = false
                twoFingerEvaluated = false
                return
            }
            if contacts.count == 2 {
                let c = centroid(contacts)
                twoFingerMaxMovement = max(twoFingerMaxMovement, distance(c, twoFingerStartCentroid))
            } else if !twoFingerEvaluated {
                twoFingerEvaluated = true
                let now = CFAbsoluteTimeGetCurrent()
                let duration = now - twoFingerStart
                if duration < 0.5, twoFingerMaxMovement < 0.06 {
                    lastTwoFingerTap = now
                }
            }
            if contacts.isEmpty {
                twoFingerActive = false
                twoFingerEvaluated = false
            }
            return
        }

        guard !gestureActive else { return }

        if contacts.count == 2 {
            twoFingerActive = true
            twoFingerEvaluated = false
            twoFingerStart = CFAbsoluteTimeGetCurrent()
            twoFingerStartCentroid = centroid(contacts)
            twoFingerMaxMovement = 0
        }
    }

    private func updateThreeFingerGesture(_ contacts: [MTFinger], present: [MTFinger]) {
        guard !pointerActive else {
            gestureActive = false
            return
        }

        if gestureActive {
            if gestureEvaluated, contacts.count >= 3 {
                gestureEvaluated = false
                threeFingerStart = CFAbsoluteTimeGetCurrent()
                threeFingerStartCentroid = centroid(present.isEmpty ? contacts : present)
                threeFingerMaxMovement = 0
            } else if contacts.count >= 3 {
                let c = centroid(present.isEmpty ? contacts : present)
                threeFingerMaxMovement = max(threeFingerMaxMovement, distance(c, threeFingerStartCentroid))
            } else if !gestureEvaluated {
                gestureEvaluated = true
                let now = CFAbsoluteTimeGetCurrent()
                let duration = now - threeFingerStart
                if duration < 0.6, threeFingerMaxMovement < 0.06 {
                    if now - lastTwoFingerTap < 1.0 {
                        lastTwoFingerTap = 0
                        lastThreeFingerTap = 0
                        onGestureConfirmed?()
                        onTwoThenThreeFingerTap?()
                    } else if now - lastThreeFingerTap < 1.5 {
                        lastThreeFingerTap = 0
                        lastTwoFingerTap = 0
                        onGestureConfirmed?()
                        onThreeFingerDoubleTap?()
                    } else {
                        lastThreeFingerTap = now
                    }
                }
            }
            if contacts.isEmpty {
                gestureActive = false
                gestureEvaluated = false
            }
            return
        }

        if contacts.count >= 3 {
            gestureActive = true
            gestureEvaluated = false
            threeFingerStart = CFAbsoluteTimeGetCurrent()
            threeFingerStartCentroid = centroid(present.isEmpty ? contacts : present)
            threeFingerMaxMovement = 0
        }
    }

    private func centroid(_ fingers: [MTFinger]) -> CGPoint {
        var x = 0.0
        var y = 0.0
        for finger in fingers {
            x += finger.x
            y += finger.y
        }
        let n = Double(fingers.count)
        return CGPoint(x: x / n, y: y / n)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    private func choose(from current: [MTFinger]) -> MTFinger {
        if pointerActive {
            return current.min { distance($0, lastPoint) < distance($1, lastPoint) } ?? current[0]
        }
        return current.max { $0.z < $1.z } ?? current[0]
    }

    private func distance(_ finger: MTFinger, _ point: CGPoint) -> Double {
        let dx = finger.x - Double(point.x)
        let dy = finger.y - Double(point.y)
        return dx * dx + dy * dy
    }

    private func scheduleRelease() {
        guard pointerActive, releaseWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pointerActive else { return }
            self.pointerActive = false
            self.releaseWork = nil
            self.onTouch?(0, self.lastPoint, false)
        }
        releaseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func log(_ line: String) {
        logHandler?("[MT] \(line)")
    }
}
