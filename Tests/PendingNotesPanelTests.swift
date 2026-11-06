import AppKit

@main enum PendingNotesPanelTests {
    private static var checks = 0
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(condition(), "FAIL: \(message)")
    }
    private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
    private static func view<T: NSView>(_ id: String, in root: NSView, as type: T.Type) -> T {
        descendants(root).first { $0.identifier?.rawValue == id } as! T
    }
    private static func click(_ id: String, in root: NSView) {
        let button = view(id, in: root, as: NSButton.self)
        expect(NSApp.sendAction(button.action!, to: button.target, from: button), "button action is connected: \(id)")
    }
    private static func submitShortcut(_ input: NSTextView, modifiers: NSEvent.ModifierFlags = .command,
                                       keyCode: UInt16 = 36, throughWindow: Bool = false) -> Bool {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: input.window?.windowNumber ?? 0, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: keyCode)!
        return throughWindow ? input.window!.performKeyEquivalent(with: event) : input.performKeyEquivalent(with: event)
    }
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let now = Date()
        let note = PendingNote(id: "fixture-note", text: "用户的第一行\n第二行保留换行与  空格。", createdAt: now.addingTimeInterval(-125))
        var snapshot = SceneSnapshot.empty(now: now)
        snapshot.pendingNotes = [note]
        var copied: [String] = []
        var copySucceeds = true
        var openCompletions: [(String?) -> Void] = []
        let controller = PendingNotesPanelController(copyText: { text in
            copied.append(text); return copySucceeds
        }, openCodex: { completion in openCompletions.append(completion) })
        var adds: [String] = [], removes: [String] = []
        var undoCount = 0
        controller.onAdd = { adds.append($0) }
        controller.onRemove = { removes.append($0) }
        controller.onUndo = { undoCount += 1 }
        controller.update(snapshot: snapshot, error: nil, canUndo: false)
        let window = controller.window!
        let root = window.contentView!
        root.layoutSubtreeIfNeeded()
        let input = view("pending-note-input", in: root, as: NSTextView.self)
        let preview = view("pending-notes-preview", in: root, as: WorkplaceSceneView.self)
        let message = view("pending-note-message", in: root, as: NSTextField.self)
        let add = view("pending-note-add", in: root, as: NSButton.self)
        let undo = view("pending-note-undo", in: root, as: NSButton.self)
        let text = view("pending-note-text:\(note.id)", in: root, as: NSTextField.self)
        let row = view("pending-note-row:\(note.id)", in: root, as: NSView.self)
        let shortcutHint = view("pending-note-shortcuts", in: root, as: NSTextField.self)
        expect(shortcutHint.stringValue.contains("⌃⌥⌘N") && shortcutHint.stringValue.contains("⌘↩"),
               "the editor shows both the global capture and submit shortcuts")
        controller.setQuickCaptureShortcutAvailable(false)
        expect(shortcutHint.stringValue.contains("全局快捷键不可用")
               && shortcutHint.stringValue.contains("⌘2") && !shortcutHint.stringValue.contains("⌃⌥⌘N"),
               "an unavailable global shortcut shows the existing local fallback")
        controller.setQuickCaptureShortcutAvailable(true)
        expect(!window.isVisible && app.windows.allSatisfy { !$0.isVisible } && !preview.isAnimating,
               "building and updating the panel never activates a window or preview timer")
        expect(preview.background == .outdoors && preview.viewport == .companion(for: .outdoors),
               "the left preview uses the real exterior renderer and companion camera independently of desktop choices")
        expect(preview.snapshot.pendingNotes == [note], "the preview receives the same pending visitors")
        expect(text.stringValue == note.text && text.isSelectable && text.maximumNumberOfLines == 0,
               "the list preserves full selectable multiline task text")
        expect(view("pending-note-wait:\(note.id)", in: root, as: NSTextField.self).stringValue.contains("等待"),
               "each note has a waiting label")
        expect(!add.isEnabled && !undo.isEnabled, "empty input and unavailable undo are disabled")
        expect(preview.frame.width > 300 && preview.frame.height > 180 && input.frame.width > 300,
               "the scene preview and multiline editor have usable native sizes")
        expect(root.bounds.contains(add.convert(add.bounds, to: root))
               && root.bounds.contains(undo.convert(undo.bounds, to: root)),
               "add and undo controls fit within the panel")
        for size in [NSSize(width: 1100, height: 760), NSSize(width: 1000, height: 720)] {
            window.setContentSize(size)
            root.layoutSubtreeIfNeeded()
            for id in ["pending-note-add", "pending-note-undo", "pending-note-copy:\(note.id)",
                       "pending-note-open:\(note.id)", "pending-note-remove:\(note.id)"] {
                let control = view(id, in: root, as: NSButton.self)
                expect(control.frame.width >= 70 && control.frame.height >= 24
                       && root.bounds.contains(control.convert(control.bounds, to: root)),
                       "\(id) stays nonzero and reachable at \(size)")
            }
            expect(input.frame.width >= 300 && input.frame.height >= 120
                   && root.bounds.contains(input.enclosingScrollView!.convert(input.enclosingScrollView!.bounds, to: root)),
                   "the multiline input stays visible at \(size)")
            expect(root.bounds.contains(shortcutHint.convert(shortcutHint.bounds, to: root)),
                   "the shortcut hint remains visible at \(size)")
        }
        window.setContentSize(NSSize(width: 1100, height: 760))
        root.layoutSubtreeIfNeeded()

        click("pending-note-copy:\(note.id)", in: root)
        expect(copied == [note.text] && openCompletions.isEmpty && removes.isEmpty,
               "copy writes exactly the user's stored text and neither opens nor removes the visitor")
        expect(message.stringValue.contains("已复制") && message.stringValue.contains("仍然保留"),
               "clipboard success is described as copied, not sent")
        click("pending-note-open:\(note.id)", in: root)
        expect(copied.last == note.text && openCompletions.count == 1 && removes.isEmpty,
               "open action first copies the original text and never marks it assigned")
        openCompletions.removeFirst()("测试：应用未安装")
        expect(message.stringValue.contains("未能打开 Codex") && message.stringValue.contains("仍保留")
               && preview.snapshot.pendingNotes == [note],
               "launch failure is visible and keeps the note")
        click("pending-note-open:\(note.id)", in: root)
        openCompletions.removeFirst()(nil)
        expect(message.stringValue.contains("手动粘贴") && message.stringValue.contains("已交办") && removes.isEmpty,
               "launch success still requires user paste, send and explicit assignment")
        copySucceeds = false
        click("pending-note-open:\(note.id)", in: root)
        expect(openCompletions.isEmpty && message.stringValue.contains("复制失败") && removes.isEmpty,
               "clipboard failure stops app launch and leaves the pending note intact")
        copySucceeds = true

        func edit(_ string: String) {
            input.string = string
            controller.textDidChange(Notification(name: NSText.didChangeNotification, object: input))
        }
        edit("  待交办的新任务\n保留内部换行  ")
        input.setSelectedRange(NSRange(location: 3, length: 2))
        let selection = input.selectedRange()
        controller.update(snapshot: snapshot, error: nil, canUndo: false)
        expect(view("pending-note-row:\(note.id)", in: root, as: NSView.self) === row
               && view("pending-note-text:\(note.id)", in: root, as: NSTextField.self) === text,
               "heartbeat updates reuse existing row and selectable text views")
        expect(input.selectedRange() == selection && input.string.hasPrefix("  "),
               "heartbeat updates preserve draft content and text selection")
        expect(add.isEnabled, "valid draft enables adding")
        click("pending-note-add", in: root)
        expect(adds == ["待交办的新任务\n保留内部换行"] && !add.isEnabled && !input.string.isEmpty,
               "add normalizes only outer whitespace and keeps the draft until persistence confirms success")
        controller.update(snapshot: snapshot, error: "保存失败：磁盘暂时不可写", canUndo: false)
        expect(message.stringValue.contains("保存失败") && !input.string.isEmpty && add.isEnabled,
               "store failure is visible, retains draft and allows retry")
        click("pending-note-add", in: root)
        controller.didAddNote()
        expect(input.string.isEmpty && !add.isEnabled && message.stringValue.contains("已保存"),
               "only explicit persisted success clears the submitted draft")
        edit("提交中的旧草稿")
        click("pending-note-add", in: root)
        edit("保存等待期间的新草稿")
        controller.didAddNote()
        expect(input.string == "保存等待期间的新草稿", "a newer edit cannot be erased by an older save completion")
        edit(String(repeating: "字", count: PendingNote.maximumTextLength + 1))
        expect(!add.isEnabled && input.string.count == PendingNote.maximumTextLength + 1,
               "over-limit input is preserved for editing but cannot be submitted")
        edit(" \n  ")
        expect(!add.isEnabled, "whitespace-only drafts cannot be submitted")

        click("pending-note-remove:\(note.id)", in: root)
        expect(removes == [note.id] && preview.snapshot.pendingNotes == [note],
               "assigned invokes owner persistence without optimistically deleting a row")
        controller.update(snapshot: snapshot, error: "移除失败，已保留便签", canUndo: false)
        expect(view("pending-note-text:\(note.id)", in: root, as: NSTextField.self).stringValue == note.text
               && message.stringValue.contains("移除失败"), "failed removal retains the full note and reports the error")
        click("pending-note-copy:\(note.id)", in: root)
        expect(message.stringValue.contains("移除失败") && message.stringValue.contains("已复制任务原文"),
               "copy feedback remains visible alongside an unresolved storage error")
        snapshot.pendingNotes = []
        controller.update(snapshot: snapshot, error: nil, canUndo: true)
        expect(undo.isEnabled && descendants(root).contains { $0.identifier?.rawValue == "pending-note-empty" },
               "persisted removal shows empty state and enables the owner's undo")
        click("pending-note-undo", in: root)
        expect(undoCount == 1, "undo invokes only the owner callback")

        snapshot.pendingNotes = (0..<PendingNote.maximumCount).map {
            PendingNote(id: "full-\($0)", text: $0 == 0 ? String(repeating: "完整文字", count: 500) : "任务 \($0)", createdAt: now)
        }
        controller.update(snapshot: snapshot, error: nil, canUndo: false)
        edit("第九条便签")
        expect(!add.isEnabled && view("pending-note-count", in: root, as: NSTextField.self).stringValue.contains("8 / 8"),
               "the full eight-visitor capacity disables adding and displays the count")
        root.layoutSubtreeIfNeeded()
        let longText = view("pending-note-text:full-0", in: root, as: NSTextField.self)
        expect(longText.stringValue.count == 2000 && longText.frame.height > 80,
               "a maximum-length note wraps to its full height rather than a truncated preview")
        let list = view("pending-note-list", in: root, as: NSScrollView.self)
        for size in [NSSize(width: 1100, height: 760), NSSize(width: 1000, height: 720)] {
            window.setContentSize(size)
            root.layoutSubtreeIfNeeded()
            let lastRow = view("pending-note-row:full-7", in: root, as: NSView.self)
            lastRow.scrollToVisible(lastRow.bounds)
            list.reflectScrolledClipView(list.contentView)
            for id in ["pending-note-copy:full-7", "pending-note-open:full-7", "pending-note-remove:full-7"] {
                let control = view(id, in: root, as: NSButton.self)
                expect(control.frame.width >= 70 && control.frame.height >= 24
                       && list.contentView.bounds.contains(control.convert(control.bounds, to: list.contentView)),
                       "the last note's \(id) can be scrolled into view at \(size)")
            }
        }
        window.setContentSize(NSSize(width: 1100, height: 760))
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("VirtualWorkplace-pending-panel-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: output) }
        try controller.renderPreview(to: output, snapshot: snapshot, error: "测试保存错误：便签仍保留")
        let imageData = try Data(contentsOf: output)
        expect(imageData.count > 10_000, "the hidden production panel renders a review image")
        expect(NSBitmapImageRep(data: imageData)!.colorAt(x: 10, y: 10)!.alphaComponent == 1,
               "the panel review image has an opaque paper background")
        expect(!window.isVisible && !preview.isAnimating && app.windows.allSatisfy { !$0.isVisible },
               "isolated UI checks never open real Codex, touch the clipboard or activate windows")
        let weatherLabel = view("pending-note-weather", in: root, as: NSTextField.self)
        var weatherSnapshot = SceneSnapshot.empty(now: now)
        weatherSnapshot.world = SceneWorld(weather: .clear, timeMode: .day)
        weatherSnapshot.pendingNotes = [note]
        controller.update(snapshot: weatherSnapshot, error: nil, canUndo: false)
        expect(weatherLabel.stringValue.contains("随机轮换") && weatherLabel.stringValue.contains("不受待办等待时长影响")
               && !weatherLabel.stringValue.contains("转阴"),
               "the note preview describes independent random weather without overdue thresholds")
        let initialWeather = preview.snapshot.effectiveWorld(at: now).weather
        weatherSnapshot.pendingNotes = [PendingNote(id: "weather-overdue", text: "天气等待测试",
            createdAt: now.addingTimeInterval(-5 * 3600))]
        controller.update(snapshot: weatherSnapshot, error: nil, canUndo: false)
        expect(weatherLabel.stringValue.contains("随机轮换")
               && preview.snapshot.effectiveWorld(at: now).weather == initialWeather
               && preview.snapshot.world?.weather == .clear,
               "overdue notes retain the same random calendar and never overwrite manual weather")
        weatherSnapshot.world?.weatherMode = .manual
        weatherSnapshot.world?.weather = .rain
        controller.update(snapshot: weatherSnapshot, error: nil, canUndo: false)
        expect(weatherLabel.stringValue.contains("手动固定") && weatherLabel.stringValue.contains(WorldWeather.rain.title)
               && preview.snapshot.effectiveWorld(at: now).weather == .rain,
               "manual rain stays selected even when a note is overdue")
        weatherSnapshot.pendingNotes = []
        controller.update(snapshot: weatherSnapshot, error: nil, canUndo: false)
        expect(weatherLabel.stringValue.contains("手动固定") && preview.snapshot.effectiveWorld(at: now).weather == .rain,
               "clearing the inbox does not change the manually selected weather")
        for size in [NSSize(width: 1100, height: 760), NSSize(width: 1000, height: 720)] {
            window.setContentSize(size); root.layoutSubtreeIfNeeded()
            expect(weatherLabel.frame.height > 20 && root.bounds.contains(weatherLabel.convert(weatherLabel.bounds, to: root))
                   && add.frame.height >= 24 && root.bounds.contains(add.convert(add.bounds, to: root)),
                   "weather explanation and add button remain visible at \(size)")
        }
        window.setContentSize(NSSize(width: 1100, height: 760))
        if let index = CommandLine.arguments.firstIndex(of: "--review-output"),
           index + 1 < CommandLine.arguments.count {
            snapshot.pendingNotes = [note, PendingNote(id: "review-second",
                text: "检查双屏的天气和昼夜是否保持同步。\n完成后记录观察结果，再标记为已交办。",
                createdAt: now.addingTimeInterval(-7_440))]
            edit("把下一件要交办的事写在这里。")
            try controller.renderPreview(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]),
                snapshot: snapshot, canUndo: true)
        }
        controller.close()
        expect(!preview.isAnimating, "closing the auxiliary panel stops its preview")

        let quick = PendingNotesPanelController(copyText: { _ in false }, openCodex: { _ in })
        let quickRoot = quick.window!.contentView!
        let quickInput = view("pending-note-input", in: quickRoot, as: NSTextView.self)
        let quickMessage = view("pending-note-message", in: quickRoot, as: NSTextField.self)
        var quickAdds: [String] = []
        quick.onAdd = { quickAdds.append($0) }
        var quickSnapshot = SceneSnapshot.empty(now: now)
        quick.update(snapshot: quickSnapshot, error: nil, canUndo: false)
        func quickEdit(_ draft: String) {
            quickInput.string = draft
            quick.textDidChange(Notification(name: NSText.didChangeNotification, object: quickInput))
        }
        quickEdit("第一行")
        quickInput.setSelectedRange(NSRange(location: quickInput.string.utf16.count, length: 0))
        quickInput.insertNewline(nil)
        expect(quickInput.string == "第一行\n" && quickAdds.isEmpty,
               "ordinary Return remains a newline and never submits")
        quickEdit("  快捷添加\n保留第二行  ")
        quick.window!.makeFirstResponder(nil)
        expect(!submitShortcut(quickInput) && quickAdds.isEmpty,
               "an unfocused editor never captures another control's submit shortcut")
        expect(quick.window!.makeFirstResponder(quickInput), "quick capture can focus the draft editor")
        expect(submitShortcut(quickInput, throughWindow: true) && quickAdds == ["快捷添加\n保留第二行"],
               "window-level Command Return routes to the focused draft's persistence callback")
        _ = submitShortcut(quickInput)
        expect(quickAdds.count == 1 && quickInput.string.hasPrefix("  "),
               "repeated submit shortcuts never duplicate an in-flight note or clear its draft")
        quick.update(snapshot: quickSnapshot, error: "快捷保存失败", canUndo: false)
        expect(quickInput.string.hasPrefix("  ") && quickMessage.stringValue.contains("保存失败"),
               "shortcut save failures keep the draft and existing error feedback")
        expect(submitShortcut(quickInput, keyCode: 76) && quickAdds.count == 2,
               "Command keypad Enter also retries a valid draft")
        quick.didAddNote()
        expect(quickInput.string.isEmpty, "a shortcut clears text only after persistence confirms success")
        quickEdit("  \n ")
        _ = submitShortcut(quickInput)
        expect(quickAdds.count == 2, "the shortcut rejects blank drafts")
        quickEdit(String(repeating: "字", count: PendingNote.maximumTextLength + 1))
        _ = submitShortcut(quickInput)
        expect(quickAdds.count == 2 && quickInput.string.count == PendingNote.maximumTextLength + 1,
               "the shortcut rejects over-length drafts without losing text")
        quickSnapshot.pendingNotes = (0..<PendingNote.maximumCount).map {
            PendingNote(id: "shortcut-full-\($0)", text: "任务\($0)", createdAt: now)
        }
        quick.update(snapshot: quickSnapshot, error: nil, canUndo: false)
        quickEdit("满员后的草稿")
        _ = submitShortcut(quickInput)
        expect(quickAdds.count == 2 && quickMessage.stringValue.contains("8 位访客"),
               "the shortcut respects the shared eight-note capacity")
        quickSnapshot.pendingNotes = []
        quick.update(snapshot: quickSnapshot, error: nil, canUndo: false)
        quickEdit("")
        quickInput.setMarkedText("输入中的拼音", selectedRange: NSRange(location: 6, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: 0))
        expect(quickInput.hasMarkedText(), "the composition fixture has active marked text")
        _ = submitShortcut(quickInput)
        expect(quickAdds.count == 2 && quickInput.hasMarkedText(),
               "Command Return does not submit an unfinished Chinese composition")
        quickInput.unmarkText()
        quickEdit("Esc 收起后保留的草稿")
        quickInput.cancelOperation(nil)
        expect(quickInput.string == "Esc 收起后保留的草稿" && quickAdds.count == 2 && !quick.window!.isVisible,
               "Escape dismisses the panel without submitting or erasing the draft")
        quick.update(snapshot: quickSnapshot, error: nil, canUndo: false)
        expect(quickInput.string == "Esc 收起后保留的草稿"
               && quick.window!.makeFirstResponder(quickInput) && quick.window!.firstResponder === quickInput,
               "refresh and editor refocus preserve a dismissed draft")
        quick.close()
        print("PASS: \(checks) pending-note panel, exact-copy, launch failure, draft preservation and lifecycle checks; no real clipboard, app launch or state writes")
    }
}
