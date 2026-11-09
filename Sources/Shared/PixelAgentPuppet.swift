import AppKit

/// A small articulated pixel human. Every limb is drawn from the supplied
/// joint angles; there are no gesture names, animation clips or sprite poses.
/// Coordinates are the existing room's scene units, with the root on the floor.
enum PixelAgentPuppet {
    private enum Paint {
        static let outline = color(0x302D29)
        static let green = color(0x638442)
        static let greenDark = color(0x3E5D32)
        static let greenLight = color(0x91AC5D)
        static let greenDeep = color(0x2E462B)
        static let trousers = color(0x514740)
        static let trousersLight = color(0x756559)
        static let trousersDark = color(0x38342F)
        static let skin = color(0xD7A772)
        static let skinLight = color(0xF1C992)
        static let skinDark = color(0xAE794F)
        static let hair = color(0x705033)
        static let hairDark = color(0x463222)
        static let hairLight = color(0x997345)
        static let shoe = color(0xD7C396)
        static let shoeLight = color(0xF0DFB7)
        static let eye = color(0x2D2926)
        static let eyeWhite = color(0xFFF1D7)
        static let mouth = color(0x773F37)
        static let tongue = color(0xC77A6D)
        static let shadow = color(0x2E2B26, alpha: 0.19)
    }

    private struct Limb {
        var start: CGPoint
        var bend: CGPoint
        var end: CGPoint
        var endAngle: CGFloat
    }

    private struct Rig {
        let pose: AgentPose
        let lean: CGFloat
        let side: Bool
        let leftArm: Limb
        let rightArm: Limb
        let leftLeg: Limb
        let rightLeg: Limb
        let lift: CGFloat

        init(_ pose: AgentPose) {
            self.pose = pose
            lean = radians(safeAngle(pose, .torsoLean))
            let isSide = pose.facing == .left || pose.facing == .right
            side = isSide
            func body(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                let local = rotated(CGPoint(x: x, y: y - 104), by: radians(safeAngle(pose, .torsoLean)))
                return CGPoint(x: local.x, y: local.y + 104)
            }
            func arm(left: Bool) -> Limb {
                let shoulder: AgentJoint = left ? .leftShoulder : .rightShoulder
                let elbow: AgentJoint = left ? .leftElbow : .rightElbow
                let wrist: AgentJoint = left ? .leftWrist : .rightWrist
                let start = body((left ? -1 : 1) * (isSide ? 13 : 34), 184)
                let upper = radians(safeAngle(pose, shoulder) + safeAngle(pose, .torsoLean))
                let lower = upper + radians(safeAngle(pose, elbow))
                let bend = offset(start, length: 48, angle: upper)
                return Limb(start: start, bend: bend, end: offset(bend, length: 43, angle: lower),
                    endAngle: lower + radians(safeAngle(pose, wrist)))
            }
            func leg(left: Bool) -> Limb {
                let hip: AgentJoint = left ? .leftHip : .rightHip
                let knee: AgentJoint = left ? .leftKnee : .rightKnee
                let start = CGPoint(x: (left ? -1 : 1) * (isSide ? 9 : 17), y: 104)
                let upper = radians(safeAngle(pose, hip))
                let lower = upper + radians(safeAngle(pose, knee))
                let bend = offset(start, length: 46, angle: upper)
                return Limb(start: start, bend: bend, end: offset(bend, length: 46, angle: lower), endAngle: lower)
            }
            leftArm = arm(left: true); rightArm = arm(left: false)
            leftLeg = leg(left: true); rightLeg = leg(left: false)
            // Bend either leg freely without letting its sole fall through the
            // ground. The lower of the two feet remains the contact anchor.
            lift = -(min(leftLeg.end.y, rightLeg.end.y) - 12)
        }

        func body(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let point = rotated(CGPoint(x: x, y: y - 104), by: lean)
            return CGPoint(x: point.x, y: point.y + 104)
        }

        func head(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let neck = body(0, 205)
            let point = rotated(CGPoint(x: x, y: y + 29),
                by: lean + radians(safeAngle(pose, .headTilt)))
            return CGPoint(x: neck.x + point.x, y: neck.y + point.y)
        }
    }

