import Carbon

final class GlobalHotKey: @unchecked Sendable {
    private let id: EventHotKeyID
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    var onPress: (@MainActor @Sendable () -> Void)?

    init(keyCode: UInt32 = UInt32(kVK_ANSI_W), modifiers: UInt32 = UInt32(controlKey | optionKey)) {
        id = EventHotKeyID(signature: OSType(0x54534C4B), id: 1)

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()

                var pressedID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedID
                )
                guard status == noErr,
                      pressedID.signature == hotKey.id.signature,
                      pressedID.id == hotKey.id.id else {
                    return OSStatus(eventNotHandledErr)
                }

                Task { @MainActor in
                    hotKey.onPress?()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
