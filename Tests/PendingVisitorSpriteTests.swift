import AppKit
import ImageIO

@main
struct PendingVisitorSpriteTests {
    static var checks = 0
    static let directions: [PixelWalkDirection] = [.down, .left, .right, .up]
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !value() { fatalError("FAIL: \(message)") }
    }
    static func context(_ width: Int = 240, _ height: Int = 200) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
    static func frame(_ variant: Int, _ direction: PixelWalkDirection, _ distance: CGFloat = 0,
                      moving: Bool = false) -> CGContext {
        let c = context()
        expect(PendingVisitorSprites.draw(in: c, variant: variant, direction: direction, distance: distance,
            isMoving: moving, feet: CGPoint(x: 120, y: 20), targetHeight: 144), "production sprite draws")
        return c
    }
    static func hash(_ c: CGContext, topOnly: Bool = false) -> UInt64 {
        let b = c.data!.assumingMemoryBound(to: UInt8.self)
        var result: UInt64 = 1469598103934665603
        let rows = topOnly ? c.height - 62 : c.height
        for i in 0..<(rows * c.width * 4) { result = (result ^ UInt64(b[i])) &* 1099511628211 }
        return result
    }
    static func bounds(_ c: CGContext) -> CGRect {
        let b = c.data!.assumingMemoryBound(to: UInt8.self)
        var left = c.width, right = -1, top = c.height, bottom = -1
        for y in 0..<c.height {
            for x in 0..<c.width where b[(y * c.width + x) * 4 + 3] > 0 {
                left = min(left,x); right = max(right,x); top = min(top,y); bottom = max(bottom,y)
            }
        }
        return CGRect(x:left,y:c.height-bottom-1,width:right-left+1,height:bottom-top+1)
    }
    static func main() throws {
        _ = NSApplication.shared
        expect(PendingVisitorSprites.isAvailable, "all eight independent visitors and six poses load")
        var identities = Set<UInt64>()
        for variant in 0..<8 {
            identities.insert(hash(frame(variant,.down)))
            var headings = Set<UInt64>()
            for direction in directions {
                let neutral = frame(variant,direction)
                headings.insert(hash(neutral))
                let contact = frame(variant,direction,10,moving:true)
                let opposite = frame(variant,direction,30,moving:true)
                expect(hash(neutral) != hash(contact), "authored stride changes from standing")
                expect(hash(frame(variant,direction,30)) == hash(neutral), "corner pause settles feet")
                for c in [neutral,contact,opposite] {
                    let ink = bounds(c)
                    expect(ink.minX >= 48 && ink.maxX <= 192 && ink.minY == 20 && ink.maxY <= 166,
                           "full silhouette including hat and shoes stays within clean bounds with fixed feet")
                    expect((130...146).contains(ink.height), "all poses preserve full-size bodies")
                    let b = c.data!.assumingMemoryBound(to: UInt8.self)
                    expect(b[3] == 0 && b[(c.width * c.height - 1) * 4 + 3] == 0,
                           "atlas background never leaks into the rendered canvas")
                }
                if direction == .down || direction == .up {
                    expect(hash(contact) != hash(opposite), "front and back alternate the contact leg")
                    expect(hash(contact,topOnly:true) == hash(opposite,topOnly:true),
                           "opposite contact never flips hairstyle or clothing above the lower legs")
                }
            }
            expect(headings.count == 4, "front, rear and both profiles are distinct")
        }
        expect(identities.count == 8, "eight simultaneous slots have eight distinct modeled visitors")
        for value in [CGFloat.nan,CGFloat.infinity,-CGFloat.infinity,-1,CGFloat.greatestFiniteMagnitude] {
            _ = frame(0,.left,value,moving:true)
        }
        expect(!PendingVisitorSprites.draw(in:context(),variant:0,direction:.down,distance:0,isMoving:false,
            feet:CGPoint(x:CGFloat.nan,y:20),targetHeight:144), "nonfinite positions are rejected")
        expect(!PendingVisitorSprites.draw(in:context(),variant:0,direction:.down,distance:0,isMoving:false,
            feet:CGPoint(x:120,y:20),targetHeight:.infinity), "nonfinite scale is rejected")
        let c = context(1280,1600)
        c.setFillColor(NSColor(srgbRed:0.89,green:0.87,blue:0.79,alpha:1).cgColor)
        c.fill(CGRect(x:0,y:0,width:1280,height:1600))
        for variant in 0..<8 {
            for (column,direction) in directions.enumerated() {
                _ = PendingVisitorSprites.draw(in:c,variant:variant,direction:direction,distance:0,isMoving:false,
                    feet:CGPoint(x:160+column*320,y:1600-(variant+1)*200+20),targetHeight:144)
            }
        }
        let dir = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("build/visitor-review")
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let output = dir.appendingPathComponent("eight-visitors-four-directions.png")
        let destination = CGImageDestinationCreateWithURL(output as CFURL,"public.png" as CFString,1,nil)!
        CGImageDestinationAddImage(destination,c.makeImage()!,nil)
        expect(CGImageDestinationFinalize(destination),"contact sheet writes")
        print("PASS: \(checks) visitor identity, true profiles, stride, fixed feet, alpha and bounds checks")
        print("PREVIEW: \(output.path)")
    }
}