    static func draw(in c: CGContext, pose: AgentPose, scale: CGFloat = 1) {
        guard pose.x.isFinite, pose.y.isFinite, scale.isFinite, scale > 0, scale <= 4 else { return }
        let rig = Rig(pose)
        c.saveGState()
        defer { c.restoreGState() }
        c.setShouldAntialias(false)
        c.interpolationQuality = .none
        c.translateBy(x: CGFloat(pose.x).rounded(), y: CGFloat(pose.y).rounded())
        c.scaleBy(x: scale, y: scale)
        let feetMin = min(rig.leftLeg.end.x, rig.rightLeg.end.x) - 20
        let feetMax = max(rig.leftLeg.end.x, rig.rightLeg.end.x) + 20
        ellipse(in: c, center: CGPoint(x: (feetMin + feetMax) / 2, y: 0),
            width: max(45, feetMax - feetMin), height: 9, fill: Paint.shadow)
        c.translateBy(x: 0, y: rig.lift)

        let leftIsFar = pose.facing == .left
        let farLeg = leftIsFar ? rig.rightLeg : rig.leftLeg
        let nearLeg = leftIsFar ? rig.leftLeg : rig.rightLeg
        drawLeg(in: c, limb: farLeg, facing: pose.facing, far: rig.side)
        drawLeg(in: c, limb: nearLeg, facing: pose.facing, far: false)

        if rig.side {
            drawArm(in: c, limb: leftIsFar ? rig.rightArm : rig.leftArm, far: true)
        } else {
            // The upper sleeves join behind the shirt. Forearms can cross its
            // front independently without dragging any torso or hair pixels.
            upperArm(in: c, limb: rig.leftArm, far: false)
            upperArm(in: c, limb: rig.rightArm, far: false)
        }
        drawTorso(in: c, rig: rig)
        if rig.side {
            drawArm(in: c, limb: leftIsFar ? rig.leftArm : rig.rightArm, far: false)
        } else {
            lowerArm(in: c, limb: rig.leftArm, far: false)
            lowerArm(in: c, limb: rig.rightArm, far: false)
        }
        drawHead(in: c, rig: rig)
    }

    private static func drawLeg(in c: CGContext, limb: Limb, facing: AgentFacing, far: Bool) {
        let base = far ? Paint.trousersDark : Paint.trousers
        segment(in: c, from: limb.start, to: limb.bend, width: 29, fill: base,
                light: far ? nil : Paint.trousersLight, dark: Paint.trousersDark)
        segment(in: c, from: limb.bend, to: limb.end, width: 25, fill: base,
                light: far ? nil : Paint.trousersLight, dark: Paint.trousersDark)
        let side: CGFloat = facing == .left ? -1 : facing == .right ? 1 : 0
        let x = limb.end.x + side * 5, y = limb.end.y
        polygon(in: c, points: [CGPoint(x: x - 15, y: y - 12), CGPoint(x: x + 16, y: y - 12),
            CGPoint(x: x + 18, y: y - 5), CGPoint(x: x + 12, y: y + 7),
            CGPoint(x: x - 11, y: y + 7), CGPoint(x: x - 16, y: y - 2)], fill: Paint.outline)
        rectangle(in: c, x: x - 12, y: y - 8, width: 25, height: 11, fill: far ? Paint.trousersLight : Paint.shoe)
        rectangle(in: c, x: x - 9, y: y - 1, width: 17, height: 5, fill: far ? Paint.shoe : Paint.shoeLight)
        rectangle(in: c, x: x - 12, y: y - 10, width: 25, height: 3, fill: Paint.trousersDark)
    }

    private static func upperArm(in c: CGContext, limb: Limb, far: Bool) {
        segment(in: c, from: limb.start, to: limb.bend, width: 27,
            fill: far ? Paint.greenDark : Paint.green, light: far ? nil : Paint.greenLight,
            dark: Paint.greenDeep)
    }

    private static func lowerArm(in c: CGContext, limb: Limb, far: Bool) {
        segment(in: c, from: limb.bend, to: limb.end, width: 21,
            fill: far ? Paint.greenDark : Paint.green, light: far ? nil : Paint.greenLight,
            dark: Paint.greenDeep)
        let cuffStart = offset(limb.end, length: -5, angle: limb.endAngle)
        segment(in: c, from: cuffStart, to: offset(limb.end, length: 4, angle: limb.endAngle),
            width: 21, fill: Paint.greenDark, light: Paint.greenLight, dark: nil)
        hand(in: c, wrist: limb.end, angle: limb.endAngle, far: far)
    }

