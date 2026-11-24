import CoreFoundation
import Darwin
import Foundation

private typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>?
private typealias GetDeviceIDFn = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
private typealias IsBuiltInFn = @convention(c) (UnsafeMutableRawPointer) -> Bool
private typealias ActuatorCreateFn = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
private typealias ActuatorOpenFn = @convention(c) (CFTypeRef) -> Int32
private typealias ActuatorCloseFn = @convention(c) (CFTypeRef) -> Int32
private typealias ActuatorActuateFn = @convention(c) (CFTypeRef, Int32, UInt32, Float, Float) -> Int32

final class MultitouchHapticActuator {
    private var handle: UnsafeMutableRawPointer?
    private var deviceList: CFArray?
    private var deviceID: UInt64?

    private var createActuator: ActuatorCreateFn?
    private var openActuator: ActuatorOpenFn?
    private var closeActuator: ActuatorCloseFn?
    private var actuateActuator: ActuatorActuateFn?

    init() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW) else {
            return
        }
        self.handle = handle

        func sym<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }

        createActuator = sym("MTActuatorCreateFromDeviceID", as: ActuatorCreateFn.self)
        openActuator = sym("MTActuatorOpen", as: ActuatorOpenFn.self)
        closeActuator = sym("MTActuatorClose", as: ActuatorCloseFn.self)
        actuateActuator = sym("MTActuatorActuate", as: ActuatorActuateFn.self)

        guard createActuator != nil, openActuator != nil, closeActuator != nil, actuateActuator != nil else {
            return
        }

        deviceID = discoverDeviceID()
    }

    deinit {
        if let handle {
            dlclose(handle)
        }
    }

    @discardableResult
    func actuate(waveform: Int32, strength: Double) -> Bool {
        guard let deviceID,
              let createActuator,
              let openActuator,
              let closeActuator,
              let actuateActuator else {
            return false
        }
        guard let actuator = createActuator(deviceID)?.takeRetainedValue() else {
            return false
        }
        guard openActuator(actuator) == 0 else {
            return false
        }
        defer { _ = closeActuator(actuator) }

        let level = Float(max(0.1, min(1.0, strength)))
        return actuateActuator(actuator, waveform, 0, level, 0) == 0
    }

    private func discoverDeviceID() -> UInt64? {
        guard let handle = handle else { return nil }

        func sym<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }

        let createList = sym("MTDeviceCreateList", as: CreateListFn.self)
        let getDeviceID = sym("MTDeviceGetDeviceID", as: GetDeviceIDFn.self)
        let isBuiltIn = sym("MTDeviceIsBuiltIn", as: IsBuiltInFn.self)
        guard let createList, let list = createList()?.takeRetainedValue() else {
            return nil
        }
        deviceList = list

        var fallback: UInt64?
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)

            var id: UInt64 = 0
            if let getDeviceID {
                guard getDeviceID(device, &id) == 0 else { continue }
            } else {
                id = device.load(fromByteOffset: 64, as: UInt64.self)
            }
            guard id != 0 else { continue }
            if isBuiltIn?(device) == true {
                return id
            }
            if fallback == nil {
                fallback = id
            }
        }
        return fallback
    }
}
