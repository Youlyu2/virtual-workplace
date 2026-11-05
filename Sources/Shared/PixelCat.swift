import AppKit
import ImageIO

private final class PixelCatResourceAnchor: NSObject {}

/// The cat owns no timer. Every host samples the shared scene clock so hiding
/// a window or stopping a screen saver also stops this animation.
enum PixelCat {
    static var hasSprites: Bool { sprites?.count == 3 }
    static let restingPosition = CGPoint(x: 615, y: 88)

    private struct Motion {
        var pose: Int = 0       // curled, awake sitting, walking
        var x: CGFloat = 0
        var y: CGFloat = 0
        var facing: CGFloat = 1
        var breath: CGFloat = 0
        var tail: CGFloat = 0
        var paw: CGFloat = 0
        var blink = false
        var ear: CGFloat = 0
        var reaction: Int = 0   // little notice mark, then a heart
        var reactionLift: CGFloat = 0
    }
    private struct Sprite {
        var body: CGImage
        var blinkingBody: CGImage
        var tail: CGImage
        var paw: CGImage?
        var tailRoot: CGPoint
        var pawRoot: CGPoint
        var rect: CGRect
        var scale: CGFloat
        var baseline: CGFloat
    }

    static func draw(in c: CGContext, time: TimeInterval, interaction: CGFloat?, reduceMotion: Bool) {
        let t = time.isFinite ? max(0, time) : 0
        let motion = state(at: t, interaction: interaction, reduceMotion: reduceMotion)
        let feet = CGPoint(x: restingPosition.x + motion.x, y: restingPosition.y + motion.y)
        c.saveGState()
        c.setShouldAntialias(false)
        c.interpolationQuality = .none
        // A shallow pixel contact shadow anchors the feet even during a hop.
        fill(c, CGRect(x: feet.x - 47, y: restingPosition.y - 3, width: 94, height: 7), 0x375749, alpha: 0.24)
        fill(c, CGRect(x: feet.x - 37, y: restingPosition.y - 6, width: 74, height: 4), 0x375749, alpha: 0.12)
        if let sprite = sprites?[motion.pose] {
            drawSprite(sprite, in: c, feet: feet, motion: motion)
        } else {
            drawNative(in: c, feet: feet, motion: motion)
        }
        if motion.reaction > 0 { drawReaction(in: c, feet: feet, motion: motion) }
        c.restoreGState()
    }

    private static func state(at time: TimeInterval, interaction: CGFloat?, reduceMotion: Bool) -> Motion {
        if let interaction, interaction.isFinite {
            let p = max(0, min(1, interaction))
            if reduceMotion {
                return Motion(pose: 1, tail: 0.2, paw: 1, reaction: 2)
            }
            var m = Motion()
            m.pose = p < 0.10 || p > 0.94 ? 0 : p < 0.30 || p > 0.78 ? 1 : 2
            let play = max(0, min(1, (p - 0.25) / 0.53))
            m.x = sin(play * .pi) * 37
            m.y = m.pose == 2 ? abs(sin(play * .pi * 3)) * 15 : 0
            m.breath = p > 0.1 ? sin(p * .pi * 8) : 0
            m.tail = sin(p * .pi * 12) * 1.1
            m.paw = p > 0.22 && p < 0.84 ? max(0, sin(p * .pi * 9)) : 0
            m.ear = p < 0.25 ? 1 : 0
            m.blink = p > 0.72 && p < 0.75
            m.reaction = p > 0.12 && p < 0.30 ? 1 : p > 0.37 && p < 0.87 ? 2 : 0
            m.reactionLift = m.reaction == 2 ? (p - 0.37) * 14 : 0
            return m
        }
        guard !reduceMotion, time > 0 else { return Motion() }
        let cycle = time.truncatingRemainder(dividingBy: 42)
        var m = Motion()
        m.breath = sin(time * 1.6) > 0.2 ? 1 : 0
        m.blink = time.truncatingRemainder(dividingBy: 4.6) > 4.39
        m.ear = cycle > 5.3 && cycle < 5.8 || cycle > 12 && cycle < 12.3 ? 1 : 0
        m.tail = sin(time * 1.25) * 0.18
        if cycle >= 14 && cycle < 22 {
            m.pose = 1
            m.tail = sin(time * 2.8) * 0.72
            m.paw = cycle > 18.4 && cycle < 20.6 ? max(0, sin(time * 3.6)) : 0
        } else if cycle >= 22 && cycle < 33 {
            m.pose = 2
            let walk = (cycle - 22) / 11
            m.x = sin(walk * .pi) * 62
            m.facing = walk < 0.5 ? 1 : -1
            m.y = floor(abs(sin(time * 5.5)) * 2)
            m.paw = sin(time * 5.5)
            m.tail = sin(time * 3.4) * 0.8
        } else if cycle >= 33 && cycle < 38 {
            m.pose = 1
            m.tail = sin(time * 2.2) * 0.45
            m.ear = cycle > 34.6 && cycle < 35 ? 1 : 0
        }
        return m
    }

