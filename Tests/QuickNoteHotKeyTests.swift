import AppKit
import Carbon

@main
struct QuickNoteHotKeyTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fatalError(message) }
    }
    static func send(_ kind: UInt32, signature: OSType = 0x56574E54, id: UInt32 = 1) {
        var event: EventRef?
        expect(CreateEvent(nil, OSType(kEventClassKeyboard), kind, 0, 0, &event) == noErr, "create isolated hotkey event")
        guard let event else { fatalError("missing event") }
        defer { ReleaseEvent(event) }
        var value = EventHotKeyID(signature: signature, id: id)
        expect(SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            MemoryLayout<EventHotKeyID>.size, &value) == noErr, "set hotkey identity")
        _ = SendEventToEventTarget(event, GetApplicationEventTarget())
    }
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let first = QuickNoteHotKey(), second = QuickNoteHotKey()
        var presses = 0
        expect(first.start { presses += 10 } == noErr && first.isRegistered, "register global quick capture")
        expect(first.start { presses += 1 } == noErr, "repeated start reuses registration")
        send(UInt32(kEventHotKeyPressed)); send(UInt32(kEventHotKeyPressed))
        expect(presses == 1, "held or repeated keydown only opens once")
        send(UInt32(kEventHotKeyReleased)); send(UInt32(kEventHotKeyPressed))
        expect(presses == 2, "next physical keypress opens again")
        send(UInt32(kEventHotKeyReleased)); send(UInt32(kEventHotKeyPressed), id: 999)
        send(UInt32(kEventHotKeyPressed), signature: 0x11111111)
        expect(presses == 2, "other hotkey identities are ignored")
        expect(second.start {} == OSStatus(eventHotKeyExistsErr) && !second.isRegistered,
            "conflicting registration fails without replacing the owner")
        first.stop(); first.stop()
        expect(!first.isRegistered && first.registrationStatus == nil, "stop is idempotent")
        expect(second.start { presses += 1 } == noErr && second.isRegistered, "failed registration can retry after release")
        send(UInt32(kEventHotKeyPressed))
        expect(presses == 3, "retry has exactly one live callback")
        second.stop()
        do {
            let temporary = QuickNoteHotKey()
            expect(temporary.start {} == noErr, "temporary registration succeeds")
        }
        expect(first.start {} == noErr, "deinit releases global registration and handler")
        first.stop()
        print("PASS: \(checks) global quick-note dispatch, conflict, repeat and cleanup checks")
    }
}
