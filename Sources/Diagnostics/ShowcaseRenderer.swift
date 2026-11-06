import AppKit
import ImageIO

/// Reproducible README media using only synthetic tasks and notes. Never reads
/// live Codex state, personal reminders, display preferences or clipboard data.
@main
struct ShowcaseRenderer {
    static let date = Date()

    static func snapshot(mode: EmployeeMode = .sitting, taskCount: Int = 3,
                         notes: Int = 0, noteAge: TimeInterval = 120) -> SceneSnapshot {
        var result = SceneSnapshot.empty(now: date)
        result.mode = mode
        result.preferredPosture = mode == .standing ? .standing : .sitting
        result.taskOrigin = .simulation
        result.completedToday = 5
        result.world = SceneWorld(weather: .clear, weatherMode: .manual, timeMode: .day)
        let titles = ["给小屋添一点生气", "检查新的页面布局", "等你确认设计方案", "整理项目运行说明", "补齐设置页空状态", "优化图片加载速度"]
        result.tasks = (0..<taskCount).map { index in
            WorkplaceTask(id: "showcase-task-\(index)", title: titles[index],
                status: index == 2 ? .waiting : .running, slot: index,
                progress: index == 2 ? nil : 0.64,
                currentStep: index == 2 ? "需要你确认后继续" : "正在处理当前步骤",
                startedAt: date.addingTimeInterval(-420), nextStep: "完成后检查结果")
        }
        let reminders = ["给首页加一段自我介绍", "整理今晚想做的小功能", "周末试试新的配色", "给猫咪动画加点惊喜", "写一份简单的使用说明", "检查深色模式的对比度", "给朋友准备一个演示", "做一个更顺手的快捷键"]
        result.pendingNotes = (0..<notes).map { index in
            PendingNote(id: "showcase-note-\(index)", text: reminders[index],
                createdAt: date.addingTimeInterval(-noteAge - Double(index * 60)), slot: index)
        }
        return result
    }

    static func canvas(_ width: Int, _ height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    static func render(_ snapshot: SceneSnapshot, width: Int = 1672, height: Int = 941,
                       time: TimeInterval = 3, now: Date = Date(),
                       background: WorkplaceBackground = .room) -> CGImage {
        let context = canvas(width, height)
        var fresh = snapshot
        fresh.updatedAt = Date()
        SceneRenderer.draw(in: context, bounds: CGRect(x: 0, y: 0, width: width, height: height),
            snapshot: fresh, time: time, reduceMotion: false, now: now, background: background)
        return context.makeImage()!
    }

    static func png(_ image: CGImage, to url: URL) {
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination), "Cannot encode \(url.lastPathComponent)")
    }

    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        precondition(SceneRenderer.hasRoomAssets && SceneRenderer.hasOutdoorAssets && PendingVisitorSprites.isAvailable)
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/images", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let room = snapshot()
        png(render(room), to: output.appendingPathComponent("hero.png"))
        png(render(room), to: output.appendingPathComponent("sitting.png"))
        png(render(snapshot(mode: .standing, taskCount: 6)), to: output.appendingPathComponent("standing.png"))
        png(render(snapshot(mode: .slacking, taskCount: 0)), to: output.appendingPathComponent("sleeping.png"))
        png(render(snapshot(notes: 8), background: .outdoors), to: output.appendingPathComponent("visitors.png"))
        let storm = snapshot(notes: 8, noteAge: 5 * 3600)
        let event = Int(floor(date.timeIntervalSinceReferenceDate / 35))
        let lightning = Date(timeIntervalSinceReferenceDate: WorldAtmosphere.lightningEventTime(index: event) + 0.12)
        png(render(storm, now: lightning, background: .outdoors), to: output.appendingPathComponent("storm.png"))
        let pair = canvas(3344, 941)
        for (index, background) in [WorkplaceBackground.outdoors, .room].enumerated() {
            pair.saveGState()
            pair.translateBy(x: CGFloat(index * 1672), y: 0)
            pair.clip(to: CGRect(x: 0, y: 0, width: 1672, height: 941))
            SceneRenderer.draw(in: pair, bounds: CGRect(x: 0, y: 0, width: 1672, height: 941),
                snapshot: snapshot(notes: 4), time: 3, reduceMotion: false, now: date, background: background)
            pair.restoreGState()
        }
        png(pair.makeImage()!, to: output.appendingPathComponent("dual-screen.png"))

        let gif = CGImageDestinationCreateWithURL(output.appendingPathComponent("showcase.gif") as CFURL,
            "com.compuserve.gif" as CFString, 72, nil)!
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<72 {
            let segment = frame / 24
            let mode: EmployeeMode = segment == 0 ? .sitting : segment == 1 ? .standing : .slacking
            let time = Double(frame) / 8
            let now = Date()
            var state = snapshot(mode: mode, taskCount: segment == 1 ? 6 : segment == 2 ? 0 : 3)
            state.updatedAt = now
            let image = render(state, width: 960, height: 540, time: time, now: now)
            CGImageDestinationAddImage(gif, image, [kCGImagePropertyGIFDictionary:
                [kCGImagePropertyGIFDelayTime: 0.125]] as CFDictionary)
        }
        precondition(CGImageDestinationFinalize(gif), "Cannot encode demo GIF")
        print("Rendered synthetic showcase media in \(output.path)")
    }
}
