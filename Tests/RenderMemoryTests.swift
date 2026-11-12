import AppKit
import Darwin

/// Synthetic, offscreen soak: never reads user state or starts live observers.
/// Keep one destination bitmap and drain temporary AppKit objects every frame.
@main enum RenderMemoryTests {
    private static let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private static let start = Date(timeIntervalSince1970: 1_793_811_600)
    private static let memoryLimit: UInt64 = 1_073_741_824

    private static func memory() -> (resident: UInt64, footprint: UInt64) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        precondition(result == KERN_SUCCESS, "cannot measure render fixture memory")
        return (info.resident_size, info.phys_footprint)
    }

    private static func context() -> CGContext {
        CGContext(data: nil, width: Int(bounds.width), height: Int(bounds.height), bitsPerComponent: 8,
            bytesPerRow: Int(bounds.width) * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    private static func fixture() -> SceneSnapshot {
        var snapshot = SceneSnapshot.empty(now: start)
        snapshot.mode = .sitting
        snapshot.world = SceneWorld(weather: .clear, timeMode: .day)
        snapshot.world?.weatherMode = .manual
        snapshot.pendingNotes = (0..<8).map {
            PendingNote(id: "memory-note-\($0)", text: "待办 \($0 + 1)：整理项目说明，核对任务状态",
                createdAt: start.addingTimeInterval(-Double($0 * 600)), slot: $0)
        }
        snapshot.tasks = (0..<6).map {
            WorkplaceTask(id: "memory-task-\($0)", title: "内存回归任务 \($0 + 1)", status: .running, slot: $0)
        }
        return snapshot
    }

    private static func hash(_ c: CGContext) -> String {
        let bytes = c.data!.assumingMemoryBound(to: UInt8.self)
        var result: UInt64 = 1469598103934665603
        for index in 0..<(c.bytesPerRow * c.height) { result = (result ^ UInt64(bytes[index])) &* 1099511628211 }
        return String(result, radix: 16)
    }

    private static func frameHashes(_ c: CGContext) -> [String] {
        var hashes: [String] = []
        for background in [WorkplaceBackground.outdoors, .room] {
            for mode in [WorldTimeMode.day, .night] {
                for weather in [WorldWeather.clear, .rain] {
                    for pose in [EmployeeMode.sitting, .standing, .slacking] {
                        autoreleasepool {
                            var snapshot = fixture()
                            snapshot.mode = pose
                            snapshot.world = SceneWorld(weather: weather, timeMode: mode)
                            snapshot.world?.weatherMode = .manual
                            SceneRenderer.draw(in: c, bounds: bounds, snapshot: snapshot, time: 112.5,
                                reduceMotion: false, now: start, background: background)
                            hashes.append(hash(c))
                        }
                    }
                }
            }
        }
        return hashes
    }

    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        setbuf(stdout, nil)
        let args = CommandLine.arguments
        let c = context()
        if let index = args.firstIndex(of: "--hashes"), args.indices.contains(index + 1) {
            let hashes = frameHashes(c)
            try hashes.joined(separator: "\n").write(toFile: args[index + 1], atomically: true, encoding: .utf8)
            print("HASHES: \(hashes.count) deterministic room/outdoor day/night/weather/pose frames")
            return
        }
        let frames = args.firstIndex(of: "--frames").flatMap { args.indices.contains($0 + 1) ? Int(args[$0 + 1]) : nil } ?? 3000
        precondition((400...30_000).contains(frames))
        let background: WorkplaceBackground = args.contains("--room") ? .room : .outdoors
        let animation = SceneAnimation()
        var snapshot = fixture()
        if args.contains("--underwater") { snapshot.world?.theme = .underwater }
        let began = ProcessInfo.processInfo.systemUptime, cpuBegan = clock()
        var samples: [(Int, UInt64, UInt64)] = []
        for frame in 0..<frames {
            autoreleasepool {
                // One virtual hour exercises note labels/cache eviction and
                // walking phases without leaving the process running an hour.
                let elapsed = Double(frame) * 3600 / Double(frames - 1)
                snapshot.updatedAt = start.addingTimeInterval(elapsed)
                SceneRenderer.draw(in: c, bounds: bounds, snapshot: snapshot,
                    time: 100 + elapsed, reduceMotion: false, animation: animation,
                    now: start.addingTimeInterval(elapsed), background: background)
            }
            if frame % 100 == 0 || frame == frames - 1 {
                let used = memory()
                samples.append((frame, used.resident, used.footprint))
                print("MEM frame=\(frame) rssMiB=\(used.resident / 1_048_576) footprintMiB=\(used.footprint / 1_048_576)")
                precondition(max(used.resident, used.footprint) < memoryLimit, "render fixture exceeded 1GiB guard")
            }
        }
        let warm = samples.filter { $0.0 >= 300 }
        let floor = warm.map(\.2).min()!, peak = warm.map(\.2).max()!
        let growth = Int64(warm.last!.2) - Int64(warm.first!.2)
        print(String(format: "RESULT scene=%@ frames=%d virtualSeconds=3600 wallSeconds=%.2f cpuSeconds=%.2f warmMinMiB=%.2f warmPeakMiB=%.2f warmGrowthMiB=%.2f",
            background.rawValue, frames, ProcessInfo.processInfo.systemUptime - began,
            Double(clock() - cpuBegan) / Double(CLOCKS_PER_SEC), Double(floor) / 1_048_576,
            Double(peak) / 1_048_576, Double(growth) / 1_048_576))
        precondition(growth < 64 * 1_048_576, "steady-state render memory grew more than64MiB after warmup")
    }
}