    private static func drawSprite(_ sprite: Sprite, in c: CGContext, feet: CGPoint, motion: Motion) {
        let width = sprite.rect.width * sprite.scale
        let height = sprite.rect.height * sprite.scale
        let drawRect = CGRect(x: -width / 2, y: -(sprite.rect.maxY - sprite.baseline) * sprite.scale,
                              width: width, height: height).integral
        func joint(_ sourcePoint: CGPoint) -> CGPoint {
            CGPoint(x: (sourcePoint.x - sprite.rect.minX) * sprite.scale - width/2,
                    y: (sprite.baseline - sourcePoint.y) * sprite.scale)
        }
        c.saveGState()
        c.translateBy(x: feet.x.rounded(), y: feet.y.rounded())
        c.scaleBy(x: motion.facing, y: 1)
        let tailRoot = joint(sprite.tailRoot)
        c.saveGState();c.translateBy(x:tailRoot.x,y:tailRoot.y)
        c.rotate(by: motion.tail * (motion.pose == 0 ? 0.22 : 0.48))
        c.translateBy(x:-tailRoot.x,y:-tailRoot.y)
        c.draw(sprite.tail,in:drawRect)
        c.restoreGState()
        let breathing = motion.pose == 0 ? motion.breath.rounded() : 0
        c.draw(motion.blink ? sprite.blinkingBody : sprite.body, in: drawRect.offsetBy(dx: 0, dy: breathing))
        if let paw = sprite.paw {
            let root = joint(sprite.pawRoot)
            c.saveGState();c.translateBy(x:root.x,y:root.y)
            c.rotate(by: max(0,motion.paw) * (motion.pose == 1 ? 0.85 : 0.5))
            c.translateBy(x:-root.x,y:-root.y)
            c.draw(paw,in:drawRect)
            c.restoreGState()
        }
        c.restoreGState()
    }

