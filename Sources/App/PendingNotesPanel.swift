import AppKit

private final class PendingNotesButton: NSButton {
    var handler: (() -> Void)?
    convenience init(_ title: String, identifier: String, handler: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        self.identifier = NSUserInterfaceItemIdentifier(identifier)
        self.handler = handler
        bezelStyle = .rounded
        translatesAutoresizingMaskIntoConstraints = false
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
            widthAnchor.constraint(greaterThanOrEqualToConstant: max(80, intrinsicContentSize.width))
        ])
        target = self
        action = #selector(invoke)
    }
    @objc private func invoke() { handler?() }
}

private final class PendingNotesRows: NSStackView {
    override var isFlipped: Bool { true }
}

private final class PendingNotesRoot: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.96, green: 0.95, blue: 0.92, alpha: 1).setFill()
        bounds.fill()
    }
}

private final class PendingNoteInput: NSTextView {
    var onSubmit: (() -> Void)?
    var onDismiss: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command && (event.keyCode == 36 || event.keyCode == 76) {
            // Let the input method finish its composition before a later
            // explicit shortcut can submit the complete draft.
            guard !hasMarkedText() else { return false }
            onSubmit?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        guard !hasMarkedText() else { super.cancelOperation(sender); return }
        onDismiss?()
    }
}

/// The panel prepares text for a user-controlled handoff. Clipboard or launch
/// success never assigns, sends, or removes a pending note.
final class PendingNotesPanelController: NSWindowController, NSTextViewDelegate, NSWindowDelegate {
    typealias CopyText = (String) -> Bool
    typealias OpenCodex = (@escaping (String?) -> Void) -> Void

    var onAdd: ((String) -> Void)?
    var onRemove: ((String) -> Void)?
    var onUndo: (() -> Void)?

    private let copyText: CopyText
    private let openCodex: OpenCodex
    private let preview = WorkplaceSceneView(frame: .zero)
    private let input = PendingNoteInput(frame: .zero)
    private let rows = PendingNotesRows()
    private let countLabel = NSTextField(labelWithString: "")
    private let draftCount = NSTextField(labelWithString: "")
    private let weatherLabel = NSTextField(wrappingLabelWithString: "")
    private let shortcutHint = NSTextField(labelWithString: "⌃⌥⌘N 快速记录 · ⌘↩ 添加 · Esc 收起")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private var addButton: NSButton!
    private var undoButton: NSButton!
    private var notes: [PendingNote] = []
    private var hasRenderedRows = false
    private var waitingLabels: [String: NSTextField] = [:]
    private var pendingDraft: String?
    private var canUndo = false
    private var storeError: String?
    private var actionMessage = ""
    private var actionIsError = false
    private var actionToken = UUID()

    private static let ink = NSColor(srgbRed: 0.17, green: 0.23, blue: 0.22, alpha: 1)
    private static let muted = NSColor(srgbRed: 0.43, green: 0.47, blue: 0.43, alpha: 1)
    private static let green = NSColor(srgbRed: 0.24, green: 0.44, blue: 0.33, alpha: 1)
    private static let red = NSColor(srgbRed: 0.65, green: 0.24, blue: 0.17, alpha: 1)

