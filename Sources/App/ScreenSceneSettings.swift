import AppKit

private final class ScreenBackgroundPopup: NSPopUpButton {
    var displayIdentity = ""
    var displayContext: SceneDisplayContext = .desktop
}

private final class ScreenSceneRows: NSStackView {
    override var isFlipped: Bool { true }
}

private final class ScreenSceneSettingsRoot: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.96, green: 0.95, blue: 0.92, alpha: 1).setFill()
        bounds.fill()
    }
}

/// Static thumbnails use the production renderer without starting animation
/// timers, observing Codex, or creating desktop windows.
private final class ScreenBackgroundPreview: NSView {
    var background: WorkplaceBackground = .room { didSet { needsDisplay = true } }
    var world = SceneWorld() { didSet { needsDisplay = true } }
    var pendingNotes: [PendingNote] = [] { didSet { needsDisplay = true } }
    var referenceDate = Date() { didSet { needsDisplay = true } }
    var viewport: WorldViewport? { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        var snapshot = SceneSnapshot.empty(now: referenceDate)
        snapshot.world = world
        snapshot.pendingNotes = pendingNotes
        SceneRenderer.draw(in: context, bounds: bounds, snapshot: snapshot, time: 0,
            reduceMotion: true, now: referenceDate, background: background, viewport: viewport)
    }
}