    private static func drawNative(in c: CGContext, feet: CGPoint, motion: Motion) {
        let unit: CGFloat = 3.3
        c.saveGState()
        c.translateBy(x: feet.x.rounded(), y: feet.y.rounded())
        c.scaleBy(x: unit * motion.facing, y: unit)
        let sleeping = motion.pose == 0
        let sitting = motion.pose == 1
        drawTail(in: c, root: CGPoint(x: sleeping ? -11 : -7, y: sleeping ? 6 : 8),
                 amount: motion.tail, sleeping: sleeping, unit: 1)
        if sleeping {
            // Wide curled body, white belly and a tucked front paw.
            poly(c, [(-17, 4),(-18, 10),(-15, 17),(-8, 21),(2, 20),(10, 15),(13, 5),(7, 1),(-8, 1)], 0x573922)
            poly(c, [(-15, 5),(-16, 10),(-13, 16),(-7, 19),(1, 18),(8, 14),(10, 6),(6, 3),(-7, 3)], 0xCE792B)
            rect(c, -12, 12, 9, 5 + Int(motion.breath), 0xEB9C42)
            rect(c, -13, 8, 4, 5, 0xE28B32); rect(c, -7, 17, 3, 2, 0xF7B75C)
            rect(c, -14, 8, 3, 3, 0x94501E); rect(c, -8, 14, 3, 4, 0x9C5520)
            rect(c, -1, 13, 3, 5, 0x9C5520); rect(c, -7, 4, 16, 5, 0xF2D6A1)
            rect(c, -5, 3, 11, 2, 0xA16B39); rect(c, -4, 4, 9, 2, 0xFFF0C4)
            drawHead(in: c, x: 4, y: 4, sleeping: true, blink: true, ear: motion.ear)
        } else if sitting {
            // Upright haunches and a distinct white chest, with separated paws.
            poly(c, [(-12, 3),(-12, 10),(-8, 18),(-6, 24),(5, 24),(10, 15),(12, 5),(8, 1),(-8, 1)], 0x573922)
            poly(c, [(-10, 4),(-10, 10),(-6, 18),(-4, 23),(4, 23),(8, 14),(10, 5),(7, 3),(-7, 3)], 0xD78231)
            rect(c, -7, 12, 4, 7, 0xEBA24A); rect(c, -8, 8, 3, 4, 0x99501E)
            rect(c, 1, 4, 6, 16, 0xF4DDB2); rect(c, 3, 4, 3, 15, 0xFFEAC2)
            rect(c, -7, 1, 8, 3, 0x65432A); rect(c, 3, 1, 8, 3, 0x65432A)
            rect(c, -6, 2, 6, 2, 0xF4DDB2); rect(c, 4, 2, 6, 2, 0xFFEAC2)
            drawHead(in: c, x: -3, y: 19, sleeping: false, blink: motion.blink, ear: motion.ear)
            if motion.paw > 0.1 {
                let y = 8 + Int(motion.paw * 7)
                rect(c, 8, y, 5, 4, 0x65432A); rect(c, 8, y + 1, 4, 3, 0xF9E7BC)
            }
        } else {
            // A low walking body. Opposing leg positions produce a real gait.
            poly(c, [(-15, 5),(-15, 13),(-10, 18),(6, 17),(13, 12),(13, 5)], 0x573922)
            rect(c, -13, 6, 23, 9, 0xD9812B); rect(c, -10, 13, 16, 3, 0xEDAB4E)
            for x in [-9, -2, 5] { rect(c, x, 10, 3, 5, 0x9D5221) }
            let stride = motion.paw > 0 ? 1 : -1
            for (x, step) in [(-10, stride),(-5, -stride),(6, -stride),(10, stride)] {
                rect(c, x + step, 1, 4, 7, 0x6B452C)
                rect(c, x + step, 1, 4, 3, 0xF7E4B8)
            }
            rect(c, 5, 5, 7, 7, 0xF3D7A6)
            drawHead(in: c, x: 6, y: 10, sleeping: false, blink: motion.blink, ear: motion.ear)
        }
        c.restoreGState()
    }

    private static func drawHead(in c: CGContext, x: Int, y: Int, sleeping: Bool, blink: Bool, ear: CGFloat) {
        let twitch = ear > 0 ? 1 : 0
        poly(c, [(x-1,y+2),(x-1,y+10),(x+1,y+17+twitch),(x+6,y+13),(x+11,y+17),(x+14,y+10),(x+14,y+3),(x+11,y),(x+3,y)], 0x573922)
        poly(c, [(x+1,y+3),(x+1,y+10),(x+2,y+14+twitch),(x+6,y+11),(x+10,y+14),(x+12,y+10),(x+12,y+3),(x+10,y+2),(x+3,y+2)], 0xDD8B38)
        rect(c, x+2, y+10, 2, 3, 0xE6AC83); rect(c, x+10, y+10, 2, 3, 0xE6AC83)
        rect(c, x+5, y+9, 3, 5, 0x9B5122)
        rect(c, x+3, y+2, 9, 6, 0xF9E2B5); rect(c, x+6, y+6, 3, 5, 0xF9E2B5)
        rect(c, x+6, y+5, 2, 1, 0x8C573D)
        if sleeping || blink {
            rect(c, x+2, y+7, 3, 1, 0x5E402B); rect(c, x+9, y+7, 3, 1, 0x5E402B)
        } else {
            rect(c, x+3, y+7, 2, 3, 0x403B27); rect(c, x+10, y+7, 2, 3, 0x403B27)
            rect(c, x+3, y+9, 1, 1, 0xE9E8AE); rect(c, x+10, y+9, 1, 1, 0xE9E8AE)
        }
        rect(c, x-2, y+4, 4, 1, 0xD8C294); rect(c, x+12, y+4, 4, 1, 0xD8C294)
    }

