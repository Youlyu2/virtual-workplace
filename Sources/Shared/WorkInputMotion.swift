import Foundation
import CoreGraphics

/// One shared input rhythm keeps the wrists, pressed keys and mouse in sync.
/// Sampling is pure, so every window and the saver can render independently.
struct WorkInputMotion: Equatable {
    enum Phase: Equatable { case typing, mouse, paused }
    var phase: Phase = .paused
    var leftPress: CGFloat = 0
    var rightPress: CGFloat = 0
    var rightHandMix: CGFloat = 0
    var mouseOffset: CGPoint = .zero
    var click: CGFloat = 0

    static func sample(time: TimeInterval, activity: EmployeeActivity) -> WorkInputMotion {
        guard activity == .working, time.isFinite, time > 0 else { return WorkInputMotion() }
        func smooth(_ x: Double) -> CGFloat {
            let p = max(0, min(1, x)); return CGFloat(p * p * (3 - 2 * p))
        }
        func press(_ phase: Double) -> CGFloat {
            let beat = phase.truncatingRemainder(dividingBy: 1)
            return CGFloat(max(0, sin(beat * .pi * 2)))
        }
        // A hashed schedule looks spontaneous without a host-local random
        // generator. Windows and the saver still agree on the same wrist and
        // device position. Bounded clock math also accepts very large times.
        let scheduleTime = time.truncatingRemainder(dividingBy: 48 * 65_536)
        let block = Int(scheduleTime / 48)
        let local = scheduleTime.truncatingRemainder(dividingBy: 48)
        let start = 14 + random(block, salt: 1) * 16
        let duration = 3 + random(block, salt: 2) * 1.2
        let elapsed = local - start
        let enabled = random(block, salt: 3) > 0.18
        let reach = smooth(elapsed / 0.65)
        let returning = 1 - smooth((elapsed - duration + 0.7) / 0.7)
        let mouse = enabled ? min(reach, returning) : 0

        // Small alternating finger presses, with a quiet pause after each
        // burst. Fade the burst ends so the elbows never snap with a key beat.
        let burst = time.truncatingRemainder(dividingBy: 3.8)
        let burstWeight = min(smooth(burst / 0.15), 1 - smooth((burst - 2.75) / 0.2))
        let typing = burstWeight * (1 - mouse) * 0.6
        var state = WorkInputMotion(phase: mouse > 0.01 ? .mouse : typing < 0.01 ? .paused : .typing,
            leftPress: press(time.truncatingRemainder(dividingBy: 1000) * 3.2) * typing,
            rightPress: press(time.truncatingRemainder(dividingBy: 1000) * 3.2 + 0.5) * typing,
            rightHandMix: mouse)
        if mouse > 0 {
            let t = max(0, elapsed - 0.65)
            let direction = random(block, salt: 4) > 0.5 ? 1.0 : -1.0
            state.mouseOffset = CGPoint(x: sin(t * 1.6) * 4 * Double(mouse) * direction,
                                        y: sin(t * 2.2) * 2 * Double(mouse))
            let first = max(0, 1 - abs(elapsed - 1.15) / 0.12)
            let second = random(block, salt: 5) > 0.45
                ? max(0, 1 - abs(elapsed - (duration - 0.95)) / 0.12) : 0
            state.click = CGFloat(max(first, second)) * mouse
        }
        return state
    }

    private static func random(_ block: Int, salt: UInt64) -> Double {
        var value = UInt64(block) &* 0x9E3779B97F4A7C15 &+ salt &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value >> 11) / 9_007_199_254_740_992
    }
}
