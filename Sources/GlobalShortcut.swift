import Carbon

final class GlobalShortcut {
    private var registration: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init?(action: @escaping () -> Void) {
        self.action = action
        guard let target = GetEventDispatcherTarget() else { return nil }
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(target, { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr, identifier.signature == 0x4D4D6163, identifier.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
                DispatchQueue.main.async(execute: shortcut.action)
            }
            return noErr
        }, events.count, &events, context, &handler) == noErr else { return nil }

        let identifier = EventHotKeyID(signature: 0x4D4D6163, id: 1)
        if RegisterEventHotKey(UInt32(kVK_ANSI_M), UInt32(cmdKey | controlKey | shiftKey),
                               identifier, target, UInt32(kEventHotKeyExclusive), &registration) != noErr {
            if let handler { RemoveEventHandler(handler) }
            handler = nil
            return nil
        }
    }

    deinit {
        if let registration { UnregisterEventHotKey(registration) }
        if let handler { RemoveEventHandler(handler) }
    }
}
