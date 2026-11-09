import AppKit
import ImageIO

@main
enum VirtualWorkplaceMain {
    static var delegate: WorkplaceAppDelegate?
    static var writerLock: StateWriterLock?

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let application = NSApplication.shared
        if let output = value(after: "--render", in: arguments) {
            render(output: output, arguments: arguments)
            return
        }
        if let output = value(after: "--render-ui", in: arguments) {
            renderInterface(output: output, arguments: arguments)
            return
        }
        if arguments.contains("--check-layout") {
            checkLayout()
            return
        }
        if arguments.contains("--check-presentation") {
            do { print(try ScenePresentationController.checkConfiguration()) }
            catch { fputs("Presentation check failed: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if arguments.contains("--list-displays") {
            let world = (try? WorldSettingsStore().read()) ?? SceneWorld()
            let context = value(after: "--context", in: arguments).flatMap(SceneDisplayContext.init(rawValue:)) ?? .desktop
            let report: [String: Any] = ["displays": DisplaySceneRouting.diagnostics(world: world, context: context),
                "context": context.rawValue,
                "weather": world.weather.rawValue, "timeMode": world.timeMode.rawValue]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
               let text = String(data: data, encoding: .utf8) { print(text) }
            return
        }
        let stateURL = (value(after: "--state-path", in: arguments).map { URL(fileURLWithPath: $0) }
                        ?? StateStore.defaultURL).standardizedFileURL.resolvingSymlinksInPath()
        do {
            writerLock = try StateWriterLock(stateURL: stateURL)
        } catch StateWriterLock.Failure.alreadyRunning(let pid) {
            if let pid = pid, let running = NSRunningApplication(processIdentifier: pid) {
                running.activate(options: [.activateAllWindows])
            } else if let identifier = Bundle.main.bundleIdentifier {
                NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                    .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })?
                    .activate(options: [.activateAllWindows])
            }
            DistributedNotificationCenter.default().postNotificationName(Notification.Name("local.virtualworkplace.openWindow"), object: stateURL.path, userInfo: nil, deliverImmediately: true)
            print("An existing virtual workplace already owns this state file: \(stateURL.path)")
            return
        } catch {
            let alert = NSAlert()
            alert.messageText = "工位状态文件暂时无法使用"
            alert.informativeText = "无法取得本地状态文件的写入锁。\n\(stateURL.path)\n\n\(error.localizedDescription)"
            alert.runModal()
            return
        }
        application.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "VirtualWorkplace", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            application.applicationIconImage = icon
        }
        let appDelegate = WorkplaceAppDelegate(stateURL: stateURL, launchDemo: arguments.contains("--demo"), launchWallpaper: arguments.contains("--wallpaper"))
        delegate = appDelegate
        application.delegate = appDelegate
        application.run()
    }

    static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static func parsedAgentPose(in arguments: [String]) throws -> AgentPose? {
        guard let raw = value(after: "--agent-pose", in: arguments) else { return nil }
        guard raw.utf8.count <= 65_536, let patch = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else {
            throw AgentPuppetError.invalid("预览姿态需要不超过64KiB的JSON对象")
        }
        return try AgentControlInbox.patched(.neutral, with: patch)
    }

    static func renderInterface(output: String, arguments: [String]) {
        let width = max(960, Double(value(after: "--width", in: arguments) ?? "1200") ?? 1200)
        let height = max(640, Double(value(after: "--height", in: arguments) ?? "820") ?? 820)
        let count = min(6, max(0, Int(value(after: "--tasks", in: arguments) ?? "3") ?? 3))
        let mode = EmployeeMode(rawValue: value(after: "--mode", in: arguments) ?? "sitting") ?? .sitting
        let action = value(after: "--action", in: arguments).flatMap(EmployeeAction.init(rawValue:))
        let actionTime = max(0, Double(value(after: "--action-time", in: arguments) ?? "1") ?? 1)
        let appDelegate = WorkplaceAppDelegate(stateURL: nil, launchDemo: false)
        do {
            let report = try appDelegate.renderInterface(output: URL(fileURLWithPath: output), size: NSSize(width: width, height: height), taskCount: count, mode: mode,
                                                        action: action, actionTime: actionTime, agentPose: try parsedAgentPose(in: arguments))
            print(report)
            print(output)
        } catch {
            fputs("UI render failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func checkLayout() {
        for size in [NSSize(width: 1200, height: 820), NSSize(width: 960, height: 640)] {
            let appDelegate = WorkplaceAppDelegate(stateURL: nil, launchDemo: false)
            do {
                print(try appDelegate.renderInterface(output: nil, size: size, taskCount: 6, mode: .standing))
            } catch {
                fputs("Layout check failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
    }

    static func render(output: String, arguments: [String]) {
        let simulator = TaskSimulator()
        let count = min(6, max(0, Int(value(after: "--tasks", in: arguments) ?? "3") ?? 3))
        let elapsed = min(3600, max(0, Double(value(after: "--elapsed", in: arguments) ?? "0") ?? 0))
        let now = Date()
        for _ in 0..<count { simulator.addTask(at: now.addingTimeInterval(-elapsed)) }
        simulator.tick(at: now)
        if let value = value(after: "--status", in: arguments), let status = TaskStatus(rawValue: value) {
            for task in simulator.snapshot.tasks { simulator.setTaskStatus(id: task.id, status: status) }
        }
        let requestedMode = value(after: "--mode", in: arguments) ?? "sitting"
        simulator.setMode(EmployeeMode(rawValue: requestedMode) ?? .sitting)
        var snapshot = simulator.snapshot
        let noteCount = min(PendingNote.maximumCount, max(0, Int(value(after: "--notes", in: arguments) ?? "0") ?? 0))
        let requestedNoteAge = value(after: "--note-age", in: arguments).flatMap(Double.init)
        let noteAge = requestedNoteAge.flatMap { $0.isFinite ? min(315_360_000, max(0, $0)) : nil }
        let sampleNotes = ["修复登录后偶发的空白页面", "给项目补一份运行说明", "检查今天的任务执行结果", "整理待审核的代码改动", "给报表增加导出功能", "检查夜间模式的文字对比度", "补齐设置页的空状态", "优化大文件加载速度"]
        snapshot.pendingNotes = (0..<noteCount).map { index in
            PendingNote(id: "render-note-\(index)", text: sampleNotes[index],
                        createdAt: now.addingTimeInterval(-(noteAge ?? Double((index + 1) * 420))), slot: index)
        }
        snapshot.world = SceneWorld(weather: value(after: "--weather", in: arguments).flatMap(WorldWeather.init(rawValue:)) ?? .clear,
                                    timeMode: value(after: "--daylight", in: arguments).flatMap(WorldTimeMode.init(rawValue:)) ?? .automatic)
        // Explicit render fixtures stay reproducible; --random-weather previews
        // the same absolute-time calendar used by desktop and saver hosts.
        snapshot.world?.weatherMode = arguments.contains("--random-weather") ? .random : .manual
        do {
            if let pose = try parsedAgentPose(in: arguments) {
                snapshot.employeeControlMode = .agent
                snapshot.agentTimeline = AgentTimeline(startedAt: now, frames: [AgentKeyframe(time: 0, pose: pose)])
            }
        } catch {
            fputs("Agent preview failed: \(error.localizedDescription)\n", stderr); exit(1)
        }
        let background = value(after: "--background", in: arguments).flatMap(WorkplaceBackground.init(rawValue:)) ?? .room
        if let kind = value(after: "--action", in: arguments).flatMap(EmployeeAction.init(rawValue:)) {
            let actionTime = max(0, Double(value(after: "--action-time", in: arguments) ?? "1") ?? 1)
            snapshot.action = SceneAction(kind: kind, startedAt: now.addingTimeInterval(-actionTime))
        }
        let width = min(7680, max(640, Int(value(after: "--width", in: arguments) ?? "1920") ?? 1920))
        let height = min(4320, max(360, Int(value(after: "--height", in: arguments) ?? "1080") ?? 1080))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fputs("Unable to create render context\n", stderr)
            exit(1)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let animationTime = max(0, Double(value(after: "--animation-time", in: arguments) ?? "2") ?? 2)
        SceneRenderer.draw(in: context, bounds: CGRect(x: 0, y: 0, width: width, height: height),
                           snapshot: snapshot, time: animationTime, reduceMotion: false, now: now, background: background)
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL,
                                                                "public.png" as CFString, 1, nil) else {
            fputs("Unable to create PNG output\n", stderr)
            exit(1)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            fputs("Unable to write PNG output\n", stderr)
            exit(1)
        }
        print(output)
    }
}