    init(copyText: @escaping CopyText = PendingNotesPanelController.writeClipboard,
         openCodex: @escaping OpenCodex = PendingNotesPanelController.launchCodex) {
        self.copyText = copyText
        self.openCodex = openCodex
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "门外待办"
        window.contentMinSize = NSSize(width: 1000, height: 720)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor(srgbRed: 0.96, green: 0.95, blue: 0.92, alpha: 1)
        window.delegate = self
        window.center()
        buildInterface(in: window)
        refreshInputControls()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setQuickCaptureShortcutAvailable(_ available: Bool) {
        shortcutHint.stringValue = available
            ? "⌃⌥⌘N 快速记录 · ⌘↩ 添加 · Esc 收起"
            : "全局快捷键不可用 · ⌘2 打开 · ⌘↩ 添加 · Esc 收起"
    }

    func show(snapshot: SceneSnapshot) {
        update(snapshot: snapshot, error: storeError, canUndo: canUndo)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(input)
    }

    /// Heartbeats refresh waiting labels and the actual exterior preview, but
    /// do not replace rows or editable controls unless note content changes.
    func update(snapshot: SceneSnapshot, error: String?, canUndo: Bool) {
        preview.snapshot = snapshot
        refreshWeather(snapshot: snapshot, at: Date())
        self.canUndo = canUndo
        storeError = error
        if error != nil {
            if pendingDraft != nil { actionMessage = ""; actionIsError = false }
            pendingDraft = nil
        }
        let updated = snapshot.pendingNotes ?? []
        if !hasRenderedRows || notes != updated {
            notes = updated
            rebuildRows()
            hasRenderedRows = true
        }
        let now = Date()
        for note in notes { waitingLabels[note.id]?.stringValue = note.waitingLabel(at: now) }
        countLabel.stringValue = "等候中的访客  \(notes.count) / \(PendingNote.maximumCount)"
        undoButton.isEnabled = canUndo && onUndo != nil
        refreshInputControls()
        refreshMessage()
    }

    /// The owner calls this only after persistence succeeds. Preserve any
    /// newer edit if saving was asynchronous and the draft changed meanwhile.
    func didAddNote() {
        if let pendingDraft, input.string == pendingDraft {
            input.string = ""
            input.setSelectedRange(NSRange(location: 0, length: 0))
        }
        pendingDraft = nil
        storeError = nil
        setMessage("便签已保存，访客会一直等到你标记「已交办」。")
        refreshInputControls()
    }

    override func close() {
        preview.stopAnimating()
        super.close()
    }

    func windowWillClose(_ notification: Notification) { preview.stopAnimating() }

    func textDidChange(_ notification: Notification) {
        guard notification.object as? NSTextView === input else { return }
        refreshInputControls()
    }

    /// Produces a review image without ordering a window or launching Codex.
    func renderPreview(to output: URL, snapshot: SceneSnapshot, error: String? = nil,
                       canUndo: Bool = false) throws {
        update(snapshot: snapshot, error: error, canUndo: canUndo)
        guard let root = window?.contentView else { return }
        root.layoutSubtreeIfNeeded()
        rows.layoutSubtreeIfNeeded()
        root.layoutSubtreeIfNeeded()
        guard let image = root.bitmapImageRepForCachingDisplay(in: root.bounds) else {
            throw NSError(domain: "VirtualWorkplace.PendingNotes", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "无法创建门外便签预览"])
        }
        root.cacheDisplay(in: root.bounds, to: image)
        guard let data = image.representation(using: .png, properties: [:]) else { return }
        try data.write(to: output, options: .atomic)
    }

    private func buildInterface(in window: NSWindow) {
        let root = PendingNotesRoot()
        root.wantsLayer = true
        root.layer?.backgroundColor = window.backgroundColor.cgColor
        window.contentView = root
        let title = label("门外待办", size: 25, weight: .semibold)
        let explanation = label("写下还没交办的事，让访客替你记着。最多 8 位访客，每条最多 2000 字。", size: 13, color: Self.muted)
        [title, explanation].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; root.addSubview($0) }

