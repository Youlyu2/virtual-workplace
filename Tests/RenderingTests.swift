import AppKit

@main
struct RenderingTests {
    static var checks = 0
    static func expect(_ result: @autoclosure () -> Bool, _ label: String) {
        checks += 1
        if !result() { fatalError("FAIL: \(label)") }
    }
    static func main() {
        _ = NSApplication.shared
        expect(SceneRenderer.hasRoomAssets, "both pixel cabin art layers load for fullscreen rendering")
        for displaySize in [CGSize(width:3024,height:1964), CGSize(width:2560,height:1600),
                            CGSize(width:1920,height:1080)] {
            let display = CGRect(origin:.zero,size:displaySize)
            let viewport = WorldViewport(canvas:display,display:display)!
            let visible = SceneRenderer.roomWorldBounds(for:viewport)
            let clock = FullscreenWorkplaceScene.clockContentRect(visibleRect:visible)
            expect(!clock.isEmpty && clock.minX >= (RoomAssets.usesFlatForeground ? 1504 : 1472),
                   "clock stays within the remaining painted frame at \(displaySize)")
            expect(clock.maxX <= visible.maxX - 12 + 0.001,
                   "Retina aspect-fill cannot crop the final clock digits at \(displaySize)")
        }
        expect(FullscreenWorkplaceScene.clockContentRect(visibleRect:CGRect(x:0,y:0,width:1400,height:941)).isEmpty,
               "a fully cropped clock does not draw outside its visible frame")
        let simulator = TaskSimulator()
        simulator.addTask()
        simulator.setMode(.sitting)
        let animation = SceneAnimation()
        let first = animation.frame(snapshot:simulator.snapshot,time:100,reduceMotion:false)
        expect(first.standing == 0 && first.slacking == 0, "initial pose is stable")
        simulator.setMode(.standing)
        let transition = animation.frame(snapshot:simulator.snapshot,time:100.033,reduceMotion:false)
        expect(transition.standing > 0 && transition.standing < 1, "standing interpolates rather than jumps")
        let reduced = animation.frame(snapshot:simulator.snapshot,time:100.066,reduceMotion:true)
        expect(reduced.standing == 1, "reduced motion snaps to stable posture")
        simulator.removeTask(id:simulator.snapshot.tasks[0].id)
        let fading = animation.frame(snapshot:simulator.snapshot,time:100.1,reduceMotion:false)
        expect(fading.screens.count == 1 && fading.screens[0].1 < 1, "closing screen fades out")
        let gone = animation.frame(snapshot:simulator.snapshot,time:100.2,reduceMotion:true)
        expect(gone.screens.isEmpty, "removed screen leaves the renderer")

        var fingerprints: Set<UInt64> = []
        for mode in [EmployeeMode.sitting,.standing,.slacking] {
            let sim = TaskSimulator()
            for _ in 0..<6 { sim.addTask() }
            sim.setMode(mode)
            for size in [CGSize(width:1200,height:850),CGSize(width:800,height:1200),CGSize(width:1920,height:1080)] {
                let width=Int(size.width), height=Int(size.height)
                let ctx=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
                                  space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                SceneRenderer.draw(in:ctx,bounds:CGRect(origin:.zero,size:size),snapshot:sim.snapshot,time:5,reduceMotion:false)
                let pixels=ctx.data!.assumingMemoryBound(to:UInt8.self)
                var hash:UInt64=1469598103934665603
                for i in stride(from:0,to:width*height*4,by:97) { hash=(hash ^ UInt64(pixels[i])) &* 1099511628211 }
                fingerprints.insert(hash)
                expect(pixels[3] == 255 && pixels[(width*height-1)*4+3] == 255,"opaque background at \(size)")
            }
        }
        expect(fingerprints.count == 9,"all poses and aspect ratios render distinct frames")
        let six = TaskSimulator()
        for _ in 0..<6 { six.addTask() }
        six.setMode(.sitting)
        let ctx = CGContext(data:nil,width:1672,height:941,bitsPerComponent:8,bytesPerRow:1672*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
        SceneRenderer.draw(in:ctx,bounds:CGRect(x:0,y:0,width:1672,height:941),snapshot:six.snapshot,time:0,reduceMotion:true)
        let pixel = ctx.data!.assumingMemoryBound(to:UInt8.self)
        let index = ((941 - 1 - 680) * 1672 + 814) * 4
        expect(pixel[index] < 40 && pixel[index+1] < 80 && pixel[index+2] < 90,
               "upper monitor arm cannot cover the lower monitor information area")
        for count in [0, 1, 3, 6] {
            let fixture = TaskSimulator()
            for _ in 0..<count { fixture.addTask() }
            let frame = SceneFrame(standing:0,slacking:0,screens:fixture.snapshot.tasks.map { ($0,1) })
            expect(FullscreenWorkplaceScene.displaySlots(for:frame).count == max(3,count),
                   "three desk displays persist with \(count) sessions")
            let canvas = CGContext(data:nil,width:1672,height:941,bitsPerComponent:8,bytesPerRow:1672*4,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
            SceneRenderer.draw(in:canvas,bounds:CGRect(x:0,y:0,width:1672,height:941),snapshot:fixture.snapshot,time:0,reduceMotion:true)
            let pixels = canvas.data!.assumingMemoryBound(to:UInt8.self)
            for x in [420,685,980] {
                let offset = ((941 - 1 - 595) * 1672 + x) * 4
                expect(pixels[offset] < 40 && pixels[offset+1] < 90 && pixels[offset+2] < 100,
                       "desk display at \(x) remains painted with \(count) sessions")
            }
        }
        print("PASS: \(checks) animation and rendering checks")
    }
}