/// Configuration belongs to the companion app. The saver only consumes the
/// resulting shared snapshot and never writes settings on behalf of a display.
final class ScreenSceneSettingsController: NSObject {
    var onChange: ((SceneWorld) -> Void)?
    private var window: NSWindow?
    private var world = SceneWorld()
    private var pendingNotes: [PendingNote] = []
    private var displayContext: SceneDisplayContext = .desktop
    private var displayRows: NSStackView?
    private var themePicker: NSSegmentedControl?
    private var environmentHeading: NSTextField?
    private var environmentHelp: NSTextField?
    private var weatherHeading: NSTextField?
    private var weatherModeHeading: NSTextField?
    private var lightHeading: NSTextField?
    private var contextPicker: NSSegmentedControl?
    private var contextExplanation: NSTextField?
    private var resetButton: NSButton?
    private var weatherPopup: NSPopUpButton?
    private var timePopup: NSPopUpButton?
    private var weatherModePopup: NSPopUpButton?
    private var weatherExplanation: NSTextField?
    private var weatherStatus: NSTextField?
    private var saveErrorLabel: NSTextField?
    private var previews: [(String, ScreenBackgroundPreview)] = []
    private var displayObserver: NSObjectProtocol?
    private let weatherOptions: [WorldWeather] = [.clear, .cloudy, .rain, .thunderstorm, .snow]
    private let timeOptions: [WorldTimeMode] = [.automatic, .day, .sunset, .night]
    private let weatherModes: [WeatherMode] = [.random, .manual]
    private static let weatherClock: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"; return formatter
    }()
    private var lastPreviewWeather: WorldWeather?
    private var lastPreviewMinute: Int?
    private static let ink = NSColor(srgbRed: 0.17, green: 0.23, blue: 0.22, alpha: 1)
    private static let secondary = NSColor(srgbRed: 0.45, green: 0.49, blue: 0.45, alpha: 1)

    override init() {
        super.init()
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.window?.isVisible == true else { return }
            self.rebuildDisplayRows()
        }
    }

    deinit {
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
    }

    func show(world: SceneWorld) {
        self.world = world
        ensureWindow()
        clearSaveError()
        refreshControls(rebuildRows: true)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func show(snapshot: SceneSnapshot) {
        pendingNotes = snapshot.pendingNotes ?? []
        show(world: snapshot.world ?? SceneWorld())
    }

    func update(world: SceneWorld) {
        clearSaveError()
        guard self.world != world else { return }
        self.world = world
        if window != nil { refreshControls(rebuildRows: true) }
    }

    /// A heartbeat does not dismiss a save error or recreate selectors. The
    /// settings retain the manual weather; previews resolve the shared weather.
    func update(snapshot: SceneSnapshot) {
        let nextWorld = snapshot.world ?? SceneWorld()
        let nextNotes = snapshot.pendingNotes ?? []
        let worldChanged = world != nextWorld
        let changed = worldChanged || pendingNotes != nextNotes
        let layoutChanged = world.theme != nextWorld.theme || world.displayScenes != nextWorld.displayScenes
            || world.screenSaverDisplayScenes != nextWorld.screenSaverDisplayScenes
        world = nextWorld
        pendingNotes = nextNotes
        guard window != nil else { return }
        if worldChanged { refreshControls(rebuildRows: layoutChanged) }
        else { refreshWeatherExplanation(at: Date()) }
        refreshPreviews(force: changed)
    }

    func close() { window?.close() }

    func showSaveError(_ message: String) {
        saveErrorLabel?.stringValue = String(message.prefix(240))
        saveErrorLabel?.isHidden = false
    }

    func clearSaveError() {
        saveErrorLabel?.stringValue = ""
        saveErrorLabel?.isHidden = true
    }

    /// A review aid for the build diagnostics; does not order or activate UI.
    func renderPreview(to output: URL, world: SceneWorld, context: SceneDisplayContext? = nil) throws {
        self.world = world
        if let context { displayContext = context }
        ensureWindow()
        refreshControls(rebuildRows: true)
        guard let root = window?.contentView else { return }
        root.layoutSubtreeIfNeeded()
        displayRows?.layoutSubtreeIfNeeded()
        root.layoutSubtreeIfNeeded()
        guard let image = root.bitmapImageRepForCachingDisplay(in: root.bounds) else {
            throw NSError(domain: "VirtualWorkplace.ScreenScenes", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "无法创建屏幕设置预览"])
        }
        root.cacheDisplay(in: root.bounds, to: image)
        guard let data = image.representation(using: .png, properties: [:]) else { return }
        try data.write(to: output, options: .atomic)
    }

    func renderPreview(to output: URL, snapshot: SceneSnapshot, context: SceneDisplayContext? = nil) throws {
        pendingNotes = snapshot.pendingNotes ?? []
        try renderPreview(to: output, world: snapshot.world ?? SceneWorld(), context: context)
    }

    private func ensureWindow() {
        guard window == nil else { return }
        let height = min(800, (NSScreen.main?.visibleFrame.height ?? 860) - 60)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: height),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "屏幕场景"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor(srgbRed: 0.96, green: 0.95, blue: 0.92, alpha: 1)
        window.center()
        let root = ScreenSceneSettingsRoot()
        root.wantsLayer = true
        root.layer?.backgroundColor = window.backgroundColor.cgColor
        window.contentView = root
        let body = NSStackView()
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 10
        body.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            body.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            body.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            body.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -24)
        ])
        body.addArrangedSubview(label("屏幕场景", size: 23, weight: .semibold))
        body.addArrangedSubview(label("选择主题，再为桌面与屏保的每块屏幕配置场景。", size: 12, color: Self.secondary))

        let contextControls = NSStackView()
        contextControls.orientation = .vertical
        contextControls.alignment = .leading
        contextControls.spacing = 7
        let picker = NSSegmentedControl(labels: SceneDisplayContext.allCases.map(\.title),
            trackingMode: .selectOne, target: self, action: #selector(contextChanged(_:)))
        picker.segmentStyle = .rounded
        picker.selectedSegment = 0
        picker.identifier = NSUserInterfaceItemIdentifier("scene-context")
        picker.setAccessibilityLabel("背景配置范围")
        picker.toolTip = "分别设置桌面背景和系统屏保的每块屏幕；切换不会更改配置"
        let theme = NSSegmentedControl(labels: WorkplaceTheme.allCases.map(\.title),
            trackingMode: .selectOne, target: self, action: #selector(themeChanged(_:)))
        theme.segmentStyle = .rounded
        theme.identifier = NSUserInterfaceItemIdentifier("scene-theme")
        theme.setAccessibilityLabel("场景主题")
        themePicker = theme
        let switches = NSStackView(views: [theme, picker])
        switches.orientation = .horizontal
        switches.spacing = 16
        contextControls.addArrangedSubview(switches)
        contextPicker = picker
        let contextHelp = label("", size: 11, color: Self.secondary)
        contextControls.addArrangedSubview(contextHelp)
        contextExplanation = contextHelp
        body.addArrangedSubview(contextControls)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        body.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: height >= 760 ? 240 : 120).isActive = true
        let rows = ScreenSceneRows()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 12
        rows.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = rows
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            rows.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            rows.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        displayRows = rows
        let divider = NSBox()
        divider.boxType = .separator
        body.addArrangedSubview(divider)
        divider.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        let environmentTitle = label("", size: 16, weight: .semibold)
        environmentHeading = environmentTitle
        body.addArrangedSubview(environmentTitle)
        let environmentRow = NSStackView()
        environmentRow.orientation = .horizontal
        environmentRow.spacing = 10
        environmentRow.alignment = .centerY
        let weatherTitle = label("", size: 12)
        weatherHeading = weatherTitle
        environmentRow.addArrangedSubview(weatherTitle)
        let weather = NSPopUpButton(frame: .zero, pullsDown: false)
        weather.identifier = NSUserInterfaceItemIdentifier("shared-weather")
        weather.addItems(withTitles: weatherOptions.map(\.title))
        weather.target = self; weather.action = #selector(weatherChanged(_:))
        weather.widthAnchor.constraint(equalToConstant: 150).isActive = true
        weather.setAccessibilityLabel("全部屏幕的手动天气")
        environmentRow.addArrangedSubview(weather)
        let gap = NSView()
        gap.widthAnchor.constraint(equalToConstant: 12).isActive = true
        environmentRow.addArrangedSubview(gap)
        let lightTitle = label("", size: 12)
        lightHeading = lightTitle
        environmentRow.addArrangedSubview(lightTitle)
        let time = NSPopUpButton(frame: .zero, pullsDown: false)
        time.identifier = NSUserInterfaceItemIdentifier("shared-time")
        time.addItems(withTitles: timeOptions.map(\.title))
        time.target = self; time.action = #selector(timeChanged(_:))
        time.widthAnchor.constraint(equalToConstant: 190).isActive = true
        time.setAccessibilityLabel("全部屏幕的昼夜")
        environmentRow.addArrangedSubview(time)
        weatherPopup = weather; timePopup = time
        body.addArrangedSubview(environmentRow)
        let explanation = label("桌面与屏保共用天气和时间。自动昼夜跟随本机时间，房间窗户与窗外风景同步。", size: 11, color: Self.secondary)
        environmentHelp = explanation
        explanation.maximumNumberOfLines = 2
        body.addArrangedSubview(explanation)
        explanation.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true

        let modeRow = NSStackView()
        modeRow.orientation = .horizontal; modeRow.spacing = 10; modeRow.alignment = .centerY
        let modeTitle = label("", size: 12)
        weatherModeHeading = modeTitle
        modeRow.addArrangedSubview(modeTitle)
        let mode = NSPopUpButton(frame: .zero, pullsDown: false)
        mode.identifier = NSUserInterfaceItemIdentifier("weather-mode")
        mode.addItems(withTitles: ["随机轮换", "手动固定"])
        mode.target = self; mode.action = #selector(weatherModeChanged(_:))
        mode.widthAnchor.constraint(equalToConstant: 180).isActive = true
        mode.setAccessibilityLabel("全部屏幕的天气模式")
        modeRow.addArrangedSubview(mode)
        weatherModePopup = mode
        body.addArrangedSubview(modeRow)
        let pendingHelp = NSTextField(wrappingLabelWithString: "")
        pendingHelp.identifier = NSUserInterfaceItemIdentifier("shared-weather-help")
        pendingHelp.font = .systemFont(ofSize: 11); pendingHelp.textColor = Self.secondary
        pendingHelp.maximumNumberOfLines = 3
        body.addArrangedSubview(pendingHelp)
        pendingHelp.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        weatherExplanation = pendingHelp
        let pendingStatus = NSTextField(wrappingLabelWithString: "")
        pendingStatus.identifier = NSUserInterfaceItemIdentifier("shared-weather-status")
        pendingStatus.font = .systemFont(ofSize: 11); pendingStatus.textColor = Self.ink
        pendingStatus.maximumNumberOfLines = 2
        body.addArrangedSubview(pendingStatus)
        pendingStatus.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        weatherStatus = pendingStatus
        let saveError = NSTextField(wrappingLabelWithString: "")
        saveError.font = .systemFont(ofSize: 11)
        saveError.textColor = NSColor(srgbRed: 0.62, green: 0.25, blue: 0.18, alpha: 1)
        saveError.maximumNumberOfLines = 2
        saveError.isHidden = true
        saveError.setAccessibilityLabel("设置保存失败")
        saveErrorLabel = saveError
        body.addArrangedSubview(saveError)
        saveError.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        let footer = NSStackView()
        footer.orientation = .horizontal
        body.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        footer.spacing = 8
        let reset = NSButton(title: "恢复桌面布局", target: self, action: #selector(resetLayout))
        reset.identifier = NSUserInterfaceItemIdentifier("reset-scene-layout")
        reset.bezelStyle = .rounded
        resetButton = reset
        footer.addArrangedSubview(reset)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(spacer)
        let done = NSButton(title: "完成", target: self, action: #selector(finish))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        footer.addArrangedSubview(done)
        self.window = window
    }

    private func rebuildDisplayRows() {
        guard let rows = displayRows else { return }
        rows.arrangedSubviews.forEach { rows.removeArrangedSubview($0); $0.removeFromSuperview() }
        previews.removeAll()
        let displays = DisplaySceneRouting.descriptors().sorted {
            $0.frame.minX == $1.frame.minX ? $0.isMain && !$1.isMain : $0.frame.minX < $1.frame.minX
        }
        let now = Date()
        for display in displays {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 18
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor, constant: -8).isActive = true
            row.heightAnchor.constraint(equalToConstant: 106).isActive = true
            let preview = ScreenBackgroundPreview(frame: .zero)
            preview.background = DisplaySceneRouting.background(for: display, among: displays, world: world, context: displayContext)
            preview.viewport = DisplaySceneRouting.viewport(for: display, among: displays, world: world, context: displayContext)
            preview.world = world; preview.pendingNotes = pendingNotes; preview.referenceDate = now
            preview.identifier = NSUserInterfaceItemIdentifier("scene-preview:\(display.id)")
            preview.setAccessibilityLabel("\(displayContext.title) · \(display.name)：\(world.theme.title(for: preview.background))")
            preview.widthAnchor.constraint(equalToConstant: 160).isActive = true
            preview.heightAnchor.constraint(equalToConstant: 90).isActive = true
            row.addArrangedSubview(preview)
            let controls = NSStackView()
            controls.orientation = .vertical
            controls.alignment = .leading
            controls.spacing = 6
            let title = label(display.name, size: 14, weight: .medium)
            title.lineBreakMode = .byTruncatingTail
            title.widthAnchor.constraint(equalToConstant: 340).isActive = true
            title.toolTip = display.name
            controls.addArrangedSubview(title)
            let position = DisplaySceneRouting.layoutTitle(for: display, among: displays)
            controls.addArrangedSubview(label("\(position) · \(Int(display.frame.width)) × \(Int(display.frame.height))", size: 11, color: Self.secondary))
            let popup = ScreenBackgroundPopup(frame: .zero, pullsDown: false)
            popup.displayIdentity = display.id
            popup.displayContext = displayContext
            popup.identifier = NSUserInterfaceItemIdentifier("screen-background:\(display.id)")
            for background in [WorkplaceBackground.room, .outdoors] {
                popup.addItem(withTitle: world.theme.title(for: background))
                popup.lastItem?.representedObject = background.rawValue
            }
            popup.selectItem(at: preview.background == .room ? 0 : 1)
            popup.target = self; popup.action = #selector(backgroundChanged(_:))
            popup.widthAnchor.constraint(equalToConstant: 180).isActive = true
            popup.setAccessibilityLabel("\(displayContext.title) · \(position) \(display.name)的背景")
            controls.addArrangedSubview(popup)
            row.addArrangedSubview(controls)
            previews.append((display.id, preview))
        }
        if displays.isEmpty { rows.addArrangedSubview(label("暂时没有检测到显示器。连接后会在这里出现。", size: 12, color: Self.secondary)) }
        lastPreviewWeather = nil
        lastPreviewMinute = nil
    }

    private func refreshControls(rebuildRows: Bool) {
        let theme = world.theme
        let underwater = theme == .underwater
        let primary = theme.title(for: WorkplaceBackground.room)
        let alternate = theme.title(for: WorkplaceBackground.outdoors)
        themePicker?.selectedSegment = WorkplaceTheme.allCases.firstIndex(of: theme) ?? 0
        contextPicker?.selectedSegment = SceneDisplayContext.allCases.firstIndex(of: displayContext) ?? 0
        switch displayContext {
        case .desktop:
            contextExplanation?.stringValue = "桌面背景：默认每块屏幕都显示\(primary)，可单独改为\(alternate)。"
            resetButton?.title = "恢复桌面布局"
            resetButton?.toolTip = "仅恢复桌面背景：每块屏幕显示\(primary)。保留系统屏保和环境配置。"
        case .screenSaver:
            contextExplanation?.stringValue = "系统屏保：默认主屏显示\(primary)，其他屏幕显示\(alternate)。"
            resetButton?.title = "恢复屏保布局"
            resetButton?.toolTip = "仅恢复系统屏保：主屏显示\(primary)，其他屏幕显示\(alternate)。保留桌面背景和环境配置。"
        }
        environmentHeading?.stringValue = underwater ? "共用的海况与光照" : "共用的天气与时间"
        weatherHeading?.stringValue = underwater ? "手动海况" : "手动天气"
        lightHeading?.stringValue = underwater ? "光照" : "昼夜"
        environmentHelp?.stringValue = underwater
            ? "桌面与屏保共用海况和光照。自动光照随本机时间调整水下亮度，深海始终更暗。"
            : "桌面与屏保共用天气和时间。自动昼夜跟随本机时间，房间窗户与窗外风景同步。"
        weatherPopup?.setAccessibilityLabel(underwater ? "全部屏幕的手动海况" : "全部屏幕的手动天气")
        timePopup?.setAccessibilityLabel(underwater ? "全部屏幕的光照" : "全部屏幕的昼夜")
        for (index, option) in weatherOptions.enumerated() {
            weatherPopup?.item(at: index)?.title = theme.title(for: option)
        }
        for (index, option) in timeOptions.enumerated() {
            timePopup?.item(at: index)?.title = theme.title(for: option)
        }
        weatherModeHeading?.stringValue = underwater ? "海况模式" : "天气模式"
        weatherModePopup?.setAccessibilityLabel(underwater ? "全部屏幕的海况模式" : "全部屏幕的天气模式")
        weatherPopup?.selectItem(at: weatherOptions.firstIndex(of: world.weather) ?? 0)
        timePopup?.selectItem(at: timeOptions.firstIndex(of: world.timeMode) ?? 0)
        weatherModePopup?.selectItem(at: weatherModes.firstIndex(of: world.weatherMode) ?? 0)
        weatherPopup?.isEnabled = world.weatherMode == .manual
        refreshWeatherExplanation(at: Date())
        if rebuildRows { rebuildDisplayRows() }
        refreshPreviews(force: rebuildRows)
    }

    private func publish(rebuildRows: Bool = false) {
        clearSaveError()
        refreshControls(rebuildRows: rebuildRows)
        refreshPreviews(force: true)
        onChange?(world)
    }

    private func weatherSnapshot(at date: Date) -> SceneSnapshot {
        var snapshot = SceneSnapshot.empty(now: date)
        snapshot.world = world
        snapshot.pendingNotes = pendingNotes
        return snapshot
    }

    private func refreshPreviews(force: Bool) {
        let now = Date()
        let effectiveWeather = weatherSnapshot(at: now).effectiveWorld(at: now).weather
        let minute = Int(now.timeIntervalSince1970 / 60)
        guard force || lastPreviewWeather != effectiveWeather || lastPreviewMinute != minute else { return }
        lastPreviewWeather = effectiveWeather
        lastPreviewMinute = minute
        let descriptors = DisplaySceneRouting.descriptors()
        for (id, preview) in previews {
            preview.world = world; preview.pendingNotes = pendingNotes; preview.referenceDate = now
            if let display = descriptors.first(where: { $0.id == id }) {
                preview.background = DisplaySceneRouting.background(for: display, among: descriptors, world: world, context: displayContext)
                preview.viewport = DisplaySceneRouting.viewport(for: display, among: descriptors, world: world, context: displayContext)
                preview.setAccessibilityLabel("\(displayContext.title) · \(display.name)：\(world.theme.title(for: preview.background))")
                let condition = world.theme == .underwater ? "海况" : "天气"
                preview.setAccessibilityValue("当前\(condition)：\(world.theme.title(for: effectiveWeather))")
            }
        }
    }

    private func refreshWeatherExplanation(at date: Date) {
        let underwater = world.theme == .underwater
        let current = world.theme.title(for: weatherSnapshot(at: date).effectiveWorld(at: date).weather)
        let message: String
        if world.weatherMode == .random {
            weatherExplanation?.stringValue = underwater
                ? "每45分钟轮换海况。海况不受待办等待时长影响，所有屏幕保持同步。"
                : "每45分钟进入一个随机天气时段，晴天为主，偶尔下雨、下雪或雷雨。\n天气不受待办等待时长影响，所有屏幕保持同步。"
            let next = RandomWeatherPolicy.nextChange(after: date).map { " · 下一时段 \(Self.weatherClock.string(from: $0))" } ?? ""
            message = "当前显示：\(current) · 随机轮换\(next)"
        } else {
            weatherExplanation?.stringValue = underwater
                ? "固定显示你选择的海况。切回随机轮换时仍保留手动选择。"
                : "固定显示你选择的天气。切回随机轮换时仍保留手动选择。\n房间窗户、窗外与屏保共用同一份天气。"
            message = "当前显示：\(current) · 手动固定"
        }
        weatherStatus?.stringValue = message
        weatherStatus?.toolTip = message
    }

    @objc private func backgroundChanged(_ sender: ScreenBackgroundPopup) {
        guard sender.displayContext == displayContext,
              let value = sender.selectedItem?.representedObject as? String,
              let background = WorkplaceBackground(rawValue: value) else { return }
        var scenes = world.displayScenes(for: displayContext)
        scenes[sender.displayIdentity] = background
        world.setDisplayScenes(scenes, for: displayContext)
        publish()
    }
    @objc private func themeChanged(_ sender: NSSegmentedControl) {
        let themes = WorkplaceTheme.allCases
        guard themes.indices.contains(sender.selectedSegment) else { return }
        world.theme = themes[sender.selectedSegment]
        publish(rebuildRows: true)
    }
    @objc private func contextChanged(_ sender: NSSegmentedControl) {
        guard SceneDisplayContext.allCases.indices.contains(sender.selectedSegment) else { return }
        let selected = SceneDisplayContext.allCases[sender.selectedSegment]
        guard selected != displayContext else { return }
        displayContext = selected
        refreshControls(rebuildRows: true)
    }
    @objc private func weatherChanged(_ sender: NSPopUpButton) {
        guard world.weatherMode == .manual, weatherOptions.indices.contains(sender.indexOfSelectedItem) else { return }
        world.weather = weatherOptions[sender.indexOfSelectedItem]; publish()
    }
    @objc private func timeChanged(_ sender: NSPopUpButton) {
        guard timeOptions.indices.contains(sender.indexOfSelectedItem) else { return }
        world.timeMode = timeOptions[sender.indexOfSelectedItem]; publish()
    }
    @objc private func weatherModeChanged(_ sender: NSPopUpButton) {
        guard weatherModes.indices.contains(sender.indexOfSelectedItem) else { return }
        world.weatherMode = weatherModes[sender.indexOfSelectedItem]
        publish()
    }
    @objc private func resetLayout() {
        var scenes = world.displayScenes(for: displayContext)
        for display in DisplaySceneRouting.descriptors() { scenes.removeValue(forKey: display.id) }
        world.setDisplayScenes(scenes, for: displayContext)
        refreshControls(rebuildRows: true); publish()
    }
    @objc private func finish() { close() }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                       color: NSColor = ScreenSceneSettingsController.ink) -> NSTextField {
        let value = NSTextField(labelWithString: text)
        value.font = .systemFont(ofSize: size, weight: weight)
        value.textColor = color
        return value
    }
}