        let left = NSStackView()
        left.orientation = .vertical; left.alignment = .leading; left.spacing = 8
        left.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(left)
        let right = NSStackView()
        right.orientation = .vertical; right.alignment = .leading; right.spacing = 10
        right.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(right)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            explanation.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            explanation.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
            explanation.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),
            left.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            left.topAnchor.constraint(equalTo: explanation.bottomAnchor, constant: 24),
            left.widthAnchor.constraint(equalToConstant: 410),
            right.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 24),
            right.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            right.topAnchor.constraint(equalTo: left.topAnchor),
            right.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -112)
        ])
        left.addArrangedSubview(label("门外实景", size: 14, weight: .semibold))
        preview.identifier = NSUserInterfaceItemIdentifier("pending-notes-preview")
        preview.background = .outdoors
        preview.viewport = .companion(for: .outdoors)
        preview.maximumFramesPerSecond = 15
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 8; preview.layer?.masksToBounds = true
        preview.translatesAutoresizingMaskIntoConstraints = false
        left.addArrangedSubview(preview)
        NSLayoutConstraint.activate([
            preview.widthAnchor.constraint(equalTo: left.widthAnchor),
            preview.heightAnchor.constraint(equalTo: preview.widthAnchor, multiplier: 9.0 / 16.0)
        ])
        weatherLabel.identifier = NSUserInterfaceItemIdentifier("pending-note-weather")
        weatherLabel.font = .systemFont(ofSize: 11)
        weatherLabel.textColor = Self.muted
        weatherLabel.maximumNumberOfLines = 2
        weatherLabel.translatesAutoresizingMaskIntoConstraints = false
        left.addArrangedSubview(weatherLabel)
        weatherLabel.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true
        let editorHeading = NSStackView()
        editorHeading.orientation = .horizontal; editorHeading.alignment = .centerY; editorHeading.spacing = 10
        editorHeading.addArrangedSubview(label("新便签", size: 14, weight: .semibold))
        shortcutHint.identifier = NSUserInterfaceItemIdentifier("pending-note-shortcuts")
        shortcutHint.font = .systemFont(ofSize: 10)
        shortcutHint.textColor = Self.muted
        shortcutHint.toolTip = "在其他应用中按 Control + Option + Command + N 快速记录；输入后按 Command + Return 添加，Return 换行。Esc 收起并保留草稿。"
        editorHeading.addArrangedSubview(shortcutHint)
        left.addArrangedSubview(editorHeading)
        let editor = NSScrollView()
        editor.hasVerticalScroller = true; editor.autohidesScrollers = true
        editor.borderType = .bezelBorder
        editor.translatesAutoresizingMaskIntoConstraints = false
        input.identifier = NSUserInterfaceItemIdentifier("pending-note-input")
        input.isRichText = false; input.isAutomaticQuoteSubstitutionEnabled = false
        input.isAutomaticDashSubstitutionEnabled = false
        input.isAutomaticTextReplacementEnabled = false
        input.font = .systemFont(ofSize: 14); input.textColor = Self.ink
        input.backgroundColor = NSColor(srgbRed: 0.995, green: 0.99, blue: 0.97, alpha: 1)
        input.textContainerInset = NSSize(width: 9, height: 9)
        input.isVerticallyResizable = true; input.isHorizontallyResizable = false
        input.autoresizingMask = [.width]
        input.minSize = NSSize(width: 0, height: 120)
        input.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        input.textContainer?.containerSize = NSSize(width: 390, height: CGFloat.greatestFiniteMagnitude)
        input.textContainer?.widthTracksTextView = true
        input.delegate = self
        input.onSubmit = { [weak self] in self?.addDraft() }
        input.onDismiss = { [weak self] in self?.close() }
        input.setAccessibilityLabel("新便签内容，最多2000字")
        editor.documentView = input
        left.addArrangedSubview(editor)
        NSLayoutConstraint.activate([
            editor.widthAnchor.constraint(equalTo: left.widthAnchor),
            // Keep 120 points of editable content inside the scroll bezel.
            editor.heightAnchor.constraint(equalToConstant: 122)
        ])
        draftCount.identifier = NSUserInterfaceItemIdentifier("pending-note-draft-count")
        draftCount.font = .systemFont(ofSize: 11)
        left.addArrangedSubview(draftCount)
        addButton = PendingNotesButton("添加访客", identifier: "pending-note-add") { [weak self] in self?.addDraft() }
        addButton.contentTintColor = Self.green
        addButton.toolTip = "添加便签（⌘↩）；Return 换行"
        left.addArrangedSubview(addButton)

        countLabel.identifier = NSUserInterfaceItemIdentifier("pending-note-count")
        countLabel.font = .systemFont(ofSize: 15, weight: .semibold); countLabel.textColor = Self.ink
        right.addArrangedSubview(countLabel)
        let list = NSScrollView()
        list.identifier = NSUserInterfaceItemIdentifier("pending-note-list")
        list.drawsBackground = false; list.hasVerticalScroller = true; list.autohidesScrollers = true
        list.borderType = .noBorder; list.translatesAutoresizingMaskIntoConstraints = false
        rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 14
        rows.translatesAutoresizingMaskIntoConstraints = false
        list.documentView = rows
        right.addArrangedSubview(list)
        NSLayoutConstraint.activate([
            list.widthAnchor.constraint(equalTo: right.widthAnchor),
            list.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),
            rows.leadingAnchor.constraint(equalTo: list.contentView.leadingAnchor, constant: 2),
            rows.trailingAnchor.constraint(equalTo: list.contentView.trailingAnchor, constant: -10),
            rows.topAnchor.constraint(equalTo: list.contentView.topAnchor)
        ])
        list.setContentHuggingPriority(.init(1), for: .vertical)

        let footer = NSStackView()
        footer.orientation = .horizontal; footer.alignment = .centerY; footer.spacing = 12
        footer.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(footer)
        let footerText = label("复制后请在 Codex 中粘贴并发送。点击「已交办」前，便签和访客一直保留。", size: 12, color: Self.muted)
        footerText.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(footerText)
        undoButton = PendingNotesButton("撤销上次离开", identifier: "pending-note-undo") { [weak self] in
            guard let self, self.canUndo else { return }
            self.onUndo?()
        }
        undoButton.toolTip = "恢复最近一位标记为已交办的访客；复制不会让访客离开"
        footer.addArrangedSubview(undoButton)
        messageLabel.identifier = NSUserInterfaceItemIdentifier("pending-note-message")
        messageLabel.font = .systemFont(ofSize: 12); messageLabel.isSelectable = true
        messageLabel.maximumNumberOfLines = 3
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(messageLabel)
        NSLayoutConstraint.activate([
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -66),
            left.bottomAnchor.constraint(lessThanOrEqualTo: footer.topAnchor, constant: -14),
            messageLabel.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            messageLabel.topAnchor.constraint(equalTo: footer.bottomAnchor, constant: 8),
            messageLabel.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -14)
        ])
    }

    private func rebuildRows() {
        for view in rows.arrangedSubviews { rows.removeArrangedSubview(view); view.removeFromSuperview() }
        waitingLabels.removeAll()
        if notes.isEmpty {
            let empty = label("门外还没有访客。\n写一条便签，把暂时没交办的事放在这里。", size: 14, color: Self.muted)
            empty.identifier = NSUserInterfaceItemIdentifier("pending-note-empty")
            rows.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
            return
        }
        for note in notes {
            let card = NSStackView()
            card.identifier = NSUserInterfaceItemIdentifier("pending-note-row:\(note.id)")
            card.orientation = .vertical; card.alignment = .leading; card.spacing = 9
            card.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
            card.wantsLayer = true
            card.layer?.backgroundColor = NSColor(srgbRed: 0.995, green: 0.985, blue: 0.945, alpha: 1).cgColor
            card.layer?.cornerRadius = 8
            card.translatesAutoresizingMaskIntoConstraints = false
            let waiting = label(note.waitingLabel(at: Date()), size: 11, color: Self.muted)
            waiting.identifier = NSUserInterfaceItemIdentifier("pending-note-wait:\(note.id)")
            waitingLabels[note.id] = waiting
            card.addArrangedSubview(waiting)
            let text = label(note.text, size: 14)
            text.identifier = NSUserInterfaceItemIdentifier("pending-note-text:\(note.id)")
            text.isSelectable = true
            text.maximumNumberOfLines = 0
            text.setContentCompressionResistancePriority(.required, for: .vertical)
            card.addArrangedSubview(text)
            text.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -28).isActive = true
            let actions = NSStackView()
            actions.orientation = .horizontal; actions.spacing = 8
            actions.addArrangedSubview(PendingNotesButton("复制任务", identifier: "pending-note-copy:\(note.id)") { [weak self] in
                self?.copyNote(id: note.id, open: false)
            })
            actions.addArrangedSubview(PendingNotesButton("复制并打开 Codex", identifier: "pending-note-open:\(note.id)") { [weak self] in
                self?.copyNote(id: note.id, open: true)
            })
            actions.addArrangedSubview(PendingNotesButton("已交办", identifier: "pending-note-remove:\(note.id)") { [weak self] in
                guard let self, self.notes.contains(where: { $0.id == note.id }) else { return }
                self.onRemove?(note.id)
            })
            card.addArrangedSubview(actions)
            rows.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
    }

    private func addDraft() {
        guard pendingDraft == nil else { return }
        guard notes.count < PendingNote.maximumCount else {
            setMessage("门外已有 8 位访客，请先交办一条便签。", error: true); return
        }
        do {
            let text = try PendingNote.normalizedText(input.string)
            guard let onAdd else { setMessage("暂时无法保存便签，请重新打开面板。", error: true); return }
            storeError = nil
            pendingDraft = input.string
            setMessage("正在保存便签…")
            refreshInputControls()
            onAdd(text)
        } catch { setMessage(error.localizedDescription, error: true) }
    }

    private func copyNote(id: String, open: Bool) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        actionToken = UUID()
        let token = actionToken
        guard copyText(note.text) else {
            setMessage("复制失败，请重试。便签和访客仍然保留。", error: true); return
        }
        if !open {
            setMessage("已复制任务原文。请在 Codex 中粘贴并发送；访客仍然保留。")
            return
        }
        setMessage("已复制任务原文，正在打开 Codex…")
        openCodex { [weak self] error in
            let complete = {
                guard let self, self.actionToken == token else { return }
                if let error {
                    self.setMessage("已复制，但未能打开 Codex：\(error)。请手动打开后粘贴；访客仍保留。", error: true)
                } else {
                    self.setMessage("已复制并打开 Codex。请手动粘贴、发送，交办后再点击「已交办」。")
                }
            }
            if Thread.isMainThread { complete() } else { DispatchQueue.main.async(execute: complete) }
        }
    }

    private func refreshInputControls() {
        let count = input.string.count
        draftCount.stringValue = "\(count) / \(PendingNote.maximumTextLength) 字"
        draftCount.textColor = count > PendingNote.maximumTextLength ? Self.red : Self.muted
        addButton.title = pendingDraft == nil ? "添加访客" : "正在保存…"
        addButton.isEnabled = pendingDraft == nil && notes.count < PendingNote.maximumCount
            && count <= PendingNote.maximumTextLength
            && !input.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func refreshWeather(snapshot: SceneSnapshot, at date: Date) {
        let world = snapshot.world ?? SceneWorld()
        let effect = snapshot.pendingWeatherEffect(at: date)
        let text: String
        if !world.pendingWeatherEnabled {
            text = "待办天气已关闭 · 当前\(world.weather.title)\n天气保持你设置的基础值。"
        } else if let reason = effect.reason {
            text = "待办天气：\(effect.weather.title)\n\(reason)"
        } else {
            let pace = world.pendingWeatherPace
            text = "待办天气：\(effect.weather.title)\n\(Self.duration(pace.cloudyAfter))转阴 · \(Self.duration(pace.rainAfter))下雨 · \(Self.duration(pace.stormAfter))雷雨"
        }
        if weatherLabel.stringValue != text { weatherLabel.stringValue = text }
        weatherLabel.toolTip = text
    }

    private static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval / 60))
        if minutes < 60 { return "\(minutes)分钟" }
        return minutes % 60 == 0 ? "\(minutes / 60)小时" : "\(minutes / 60)小时\(minutes % 60)分钟"
    }

    private func setMessage(_ message: String, error: Bool = false) {
        actionMessage = message; actionIsError = error
        refreshMessage()
    }

    private func refreshMessage() {
        messageLabel.stringValue = [storeError, actionMessage.isEmpty ? nil : actionMessage]
            .compactMap { $0 }.joined(separator: "\n")
        messageLabel.textColor = storeError != nil || actionIsError ? Self.red : Self.green
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                       color: NSColor = ink) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private static func writeClipboard(_ text: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }

    private static func launchCodex(_ completion: @escaping (String?) -> Void) {
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else {
            completion("没有找到已安装的 Codex 应用"); return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: application, configuration: configuration) { _, error in
            completion(error?.localizedDescription)
        }
    }
}