    private static func drawArm(in c: CGContext, limb: Limb, far: Bool) {
        upperArm(in: c, limb: limb, far: far)
        lowerArm(in: c, limb: limb, far: far)
    }

    private static func hand(in c: CGContext, wrist: CGPoint, angle: CGFloat, far: Bool) {
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let point = rotated(CGPoint(x: x, y: y), by: angle)
            return CGPoint(x: wrist.x + point.x, y: wrist.y + point.y)
        }
        polygon(in: c, points: [at(-9, 3), at(8, 3), at(11, -5), at(8, -20),
            at(-7, -22), at(-12, -13), at(-12, -3)], fill: Paint.outline)
        polygon(in: c, points: [at(-6, 0), at(5, 0), at(8, -6), at(5, -17),
            at(-5, -18), at(-9, -11), at(-9, -5)], fill: far ? Paint.skinDark : Paint.skin)
        polygon(in: c, points: [at(-5, -2), at(4, -2), at(5, -8), at(-6, -8)], fill: Paint.skinLight)
        for x in [CGFloat(-4), 1, 6] {
            polygon(in: c, points: [at(x, -12), at(x + 2, -12), at(x + 2, -18), at(x, -18)], fill: Paint.skinDark)
        }
    }

    private static func drawTorso(in c: CGContext, rig: Rig) {
        let side = rig.side
        let width: CGFloat = side ? 0.64 : 1
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { rig.body(x * width, y) }
        func shape(_ pairs: [(CGFloat, CGFloat)], _ fill: CGColor) {
            polygon(in: c, points: pairs.map { at($0.0, $0.1) }, fill: fill)
        }
        shape([(-13,193),(-13,217),(13,217),(13,193)], Paint.outline)
        shape([(-10,196),(-10,217),(10,217),(10,196)], Paint.skinDark)
        shape([(-8,197),(-8,216),(8,216),(8,197)], Paint.skin)
        shape([(-29,103),(-36,112),(-39,162),(-35,188),(-20,199),(20,199),
               (35,188),(39,162),(36,112),(29,103)], Paint.outline)
        shape([(-26,108),(-31,115),(-34,161),(-31,184),(-18,194),(18,194),
               (31,184),(34,161),(31,115),(26,108)], Paint.green)
        shape([(-31,117),(-34,160),(-29,183),(-22,183),(-25,153),(-22,117)], Paint.greenDark)
        shape([(22,115),(27,159),(24,183),(30,181),(34,161),(31,115)], Paint.greenDeep)
        shape([(-20,117),(-23,151),(-20,181),(-13,184),(-16,151),(-13,117)], Paint.greenLight)
        shape([(-25,109),(25,109),(29,115),(-29,115)], Paint.greenDark)
        if rig.pose.facing == .back {
            shape([(-23,191),(-20,175),(-10,164),(10,164),(21,175),(23,191),
                   (13,199),(-13,199)], Paint.greenDark)
            shape([(-17,190),(-14,178),(-7,170),(7,170),(15,179),(17,190),
                   (9,194),(-9,194)], Paint.greenLight)
            shape([(-3,174),(-3,190),(2,190),(2,174)], Paint.green)
            shape([(-13,135),(14,135),(14,139),(-13,139)], Paint.greenDark)
        } else {
            shape([(-15,194),(-8,184),(8,184),(15,194)], Paint.greenDeep)
            shape([(-10,193),(-6,188),(6,188),(10,193)], Paint.skin)
            shape([(-3,120),(-3,179),(1,179),(1,120)], Paint.greenDark)
            shape([(-22,137),(-14,143),(-5,143),(-5,139),(-13,139),(-20,133)], Paint.greenDark)
            shape([(5,143),(15,143),(23,137),(21,133),(13,139),(5,139)], Paint.greenDark)
            shape([(-9,181),(-9,170),(-6,170),(-6,181)], Paint.shoeLight)
            shape([(6,181),(6,170),(9,170),(9,181)], Paint.shoeLight)
        }
    }

    private static func drawHead(in c: CGContext, rig: Rig) {
        func shape(_ points: [(CGFloat, CGFloat)], _ fill: CGColor) {
            polygon(in: c, points: points.map { rig.head($0.0, $0.1) }, fill: fill)
        }
        let side = rig.side
        let direction: CGFloat = rig.pose.facing == .left ? -1 : 1
        func profile(_ points: [(CGFloat, CGFloat)], _ fill: CGColor) {
            shape(points.map { ($0.0 * direction, $0.1) }, fill)
        }
        if side {
            profile([(-20,-23),(-25,-8),(-25,17),(-18,29),(-7,35),(12,32),
                     (23,18),(23,1),(30,-7),(23,-11),(21,-25),(10,-31),(-8,-30)], Paint.outline)
            profile([(-15,-19),(-20,-7),(-20,15),(-13,25),(-4,29),(11,26),
                     (19,15),(18,-2),(24,-7),(18,-10),(17,-22),(9,-26),(-6,-25)], Paint.skin)
            profile([(12,-11),(18,-11),(17,-22),(9,-26),(-6,-25),(-10,-20),
                     (4,-21),(11,-18)], Paint.skinDark)
            profile([(-20,-21),(-25,-6),(-25,18),(-18,29),(-7,35),(12,32),
                     (22,20),(21,11),(13,14),(10,21),(2,20),(-2,10),(-6,4),
                     (-8,-11),(-12,-11),(-13,-23)], Paint.hairDark)
            profile([(-19,-6),(-19,17),(-13,25),(-3,29),(9,27),(15,22),(7,23),
                     (-3,17),(-8,6),(-12,-8)], Paint.hair)
            profile([(-13,12),(-12,21),(-3,27),(6,26),(5,22),(-4,18),(-8,9)], Paint.hairLight)
            profile([(-10,-8),(-10,0),(-4,3),(2,0),(2,-9),(-3,-13)], Paint.skinDark)
            profile([(-7,-7),(-7,-1),(-3,0),(-1,-2),(-2,-8)], Paint.skinLight)
            face(in: c, rig: rig, profileDirection: direction)
            return
        }
        shape([(-32,-5),(-32,-17),(-25,-20),(-22,-7)], Paint.skinDark)
        shape([(23,-7),(24,-20),(31,-17),(32,-5)], Paint.skinDark)
        shape([(-29,-7),(-29,-14),(-25,-15),(-24,-7)], Paint.skin)
        shape([(25,-7),(26,-15),(29,-13),(29,-7)], Paint.skinLight)
        shape([(-25,-22),(-30,-8),(-29,16),(-21,29),(-10,35),(11,35),
               (23,27),(30,14),(29,-10),(23,-24),(10,-30),(-11,-30)], Paint.outline)
        if rig.pose.facing == .back {
            shape([(-21,-20),(-26,-7),(-25,14),(-18,25),(-8,31),(10,31),
                   (20,24),(26,12),(25,-9),(20,-21),(9,-26),(-9,-26)], Paint.hairDark)
            shape([(-19,-13),(-22,3),(-18,18),(-6,27),(8,27),(18,20),
                   (22,8),(20,-13),(10,-21),(-8,-21)], Paint.hair)
            shape([(-16,5),(-12,18),(-3,24),(6,24),(8,19),(-2,16),(-7,8)], Paint.hairLight)
            shape([(6,10),(10,20),(17,15),(19,3),(13,-8),(9,-7),(12,5)], Paint.hairDark)
            shape([(-16,-8),(-8,-16),(1,-18),(1,-22),(-11,-20),(-19,-14)], Paint.hairDark)
            shape([(-9,-1),(-3,6),(3,6),(2,1),(-3,-3),(-5,-10),(-10,-11)], Paint.hairLight)
            return // Rear hair never draws eyes, brows or a mouth.
        }
        shape([(-21,-19),(-26,-6),(-25,13),(-18,24),(-8,29),(10,29),
               (19,22),(25,12),(25,-7),(19,-20),(9,-26),(-9,-26)], Paint.skin)
        shape([(-18,-15),(-23,-5),(-23,7),(-17,4),(-16,-13),(-7,-22),(-9,-26)], Paint.skinDark)
        shape([(-8,-23),(10,-23),(18,-17),(20,-6),(15,-10),(12,-18),(1,-21)], Paint.skinLight)
        shape([(-29,8),(-29,18),(-21,29),(-10,35),(11,35),(23,27),(30,14),
               (26,3),(18,7),(15,17),(8,16),(4,8),(-3,11),(-6,20),(-14,17),
               (-19,7),(-24,4),(-24,-8),(-28,-10)], Paint.hairDark)
        shape([(-24,16),(-18,25),(-7,31),(10,31),(20,24),(24,16),(17,17),
               (14,23),(6,22),(0,17),(-4,23),(-13,21),(-19,15)], Paint.hair)
        shape([(-13,24),(-6,28),(7,28),(11,25),(3,25),(-2,21),(-5,25)], Paint.hairLight)
        face(in: c, rig: rig, profileDirection: nil)
    }

    private static func face(in c: CGContext, rig: Rig, profileDirection direction: CGFloat?) {
        let eyeOpen = bounded(rig.pose.face.eyes, within: 0...1, fallback: 1)
        let brows = bounded(rig.pose.face.brows, within: -1...1, fallback: 0)
        let mouth = bounded(rig.pose.face.mouth, within: -1...1, fallback: 0)
        let mouthOpen = bounded(rig.pose.face.mouthOpen, within: 0...1, fallback: 0)
        func shape(_ points: [(CGFloat, CGFloat)], _ fill: CGColor) {
            polygon(in: c, points: points.map { rig.head($0.0, $0.1) }, fill: fill)
        }
        func line(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), _ width: CGFloat, _ fill: CGColor) {
            segment(in: c, from: rig.head(a.0, a.1), to: rig.head(b.0, b.1), width: width,
                    fill: fill, light: nil, dark: nil, outlined: false)
        }
        let eyeHeight = max(2, (8 * eyeOpen).rounded())
        let centers: [CGFloat] = direction.map { [$0 * 14] } ?? [-12, 12]
        for x in centers {
            let w: CGFloat = direction == nil ? 9 : 7
            shape([(x-w/2,-eyeHeight/2),(x+w/2,-eyeHeight/2),
                   (x+w/2,eyeHeight/2),(x-w/2,eyeHeight/2)], Paint.eye)
            if eyeOpen > 0.6 {
                shape([(x-w/2,1),(x-w/2+3,1),(x-w/2+3,4),(x-w/2,4)], Paint.eyeWhite)
            }
            let slope = brows * (x < 0 ? -4 : 4)
            line((x-w/2,10+brows*3+slope/2), (x+w/2,10+brows*3-slope/2), 3, Paint.hairDark)
        }
        if let direction {
            line((direction*19,-9),(direction*23,-8),3,Paint.skinDark)
            let x = direction * 17
            if mouthOpen > 0.1 {
                let h = 3 + mouthOpen * 9
                shape([(x-3,-17-h/2),(x+3,-17-h/2),(x+3,-17+h/2),(x-3,-17+h/2)],Paint.mouth)
            } else {
                line((x-direction*3,-18-mouth*2),(x+direction*3,-18+mouth*2),3,Paint.mouth)
            }
        } else {
            shape([(-2,-6),(-3,-11),(3,-11),(4,-8),(1,-9)],Paint.skinDark)
            if mouthOpen > 0.1 {
                let h = 3 + mouthOpen * 10
                shape([(-7,-18-h/2),(7,-18-h/2),(9,-17),(6,-18+h/2),
                       (-6,-18+h/2),(-9,-17)],Paint.mouth)
                if mouthOpen > 0.5 { line((-4,-20-h/4),(4,-20-h/4),3,Paint.tongue) }
            } else {
                line((-8,-17),(0,-17-mouth*5),3,Paint.mouth)
                line((0,-17-mouth*5),(8,-17),3,Paint.mouth)
            }
        }
    }

    private static func segment(in c: CGContext, from a: CGPoint, to b: CGPoint, width: CGFloat,
                                fill: CGColor, light: CGColor?, dark: CGColor?, outlined: Bool = true) {
        let dx = b.x-a.x, dy = b.y-a.y, distance = max(0.001,hypot(dx,dy))
        let u = CGPoint(x:dx/distance,y:dy/distance), n = CGPoint(x:-u.y,y:u.x)
        func hull(_ radius: CGFloat, inset: CGFloat = 0) -> [CGPoint] {
            let cap = radius*0.42
            let start = CGPoint(x:a.x+u.x*inset,y:a.y+u.y*inset)
            let end = CGPoint(x:b.x-u.x*inset,y:b.y-u.y*inset)
            return [CGPoint(x:start.x-u.x*cap+n.x*radius*0.55,y:start.y-u.y*cap+n.y*radius*0.55),
                CGPoint(x:start.x+n.x*radius,y:start.y+n.y*radius),
                CGPoint(x:end.x+n.x*radius,y:end.y+n.y*radius),
                CGPoint(x:end.x+u.x*cap+n.x*radius*0.55,y:end.y+u.y*cap+n.y*radius*0.55),
                CGPoint(x:end.x+u.x*cap-n.x*radius*0.55,y:end.y+u.y*cap-n.y*radius*0.55),
                CGPoint(x:end.x-n.x*radius,y:end.y-n.y*radius),
                CGPoint(x:start.x-n.x*radius,y:start.y-n.y*radius),
                CGPoint(x:start.x-u.x*cap-n.x*radius*0.55,y:start.y-u.y*cap-n.y*radius*0.55)]
        }
        if outlined { polygon(in:c,points:hull(width/2),fill:Paint.outline) }
        polygon(in:c,points:hull(max(1,width/2-(outlined ? 3:0)),inset:outlined ? 1:0),fill:fill)
        func stripe(_ offset: CGFloat, _ paint: CGColor) {
            let q = width*0.12
            polygon(in:c,points:[CGPoint(x:a.x+n.x*(offset-q)+u.x*4,y:a.y+n.y*(offset-q)+u.y*4),
                CGPoint(x:b.x+n.x*(offset-q)-u.x*4,y:b.y+n.y*(offset-q)-u.y*4),
                CGPoint(x:b.x+n.x*(offset+q)-u.x*4,y:b.y+n.y*(offset+q)-u.y*4),
                CGPoint(x:a.x+n.x*(offset+q)+u.x*4,y:a.y+n.y*(offset+q)+u.y*4)],fill:paint)
        }
        if let light { stripe(width*0.18,light) }
        if let dark { stripe(-width*0.22,dark) }
    }

    private static func ellipse(in c: CGContext, center: CGPoint, width: CGFloat, height: CGFloat, fill: CGColor) {
        polygon(in:c,points:(0..<16).map { index in
            let angle = CGFloat(index) * .pi / 8
            return CGPoint(x:center.x+cos(angle)*width/2,y:center.y+sin(angle)*height/2)
        },fill:fill)
    }

    private static func polygon(in c: CGContext, points: [CGPoint], fill: CGColor) {
        guard points.count >= 3 else { return }
        c.beginPath()
        // Three scene-unit pixels retain the room's coarse 16-bit art language
        // even for continuously changing joint angles; no bitmap cache grows.
        c.addLines(between:points.map { CGPoint(x:($0.x/3).rounded()*3,y:($0.y/3).rounded()*3) })
        c.closePath(); c.setFillColor(fill); c.fillPath()
    }

    private static func rectangle(in c: CGContext, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, fill: CGColor) {
        polygon(in:c,points:[CGPoint(x:x,y:y),CGPoint(x:x+width,y:y),
            CGPoint(x:x+width,y:y+height),CGPoint(x:x,y:y+height)],fill:fill)
    }

    private static func radians(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }
    private static func safeAngle(_ pose: AgentPose, _ joint: AgentJoint) -> CGFloat {
        bounded(pose.angle(joint),within:joint.limits,fallback:0)
    }
    private static func bounded(_ value: Double, within limits: ClosedRange<Double>, fallback: Double) -> CGFloat {
        CGFloat(value.isFinite ? max(limits.lowerBound,min(limits.upperBound,value)):fallback)
    }
    private static func rotated(_ point: CGPoint, by angle: CGFloat) -> CGPoint {
        CGPoint(x:point.x*cos(angle)+point.y*sin(angle),y:-point.x*sin(angle)+point.y*cos(angle))
    }
    private static func offset(_ point: CGPoint, length: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(x:point.x+sin(angle)*length,y:point.y-cos(angle)*length)
    }
    private static func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(red:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,
            blue:CGFloat(hex&255)/255,alpha:alpha)
    }
}
