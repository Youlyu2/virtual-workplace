import AppKit
import Carbon

/// Registers one explicit system hot key rather than observing keyboard input.
/// Owned by the menu-bar app; the saver never installs keyboard handlers.
final class QuickNoteHotKey {
    static let displayShortcut = "⌃⌥⌘N"
    private static let signature: OSType = 0x56574E54 // VWNT
    private static let identifier: UInt32 = 1
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var onPress: (() -> Void)?
    private var isPressed = false
    private(set) var registrationStatus: OSStatus?
    var isRegistered: Bool { hotKey != nil }

    @discardableResult
    func start(onPress: @escaping () -> Void) -> OSStatus {
        precondition(Thread.isMainThread)
        self.onPress = onPress
        if isRegistered { return noErr }
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            return Unmanaged<QuickNoteHotKey>.fromOpaque(context).takeUnretainedValue().receive(event)
        }, types.count, &types, context, &handler)
        guard installed == noErr else {
            registrationStatus = installed
            self.onPress = nil
            return installed
        }
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey | cmdKey),
            EventHotKeyID(signature: Self.signature, id: Self.identifier), GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &hotKey)
        registrationStatus = status
        if status != noErr { removeRegistration() }
        return status
    }

    func stop() {
        precondition(Thread.isMainThread)
        removeRegistration()
        registrationStatus = nil
    }

    deinit { removeRegistration() }

    private func removeRegistration() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil; handler = nil; onPress = nil; isPressed = false
    }

    private func receive(_ event: EventRef) -> OSStatus {
        guard isRegistered, GetEventClass(event) == OSType(kEventClassKeyboard) else {
            return OSStatus(eventNotHandledErr)
        }
        var id = EventHotKeyID()
        let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
        guard result == noErr, id.signature == Self.signature, id.id == Self.identifier else {
            return OSStatus(eventNotHandledErr)
        }
        switch GetEventKind(event) {
        case UInt32(kEventHotKeyPressed):
            if !isPressed { isPressed = true; onPress?() }
            return noErr
        case UInt32(kEventHotKeyReleased):
            isPressed = false
            return noErr
        default: return OSStatus(eventNotHandledErr)
        }
    }
}
