import AppKit

/// Exercises the production hand/input rhythm and pixels, without starting an
/// observer, opening a window, or touching the user's shared state file.
@main
struct WorkInputTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fatalError("FAIL: \(message)") }
    }

    static func main() {
        _ = NSApplication.shared
        let sampleStep = 1.0 / 120.0
        let samples = stride(from: 0.01, through: 600.0, by: sampleStep).map {
            WorkInputMotion.sample(time: $0, activity: .working)
        }
        expect(samples.allSatisfy {
            [$0.leftPress, $0.rightPress, $0.rightHandMix, $0.click].allSatisfy { $0.isFinite && (0...1).contains($0) }
                && $0.mouseOffset.x.isFinite && $0.mouseOffset.y.isFinite
                && abs($0.mouseOffset.x) <= 20 && abs($0.mouseOffset.y) <= 20
        }, "a long working cycle keeps wrists, clicks and mouse motion finite and inside the desk area")
        expect(samples.contains { $0.phase == .typing && $0.leftPress > 0.45 && $0.rightPress < 0.1 }
               && samples.contains { $0.phase == .typing && $0.rightPress > 0.45 && $0.leftPress < 0.1 },
               "typing alternates visible left and right key presses")
        expect(samples.allSatisfy { $0.leftPress <= 0.6 && $0.rightPress <= 0.6 },
               "key presses remain small enough for a one-to-two pixel wrist movement")
        expect(samples.contains { $0.phase == .paused && $0.leftPress == 0 && $0.rightPress == 0 },
               "working includes short natural pauses between bursts")
        expect(samples.contains { $0.phase == .mouse && $0.rightHandMix > 0.99 },
               "the right hand reaches the mouse during normal work")
        expect(samples.contains { $0.phase == .mouse && abs($0.mouseOffset.x) + abs($0.mouseOffset.y) > 3 },
               "mouse work moves the device as well as changing the arm pose")
        expect(samples.contains { $0.click > 0.8 && $0.rightHandMix > 0.99 }
               && samples.allSatisfy { $0.click < 0.01 || $0.phase == .mouse },
               "clicks happen with the right hand at the mouse, not while typing")
        expect(zip(samples, samples.dropFirst()).allSatisfy { abs($0.rightHandMix - $1.rightHandMix) < 0.04 },
               "reaching the mouse and returning to the keyboard has no sudden arm jump")
        expect(zip(samples, samples.dropFirst()).allSatisfy {
            abs($0.mouseOffset.x - $1.mouseOffset.x) < 1 && abs($0.mouseOffset.y - $1.mouseOffset.y) < 1
        }, "mouse motion is continuous across phase and cycle boundaries")
        let mouseRatio = Double(samples.filter { $0.phase == .mouse }.count) / Double(samples.count)
        expect((0.04...0.1).contains(mouseRatio),
               "mouse use occupies a small fraction of work instead of recurring every twelve seconds")
        let starts = samples.indices.dropFirst().filter {
            samples[$0].phase == .mouse && samples[$0 - 1].phase != .mouse
        }.map { Double($0) * sampleStep + 0.01 }
        let intervals = zip(starts, starts.dropFirst()).map { $1 - $0 }
        expect(starts.count >= 6 && intervals.allSatisfy { $0 > 28 },
               "mouse bouts are separated by long stretches of keyboard work")
        expect(Set(intervals.map { Int($0.rounded()) }).count >= 4,
               "independent random start offsets and skipped bouts avoid a fixed mouse cadence")
        let mouseTimes = stride(from: 0.01, through: 300.0, by: 0.02).filter {
            WorkInputMotion.sample(time: $0, activity: .working).rightHandMix > 0.999
        }
        guard let mouseTimeA = mouseTimes.first else { fatalError("No mouse bout in preview range") }
        let mouseTimeB = mouseTimeA + 0.6
        let paused = WorkInputMotion()
        for activity in [EmployeeActivity.waiting, .resting, .offline] {
            expect([0.1, 2.2, 7.85, 12.0, 24.5].allSatisfy {
                WorkInputMotion.sample(time: $0, activity: activity) == paused
            }, "\(activity) pauses typing, reaching, device movement and clicking")
        }
        expect([0.0, -1.0, Double.nan, Double.infinity].allSatisfy {
            WorkInputMotion.sample(time: $0, activity: .working) == paused
        }, "reduced motion and invalid clocks cannot animate input")
        expect(WorkInputMotion.sample(time: mouseTimeA, activity: .working)
               == WorkInputMotion.sample(time: mouseTimeA, activity: .working),
               "independent windows sampling one clock receive the same input pose")
        expect([Double.greatestFiniteMagnitude, 1e20].allSatisfy {
            let state = WorkInputMotion.sample(time: $0, activity: .working)
            return state.rightHandMix.isFinite && state.leftPress.isFinite && state.mouseOffset.x.isFinite
        }, "large finite clocks cannot overflow the deterministic schedule")

        expect(PixelEmployee.hasSprites && SceneRenderer.hasRoomAssets,
               "regressions exercise bundled production sprites instead of a geometric fallback")
        let now = Date()
        for standing in [CGFloat(0), CGFloat(1)] {
            let typingA = employee(standing: standing, time: 0.1, activity: .working)
            let typingB = employee(standing: standing, time: 0.22, activity: .working)
            let mouseA = employee(standing: standing, time: mouseTimeA, activity: .working)
            let mouseB = employee(standing: standing, time: mouseTimeB, activity: .working)
            let rise = standing * 40
            let hands = CGRect(x: 740, y: 415 + rise, width: 280, height: 95)
            let feet = CGRect(x: 740, y: 269, width: 210, height: 66)
            let head = CGRect(x: 805, y: standing == 0 ? 510 : 550, width: 60, height: 25)
            expect(fingerprint(typingA, region: hands) != fingerprint(typingB, region: hands),
                   "\(standing == 0 ? "seated" : "standing") production hands actually alternate on the keyboard")
            expect(fingerprint(mouseA, region: hands) != fingerprint(mouseB, region: hands),
                   "\(standing == 0 ? "seated" : "standing") production right hand follows the mouse")
            expect(fingerprint(typingA, region: feet) == fingerprint(mouseB, region: feet),
                   "input gestures keep \(standing == 0 ? "chair and feet" : "shoes") planted")
            expect(fingerprint(typingA, region: head) == fingerprint(mouseB, region: head),
                   "input gestures do not distort or drag the back of the head")
            for activity in [EmployeeActivity.waiting, .resting, .offline] {
                let a = employee(standing: standing, time: 2.2, activity: activity)
                let b = employee(standing: standing, time: 8.2, activity: activity)
                expect(fingerprint(a, region: hands) == fingerprint(b, region: hands),
                       "\(activity) stops visible \(standing == 0 ? "seated" : "standing") hand animation")
            }

            var state = SceneSnapshot.empty(now: now)
            state.mode = standing == 0 ? .sitting : .standing
            state.tasks = [WorkplaceTask(id: "input-fixture", title: "Actual work", status: .running, slot: 0)]
            let deviceArea = CGRect(x: 920, y: 430 + rise, width: 90, height: 70)
            let workA = scene(state, time: mouseTimeA, now: now)
            let workB = scene(state, time: mouseTimeB, now: now)
            expect(fingerprint(workA, region: deviceArea) != fingerprint(workB, region: deviceArea),
                   "the rendered \(standing == 0 ? "low" : "raised") desktop mouse moves with the hand")
            state.tasks[0].status = .waiting
            let waitA = scene(state, time: mouseTimeA, now: now)
            let waitB = scene(state, time: mouseTimeB, now: now)
            expect(fingerprint(waitA, region: deviceArea) == fingerprint(waitB, region: deviceArea),
                   "waiting stops the visible desktop mouse rather than leaving it moving by itself")
            state.tasks[0].status = .running
            let reducedA = scene(state, time: 0.1, now: now, reduceMotion: true)
            let reducedB = scene(state, time: 8.2, now: now, reduceMotion: true)
            expect(fingerprint(reducedA, region: hands) == fingerprint(reducedB, region: hands),
                   "reduced motion stops visible work input for both production postures")
            state.action = SceneAction(kind: .playWithCat, startedAt: now.addingTimeInterval(-3))
            let awayA = scene(state, time: mouseTimeA, now: now)
            let awayB = scene(state, time: mouseTimeB, now: now)
            expect(fingerprint(awayA, region: deviceArea) == fingerprint(awayB, region: deviceArea),
                   "leaving the desk for a manual action stops the mouse while real work remains running")
        }
        print("PASS: \(checks) keyboard, mouse, posture and paused-state checks; mouse \(Int((mouseRatio * 100).rounded()))% of work")
        print("Mouse preview timestamps: \(mouseTimeA), \(mouseTimeB); bout intervals: \(intervals.map { Int($0.rounded()) })")
    }

    private static func canvas() -> CGContext {
        let context = CGContext(data: nil, width: 1200, height: 900, bitsPerComponent: 8, bytesPerRow: 1200 * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.clear(CGRect(x: 0, y: 0, width: 1200, height: 900))
        return context
    }
    private static func employee(standing: CGFloat, time: TimeInterval, activity: EmployeeActivity) -> CGContext {
        let context = canvas()
        PixelEmployee.drawWorking(in: context, standing: standing, time: time,
                                  activity: activity, feet: CGPoint(x: 835, y: 270), pixelSize: 6)
        return context
    }
    private static func scene(_ state: SceneSnapshot, time: TimeInterval, now: Date,
                              reduceMotion: Bool = false) -> CGContext {
        // Render in the scene's native coordinates to compare actual device
        // pixels without depending on a window size or image resampling.
        let context = CGContext(data: nil, width: 1672, height: 941, bitsPerComponent: 8, bytesPerRow: 1672 * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.clear(CGRect(x: 0, y: 0, width: 1672, height: 941))
        SceneRenderer.draw(in: context, bounds: CGRect(x: 0, y: 0, width: 1672, height: 941),
                           snapshot: state, time: time, reduceMotion: reduceMotion, now: now)
        return context
    }
    private static func fingerprint(_ context: CGContext, region: CGRect) -> UInt64 {
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        var value: UInt64 = 1469598103934665603
        for y in Int(region.minY)..<Int(region.maxY) {
            for x in Int(region.minX)..<Int(region.maxX) {
                let index = ((context.height - 1 - y) * context.width + x) * 4
                for channel in 0..<4 { value = (value ^ UInt64(bytes[index + channel])) &* 1099511628211 }
            }
        }
        return value
    }
}