    private static func drawTail(in c: CGContext, root: CGPoint, amount: CGFloat, sleeping: Bool, unit: CGFloat) {
        c.saveGState()
        c.translateBy(x: root.x, y: root.y)
        c.rotate(by: amount * (sleeping ? 0.22 : 0.48))
        c.scaleBy(x: unit, y: unit)
        let points: [(CGFloat, CGFloat)] = sleeping
            ? [(0,0),(-4,-1),(-9,-1),(-12,1),(-12,5),(-10,7)]
            : [(0,0),(-4,1),(-7,5),(-8,10),(-6,14),(-3,15)]
        for (index, point) in points.enumerated() {
            fill(c, CGRect(x: point.0-2, y: point.1-2, width: 5, height: 5), 0x633C24)
            fill(c, CGRect(x: point.0-1, y: point.1-1, width: 3, height: 3), index == points.count-1 ? 0xF8DFAD : index % 2 == 0 ? 0xD88832 : 0xF0AC4F)
        }
        c.restoreGState()
    }

    private static func drawReaction(in c: CGContext, feet: CGPoint, motion: Motion) {
        let x = feet.x + 7, y = feet.y + (motion.pose == 0 ? 90 : 116) + motion.reactionLift
        c.saveGState(); c.translateBy(x: x.rounded(), y: y.rounded()); c.scaleBy(x: 3, y: 3)
        if motion.reaction == 1 {
            fill(c, CGRect(x: -1, y: 2, width: 3, height: 8), 0x694528)
            fill(c, CGRect(x: 0, y: 3, width: 1, height: 6), 0xFFE5A0)
            fill(c, CGRect(x: -1, y: -2, width: 3, height: 3), 0x694528)
            fill(c, CGRect(x: 0, y: -1, width: 1, height: 1), 0xFFE5A0)
        } else {
            let rows = [".OO.OO.","OHHHHHO","OHHHHHO",".OHHHO.","..OHO..","...O..."]
            for (row, line) in rows.enumerated() {
                for (column, pixel) in line.enumerated() where pixel != "." {
                    fill(c, CGRect(x: column-3, y: rows.count-row, width: 1, height: 1), pixel == "O" ? 0x845038 : 0xEE9D7D)
                }
            }
        }
        c.restoreGState()
    }

