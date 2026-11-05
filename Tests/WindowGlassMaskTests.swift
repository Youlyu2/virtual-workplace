import Foundation
import CoreGraphics

// The pure tests deliberately cannot load the real generated asset.
enum RoomAssets {
    static let windowForeground: CGImage? = nil
    static let usesFlatForeground = true
}

@main
enum WindowGlassMaskTests {
    private static var checks = 0
    private static let width = 1672, height = 941
    private static var canvas: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }
    private static func expect(_ value: @autoclosure () -> Bool, _ description: String) {
        checks += 1
        if !value() { fatalError("FAIL: \(description)") }
    }
    private static func context(_ w: Int = width, _ h: Int = height) -> CGContext {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
    private static func paint(_ c: CGContext, _ rect: CGRect, alpha: CGFloat,
                              red: CGFloat = 0.15, green: CGFloat = 0.35, blue: CGFloat = 0.55) {
        c.setBlendMode(.copy)
        c.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: alpha))
        c.fill(rect)
    }
    private static func foreground(alternateRGB: Bool = false) -> CGImage {
        let c = context()
        paint(c, canvas, alpha: 1, red: alternateRGB ? 0.9 : 0.1)
        // Two transparent glass regions at deliberately asymmetric heights.
        paint(c, CGRect(x:205,y:705,width:70,height:50), alpha:0)
        paint(c, CGRect(x:205,y:548,width:55,height:40), alpha:0)
        // Opaque ivy and a soft cutout edge must remain in the foreground.
        paint(c, CGRect(x:225,y:730,width:8,height:18), alpha:1)
        paint(c, CGRect(x:216,y:714,width:4,height:30), alpha:0.25)
        // A stray hole in a mullion and another outside the window must never
        // enlarge the safe geometric clip.
        paint(c, CGRect(x:186,y:700,width:10,height:60), alpha:0)
        paint(c, CGRect(x:1000,y:500,width:10,height:10), alpha:0)
        return c.makeImage()!
    }
    private static func rendered(mask: CGImage?, useDefault: Bool = false) -> CGContext {
        let c = context()
        paint(c, canvas, alpha:1, red:0, green:0, blue:1)
        if useDefault { WindowGlassMask.clip(in:c) }
        else { WindowGlassMask.clip(in:c,using:mask) }
        paint(c, canvas, alpha:1, red:1, green:0, blue:0)
        return c
    }
    private static func replaced(_ c: CGContext, _ x: Int, _ y: Int) -> Bool {
        let p = c.data!.assumingMemoryBound(to:UInt8.self)
        let offset = ((height - 1 - y) * width + x) * 4
        return p[offset] > 220 && p[offset + 1] < 100 && p[offset + 2] < 60
    }

    static func main() {
        expect(WindowGlassMask.bounds == CGRect(x:94,y:538,width:300,height:226),
               "glass mask keeps the approved cabin coordinate system")
        expect(WindowGlassMask.path.contains(CGPoint(x:250,y:720))
               && WindowGlassMask.path.contains(CGPoint(x:235,y:560)),
               "authored upper and lower panes are included")
        expect(!WindowGlassMask.path.contains(CGPoint(x:190,y:725))
               && !WindowGlassMask.path.contains(CGPoint(x:1000,y:505)),
               "mullions and the rest of the room are outside the safety path")
        expect(WindowGlassMask.makeMask(foreground:nil) == nil && !WindowGlassMask.usesArtworkMask,
               "missing cutout cleanly chooses the conservative flat-pane fallback")
        let missing = rendered(mask:nil,useDefault:true)
        expect(replaced(missing,250,720) && !replaced(missing,190,725),
               "fallback actually clips drawing to glass and protects wooden frames")
        expect(!replaced(missing,110,725) && !replaced(missing,350,560),
               "fallback retains the curtain and lower-pane plants when artwork alpha is missing")
        let opaque = context();paint(opaque,canvas,alpha:1)
        expect(WindowGlassMask.makeMask(foreground:opaque.makeImage()) == nil,
               "all-opaque export is rejected instead of hiding the entire scenic view")
        let empty = context();paint(empty,canvas,alpha:0)
        expect(WindowGlassMask.makeMask(foreground:empty.makeImage()) == nil,
               "all-transparent unrelated image is rejected")
        expect(WindowGlassMask.makeMask(foreground:context(32,32).makeImage()) == nil,
               "incorrect source dimensions cannot be aligned onto the room")
        let narrowExport = context(width - 1, height)
        narrowExport.draw(foreground(), in:CGRect(x:0,y:0,width:width - 1,height:height))
        expect(WindowGlassMask.makeMask(foreground:narrowExport.makeImage()) != nil,
               "a one-pixel export width difference normalizes to the same room coordinate system")
        let wrongAspect = context(1000,1000)
        wrongAspect.draw(foreground(), in:CGRect(x:0,y:0,width:1000,height:1000))
        expect(WindowGlassMask.makeMask(foreground:wrongAspect.makeImage()) == nil,
               "a materially different aspect ratio cannot move glass into room furniture")
        let tiny = context();paint(tiny,canvas,alpha:1)
        paint(tiny,CGRect(x:250,y:720,width:2,height:2),alpha:0)
        expect(WindowGlassMask.makeMask(foreground:tiny.makeImage()) == nil,
               "implausibly tiny glass coverage uses the safe fallback")
        let mask = WindowGlassMask.makeMask(foreground:foreground())
        expect(mask != nil, "a full-room foreground with plausible glass holes produces a mask")
        guard let mask else { return }
        expect(mask.width == 300 && mask.height == 226 && !mask.isMask,
               "cached clip is compact RGBA alpha rather than inverse grayscale-mask semantics")
        let image = rendered(mask:mask)
        expect(replaced(image,250,720) && replaced(image,235,560),
               "transparent source glass admits new outdoor drawing in both asymmetric panes")
        expect(!replaced(image,250,221) && !replaced(image,235,381),
               "source alpha and clipping maintain the correct top-to-bottom orientation")
        expect(!replaced(image,228,735), "opaque indoor ivy survives replacement within a glass pane")
        expect(!replaced(image,217,720), "soft foreground alpha is conservatively retained")
        expect(!replaced(image,215,720) && replaced(image,213,720),
               "one-pixel erosion protects the edge adjacent to semi-transparent foreground")
        expect(!replaced(image,205,715) && replaced(image,207,715),
               "empty hole borders are eroded by one pixel without losing the clear interior")
        expect(!replaced(image,190,725) && !replaced(image,1004,505),
               "stray transparency cannot erase wood or other room details")
        expect(!replaced(image,280,715), "opaque glass-region source pixels remain protected")
        let alternate = WindowGlassMask.makeMask(foreground:foreground(alternateRGB:true))!
        expect(mask.dataProvider!.data! == alternate.dataProvider!.data!,
               "generated RGB never changes the foreground protection mask")
        let bytes = mask.dataProvider!.data! as Data
        expect(stride(from:3,to:bytes.count,by:4).allSatisfy { bytes[$0] == 0 || bytes[$0] == 255 },
               "no translucent halo from generated soft alpha reaches the rendered glass")
        print("PASS: \(checks) window glass alpha, foreground protection, orientation and fallback checks (synthetic images only)")
    }
}
