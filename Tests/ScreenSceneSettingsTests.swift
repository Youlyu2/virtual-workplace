import AppKit

@main
enum ScreenSceneSettingsTests {
    private static var checks = 0
    private static func expect(_ result: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !result() { fatalError("FAIL: \(message)") }
    }
    private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
    private static func control<T: NSView>(_ id: String, in root: NSView, as type: T.Type) -> T {
        descendants(root).first { $0.identifier?.rawValue == id } as! T
    }
    private static func send(_ control: NSControl) {
        expect(NSApp.sendAction(control.action!, to: control.target, from: control), "the native control action reaches the settings controller")
    }
    private static func thumbnail(_ view: NSView) -> Data {
        let image = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: image)
        return image.representation(using: .png, properties: [:])!
    }
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("VirtualWorkplace-settings-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: output) }
        let controller = ScreenSceneSettingsController()
        let displays = DisplaySceneRouting.descriptors()
        let disconnected = "display:disconnected-fixture"
        var fixture = SceneWorld(weather: .rain, timeMode: .night,
            displayScenes: [disconnected: .outdoors], screenSaverDisplayScenes: [disconnected: .room])
        if let first = displays.first {
            fixture.displayScenes[first.id] = .outdoors
            fixture.screenSaverDisplayScenes[first.id] = .room
        }
        var changes: [SceneWorld] = []
        controller.onChange = { changes.append($0) }
        try controller.renderPreview(to: output, world: fixture)
        let window = app.windows.first { $0.title == "屏幕场景" }!
        let root = window.contentView!
        let views = descendants(root)
        let popups = views.compactMap { $0 as? NSPopUpButton }
        expect(popups.count == NSScreen.screens.count + 3, "each monitor has a background selector plus shared manual weather, time and weather mode")
        expect(popups.allSatisfy { $0.frame.width >= 100 && $0.frame.height >= 20 },
            "every background and environment selector has a visible usable frame")
        expect(popups.contains { $0.selectedItem?.title == WorldWeather.rain.title }
               && popups.contains { $0.selectedItem?.title == WorldTimeMode.night.title },
            "saved weather and day mode appear in the shared selectors")
        let buttons = views.compactMap { $0 as? NSButton }.filter { !($0 is NSPopUpButton) }
        expect(buttons.contains { $0.title == "完成" } && buttons.contains { $0.title == "恢复桌面布局" },
            "close and context-specific reset controls exist")
        expect(buttons.allSatisfy { $0.frame.height >= 20 && root.bounds.contains($0.convert($0.bounds, to: root)) },
            "footer controls fit inside the settings window")
        expect(!window.isVisible && app.windows.allSatisfy { !$0.isVisible },
            "offscreen review never opens a window or takes focus")
        let imageData = try Data(contentsOf: output)
        expect(imageData.count > 10_000, "the production scene preview renders to an image")
        let weatherMode = control("weather-mode", in: root, as: NSPopUpButton.self)
        let weatherHelp = control("shared-weather-help", in: root, as: NSTextField.self)
        let weatherStatus = control("shared-weather-status", in: root, as: NSTextField.self)
        expect(weatherMode.indexOfSelectedItem == 0 && weatherHelp.stringValue.contains("每45分钟")
               && weatherHelp.stringValue.contains("不受待办") && weatherStatus.stringValue.contains("随机轮换"),
               "random weather is default and explains the independent synchronized schedule")
        expect(!control("shared-weather", in: root, as: NSPopUpButton.self).isEnabled,
               "manual selector is disabled while random weather is active")
        expect(!views.contains { $0.identifier?.rawValue == "pending-weather-enabled" },
               "obsolete overdue-weather controls are removed")
        let initialWindowCount = app.windows.count
        let picker = control("scene-context", in: root, as: NSSegmentedControl.self)
        expect(picker.segmentCount == 2 && picker.label(forSegment: 0) == SceneDisplayContext.desktop.title
               && picker.label(forSegment: 1) == SceneDisplayContext.screenSaver.title && picker.selectedSegment == 0,
            "desktop and screen saver are independent, clearly labelled configuration tabs")
        expect(picker.frame.height >= 20 && root.bounds.contains(picker.convert(picker.bounds, to: root)),
            "the context picker fits inside the settings window")
        func choose(_ context: SceneDisplayContext) {
            picker.selectedSegment = SceneDisplayContext.allCases.firstIndex(of: context)!
            send(picker)
            root.layoutSubtreeIfNeeded()
        }
        func background(_ id: String) -> NSPopUpButton {
            control("screen-background:\(id)", in: root, as: NSPopUpButton.self)
        }
        if let first = displays.first {
            let desktopControl = background(first.id)
            expect(desktopControl.selectedItem?.representedObject as? String == WorkplaceBackground.outdoors.rawValue,
                "the desktop tab preserves an existing explicit desktop choice")
            let desktopPreview = thumbnail(control("scene-preview:\(first.id)", in: root, as: NSView.self))
            choose(.screenSaver)
            expect(changes.isEmpty, "switching contexts does not publish a setting change")
            expect(background(first.id).selectedItem?.representedObject as? String == WorkplaceBackground.room.rawValue,
                "the screen saver tab selects its own saved background")
            let saverPreview = control("scene-preview:\(first.id)", in: root, as: NSView.self)
            expect(saverPreview.accessibilityLabel()?.contains(SceneDisplayContext.screenSaver.title) == true
                   && thumbnail(saverPreview) != desktopPreview,
                "thumbnails and accessibility labels follow the selected context")
            desktopControl.selectItem(at: 0); send(desktopControl)
            expect(changes.isEmpty, "an old context's removed selector cannot write to the newly selected map")

            background(first.id).selectItem(at: 1); send(background(first.id))
            expect(changes.last?.displayScenes == fixture.displayScenes
                   && changes.last?.screenSaverDisplayScenes[first.id] == .outdoors,
                "a screen saver edit changes only the screen saver display map")
            choose(.desktop)
            expect(background(first.id).selectedItem?.representedObject as? String == WorkplaceBackground.outdoors.rawValue,
                "returning to desktop retains its independent selected background")
            background(first.id).selectItem(at: 0); send(background(first.id))
            expect(changes.last?.displayScenes[first.id] == .room
                   && changes.last?.screenSaverDisplayScenes[first.id] == .outdoors,
                "a desktop edit preserves the screen saver display map")
        }
        let weather = control("shared-weather", in: root, as: NSPopUpButton.self)
        let time = control("shared-time", in: root, as: NSPopUpButton.self)
        weatherMode.selectItem(at: 1); send(weatherMode)
        expect(changes.last?.weatherMode == .manual && weather.isEnabled, "manual mode enables the fixed weather selector")
        weather.selectItem(withTitle: WorldWeather.snow.title); send(weather)
        let beforeSwitch = changes.count
        choose(.screenSaver)
        expect(changes.count == beforeSwitch && weather.selectedItem?.title == WorldWeather.snow.title,
            "weather is shared across contexts and context navigation never saves")
        time.selectItem(withTitle: WorldTimeMode.day.title); send(time)
        expect(changes.last?.weather == .snow && changes.last?.timeMode == .day,
            "the screen saver uses the same weather and time settings as the desktop")
        let beforeSaverReset = changes.last!
        let reset = control("reset-scene-layout", in: root, as: NSButton.self)
        expect(reset.title == "恢复屏保布局" && reset.toolTip?.contains("保留桌面背景") == true,
            "reset describes only the currently selected configuration")
        send(reset)
        expect(changes.last?.displayScenes == beforeSaverReset.displayScenes
               && changes.last?.screenSaverDisplayScenes == [disconnected: .room]
               && changes.last?.weather == .snow && changes.last?.timeMode == .day,
            "screen saver reset clears connected screen saver overrides while retaining desktop, disconnected and environment settings")
        for display in displays {
            let expected: WorkplaceBackground = display.isMain || displays.count == 1 ? .room : .outdoors
            expect(background(display.id).selectedItem?.representedObject as? String == expected.rawValue,
                "reset previews the default main-room and companion-outdoor screen saver layout")
        }
        choose(.desktop)
        expect(reset.title == "恢复桌面布局", "reset changes its title with the selected context")
        send(reset)
        expect(changes.last?.displayScenes == [disconnected: .outdoors]
               && changes.last?.screenSaverDisplayScenes == [disconnected: .room],
            "desktop reset preserves the independent screen saver map and disconnected overrides")
        expect(displays.allSatisfy { background($0.id).selectedItem?.representedObject as? String == WorkplaceBackground.room.rawValue },
            "desktop reset shows a room on every connected screen")
        let latest = changes.last!
        controller.update(world: latest)
        controller.showSaveError("设置保存失败，请重试。")
        root.layoutSubtreeIfNeeded()
        expect(descendants(root).compactMap { $0 as? NSTextField }.contains { !$0.isHidden && $0.stringValue.contains("设置保存失败") },
            "save errors have an inline visible message")
        expect(buttons.allSatisfy { root.bounds.contains($0.convert($0.bounds, to: root)) },
            "the footer stays inside the window with a visible save error")
        controller.update(world: latest)
        expect(!descendants(root).compactMap { $0 as? NSTextField }.contains { !$0.isHidden && $0.stringValue.contains("设置保存失败") },
            "a successful refresh clears the old save failure")
        let published = changes.count
        try controller.renderPreview(to: output, world: latest, context: .screenSaver)
        expect(app.windows.count == initialWindowCount && !window.isVisible,
            "repeated preview refreshes reuse one hidden settings window")
        expect(changes.count == published && picker.selectedSegment == 1,
            "offscreen review can select either context without publishing a user settings change")

        let weatherPublished = changes.count
        var weatherSnapshot = SceneSnapshot.empty()
        weatherSnapshot.world = latest
        weatherSnapshot.pendingNotes = []
        controller.update(snapshot: weatherSnapshot)
        let firstPreview = displays.first.map { control("scene-preview:\($0.id)", in: root, as: NSView.self) }
        let overdue = PendingNote(id: "overdue-ui", text: "等待天气测试", createdAt: Date().addingTimeInterval(-50 * 3600))
        weatherSnapshot.pendingNotes = [overdue]
        controller.update(snapshot: weatherSnapshot)
        expect(changes.count == weatherPublished && weather.selectedItem?.title == latest.weather.title
               && weatherStatus.stringValue.contains("手动固定") && weatherStatus.stringValue.contains(latest.weather.title),
               "old notes never change manual weather or publish settings")
        if let firstPreview, let first = displays.first {
            expect(control("scene-preview:\(first.id)", in: root, as: NSView.self) === firstPreview,
                   "note changes reuse display selectors and thumbnail views")
            expect(firstPreview.accessibilityValue() as? String == "当前天气：\(latest.weather.title)",
                   "thumbnails keep the shared manual weather even with overdue notes")
        }
        controller.showSaveError("测试保存失败，保留基础设置")
        controller.update(snapshot: weatherSnapshot)
        expect(descendants(root).compactMap { $0 as? NSTextField }.contains { !$0.isHidden && $0.stringValue.contains("测试保存失败") },
               "a heartbeat does not dismiss an unresolved settings save error")
        controller.clearSaveError()
        weatherMode.selectItem(at: 0); send(weatherMode)
        expect(changes.last?.weatherMode == .random && !weather.isEnabled
               && weatherStatus.stringValue.contains("随机轮换") && weather.selectedItem?.title == latest.weather.title,
               "random mode resumes without overwriting saved manual weather")
        choose(.desktop)
        expect(weatherMode.indexOfSelectedItem == 0, "random mode is shared between desktop and saver settings")
        weatherMode.selectItem(at: 1); send(weatherMode)
        weather.selectItem(withTitle: WorldWeather.thunderstorm.title); send(weather)
        expect(changes.last?.weather == .thunderstorm && changes.last?.weatherMode == .manual,
               "thunderstorms remain available as an explicit fixed weather choice")
        weatherSnapshot.world = SceneWorld(weather: .clear, timeMode: .day)
        weatherSnapshot.pendingNotes = []
        controller.update(snapshot: weatherSnapshot)
        expect(weather.selectedItem?.title == WorldWeather.clear.title && weatherStatus.stringValue.contains("随机轮换"),
               "new worlds use independent random weather even with no pending notes")
        root.layoutSubtreeIfNeeded()
        expect(descendants(root).compactMap { $0 as? NSButton }.allSatisfy {
            $0.frame.height >= 20 && root.bounds.contains($0.convert($0.bounds, to: root))
        }, "all weather controls and footer buttons remain inside the expanded settings window")
        if let index = CommandLine.arguments.firstIndex(of: "--review-output"), index + 1 < CommandLine.arguments.count {
            weatherSnapshot.pendingNotes = [overdue]
            try controller.renderPreview(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), snapshot: weatherSnapshot)
        }
        controller.close()
        print("PASS: \(checks) native screen settings construction and layout checks (no visible windows or state writes)")
    }
}