    private static let sprites: [Sprite]? = {
        let bundles = [Bundle(for: PixelCatResourceAnchor.self), Bundle.main]
        var paths = bundles.compactMap { $0.url(forResource: "cat-kit", withExtension: "png", subdirectory: "Room") }
        paths.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Room/cat-kit.png"))
        guard let path = paths.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let source = CGImageSourceCreateWithURL(path as CFURL, nil),
              let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil),
              atlas.width >= 192, atlas.width <= 8192, atlas.height >= 64, atlas.height <= 4096 else { return nil }
        // Explicit source regions exclude the neighbouring tail fragment at
        // x1000 that crosses the generated sheet's equal-column boundary.
        // The common baselines and near-equal head scales keep the same cat's
        // physical size through a curl, a sit and a walk.
        let descriptors: [(CGRect,CGFloat,CGFloat,CGPoint,[CGRect],CGRect?,CGPoint,[CGRect])] = [
            (CGRect(x:0,y:470,width:512,height:325),0.24,775,CGPoint(x:56,y:735),
             [CGRect(x:0,y:720,width:310,height:75)],nil,.zero,[]),
            (CGRect(x:520,y:240,width:468,height:555),0.20,760,CGPoint(x:643,y:720),
             [CGRect(x:520,y:500,width:125,height:285)],CGRect(x:838,y:650,width:73,height:112),CGPoint(x:849,y:649),
             [CGRect(x:849,y:415,width:34,height:39)]),
            (CGRect(x:990,y:290,width:546,height:505),0.21,770,CGPoint(x:1110,y:582),
             [CGRect(x:990,y:360,width:160,height:140),CGRect(x:990,y:500,width:125,height:103)],
             CGRect(x:1400,y:614,width:115,height:156),CGPoint(x:1420,y:626),
             [CGRect(x:1421,y:449,width:35,height:39)])
        ]
        let sx = CGFloat(atlas.width)/1536, sy = CGFloat(atlas.height)/1024
        guard abs(sx-sy)<0.02 else { return nil }
        var result: [Sprite] = []
        for (rect,scale,baseline,tailRoot,tails,pawRect,pawRoot,eyes) in descriptors {
            let sourceRect = CGRect(x:rect.minX*sx,y:rect.minY*sy,width:rect.width*sx,height:rect.height*sy).integral
            guard let cell=atlas.cropping(to:sourceRect),let cleaned=cleanedPixels(cell) else { return nil }
            let w=cell.width,h=cell.height
            var body=cleaned,tail=cleaned,paw=cleaned,blink=cleaned
            for y in 0..<h { for x in 0..<w {
                let index=(y*w+x)*4
                let point=CGPoint(x:(sourceRect.minX+CGFloat(x))/sx,y:(sourceRect.minY+CGFloat(y))/sy)
                let isTail=tails.contains { $0.contains(point) }
                let isPaw=pawRect?.contains(point) ?? false
                if isTail || isPaw { for channel in 0..<4 { body[index+channel]=0 } }
                if !isTail { for channel in 0..<4 { tail[index+channel]=0 } }
                if !isPaw { for channel in 0..<4 { paw[index+channel]=0 } }
            } }
            blink=body
            for y in 0..<h { for x in 0..<w {
                let index=(y*w+x)*4
                guard body[index+3]>0 else { continue }
                let point=CGPoint(x:(sourceRect.minX+CGFloat(x))/sx,y:(sourceRect.minY+CGFloat(y))/sy)
                for eye in eyes where eye.contains(point) {
                    let lid = point.y >= eye.minY + eye.height*0.58 && point.y < eye.minY + eye.height*0.78
                    let color:UInt32 = lid ? 0x60371F : point.x > eye.maxX-8 ? 0xFFE2AA : 0xF9AC3B
                    blink[index]=UInt8((color>>16)&255);blink[index+1]=UInt8((color>>8)&255)
                    blink[index+2]=UInt8(color&255);blink[index+3]=255
                }
            } }
            guard let bodyImage=image(body,w:w,h:h),let blinkImage=image(blink,w:w,h:h),let tailImage=image(tail,w:w,h:h) else { return nil }
            result.append(Sprite(body:bodyImage,blinkingBody:blinkImage,tail:tailImage,
                                 paw:pawRect == nil ? nil : image(paw,w:w,h:h),tailRoot:tailRoot,pawRoot:pawRoot,
                                 rect:rect,scale:scale,baseline:baseline))
        }
        return result
    }()

    private static func cleanedPixels(_ image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        guard let bitmap = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
            let pixels = bitmap.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var visible = false
        for y in 0..<h {
            for x in 0..<w {
                let offset = (y*w+x)*4, alpha = Int(pixels[offset+3])
                if alpha < 160 { for channel in 0..<4 { pixels[offset+channel] = 0 }; continue }
                for channel in 0..<3 { pixels[offset+channel] = UInt8(min(255,Int(pixels[offset+channel])*255/alpha)) }
                pixels[offset+3] = 255
                visible = true
            }
        }
        guard visible else { return nil }
        return Array(UnsafeBufferPointer(start:pixels,count:w*h*4))
    }
    private static func image(_ pixels:[UInt8],w:Int,h:Int)->CGImage? {
        guard let provider=CGDataProvider(data:Data(pixels) as CFData) else { return nil }
        return CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,
                       space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)
    }

    private static func rect(_ c: CGContext, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: UInt32) {
        fill(c, CGRect(x: x, y: y, width: w, height: h), color)
    }
    private static func fill(_ c: CGContext, _ r: CGRect, _ color: UInt32, alpha: CGFloat = 1) {
        c.setFillColor(CGColor(red: CGFloat((color>>16)&255)/255, green: CGFloat((color>>8)&255)/255,
                              blue: CGFloat(color&255)/255, alpha: alpha))
        c.fill(r.integral)
    }
    private static func poly(_ c: CGContext, _ vertices: [(Int,Int)], _ color: UInt32) {
        guard let first = vertices.first else { return }
        c.beginPath();c.move(to:CGPoint(x:first.0,y:first.1))
        for vertex in vertices.dropFirst() { c.addLine(to:CGPoint(x:vertex.0,y:vertex.1)) }
        c.closePath();c.setFillColor(CGColor(red: CGFloat((color>>16)&255)/255,green: CGFloat((color>>8)&255)/255,
            blue: CGFloat(color&255)/255,alpha: 1));c.fillPath()
    }
}
