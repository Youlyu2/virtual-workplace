import AppKit
import ImageIO
import Darwin

/// Small static images only: no live app, model calls, user state or soak loop.
@main enum AgentPuppetRenderingTests {
    private static var checks = 0
    private static let width = 480, height = 440
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1; precondition(condition(), "FAIL: \(message)")
    }
    private static func context(width: Int = width, height: Int = height) -> CGContext {
        CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
            space:CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
    private static func pose(_ facing: AgentFacing = .front, joints: [AgentJoint: Double] = [:],
                             face: AgentFace = AgentFace()) -> AgentPose {
        var result = AgentPose(); result.facing = facing; result.face = face
        result.joints = Dictionary(uniqueKeysWithValues:joints.map { ($0.key.rawValue,$0.value) })
        return result
    }
    private static func render(_ pose: AgentPose, scale: CGFloat = 1) -> CGContext {
        let c = context()
        c.translateBy(x:240-835,y:55-270)
        PixelAgentPuppet.draw(in:c,pose:pose,scale:scale)
        return c
    }
    private static func same(_ a: CGContext, _ b: CGContext) -> Bool {
        memcmp(a.data!,b.data!,a.bytesPerRow*a.height)==0
    }
    private static func bounds(_ c: CGContext, minimumAlpha: UInt8 = 220) -> CGRect? {
        let bytes = c.data!.assumingMemoryBound(to:UInt8.self)
        var minX=c.width,maxX = -1,minY=c.height,maxY = -1
        for row in 0..<c.height {
            for x in 0..<c.width where bytes[row*c.bytesPerRow+x*4+3] >= minimumAlpha {
                let y=c.height-1-row
                minX=min(minX,x);maxX=max(maxX,x);minY=min(minY,y);maxY=max(maxY,y)
            }
        }
        guard maxX>=minX,maxY>=minY else { return nil }
        return CGRect(x:minX,y:minY,width:maxX-minX+1,height:maxY-minY+1)
    }
    private static func save(_ c: CGContext, to url: URL) throws {
        let destination=CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil)!
        CGImageDestinationAddImage(destination,c.makeImage()!,nil)
        precondition(CGImageDestinationFinalize(destination))
    }
    private static func contactSheet() throws {
        let cards:[(String,AgentPose)]=[
            ("FRONT",pose(.front)),("BACK",pose(.back)),("LEFT",pose(.left)),("RIGHT",pose(.right)),
            ("INDEPENDENT ARMS",pose(.front,joints:[.leftShoulder:-128,.leftElbow:38,.rightShoulder:41,.rightElbow:73],
                face:AgentFace(eyes:1,brows:0.55,mouth:0.8,mouthOpen:0))),
            ("BENT LEGS / WRISTS",pose(.front,joints:[.leftShoulder:-37,.leftElbow:64,.leftWrist:37,
                .rightShoulder:68,.rightElbow:42,.rightWrist:-48,.leftHip:-33,.leftKnee:64,.rightHip:24,.rightKnee:-17],
                face:AgentFace(eyes:0.7,brows:-0.65,mouth:-0.65,mouthOpen:0))),
            ("HEAD + TORSO",pose(.back,joints:[.torsoLean:-16,.headTilt:24,.leftShoulder:-28,.leftElbow:-54,
                .rightShoulder:42,.rightElbow:87])),
            ("PROFILE EXPRESSION",pose(.right,joints:[.headTilt:-15,.leftShoulder:-23,.rightShoulder:100,
                .rightElbow:52,.rightWrist:-19],face:AgentFace(eyes:0.4,brows:0.7,mouth:0,mouthOpen:0.8)))
        ]
        let c=context(width:1440,height:760)
        c.setFillColor(NSColor(srgbRed:0.96,green:0.91,blue:0.8,alpha:1).cgColor)
        c.fill(CGRect(x:0,y:0,width:1440,height:760))
        for (index,card) in cards.enumerated() {
            let column=index%4,row=1-index/4
            let origin=CGPoint(x:column*360,y:row*380)
            c.setFillColor(NSColor(srgbRed:0.91,green:0.84,blue:0.69,alpha:1).cgColor)
            c.fill(CGRect(x:origin.x+10,y:origin.y+15,width:340,height:350))
            c.saveGState();c.translateBy(x:origin.x+180-835,y:origin.y+52-270)
            PixelAgentPuppet.draw(in:c,pose:card.1)
            c.restoreGState()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current=NSGraphicsContext(cgContext:c,flipped:false)
            let paragraph=NSMutableParagraphStyle();paragraph.alignment = .center
            (card.0 as NSString).draw(in:CGRect(x:origin.x+10,y:origin.y+337,width:340,height:22),
                withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:13,weight:.semibold),
                    .foregroundColor:NSColor(srgbRed:0.25,green:0.22,blue:0.18,alpha:1),.paragraphStyle:paragraph])
            NSGraphicsContext.restoreGraphicsState()
        }
        let directory=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("build/agent-puppet-review")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try save(c,to:directory.appendingPathComponent("contact-sheet.png"))
        print("PREVIEW: \(directory.appendingPathComponent("contact-sheet.png").path)")
    }

    static func main() throws {
        _=NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
        let neutral=render(pose())
        expect(bounds(neutral) != nil,"the procedural human has visible opaque pixels")
        expect(abs(bounds(neutral)!.minY-55)<=3,"the neutral soles meet the supplied floor anchor")
        let facingImages=AgentFacing.allCases.map { render(pose($0)) }
        for a in facingImages.indices {
            for b in facingImages.indices where b>a {
                expect(!same(facingImages[a],facingImages[b]),"each authored direction has a distinct head/body projection")
            }
        }
        for joint in AgentJoint.allCases {
            let changed=pose(joints:[joint:27])
            expect(!same(neutral,render(changed)),"\(joint.rawValue) independently changes visible limb/head geometry")
        }
        let strongFace=AgentFace(eyes:0.15,brows:0.8,mouth:0.8,mouthOpen:0.85)
        for facing in [AgentFacing.front,.left,.right] {
            expect(!same(render(pose(facing)),render(pose(facing,face:strongFace))),
                "continuous facial parameters are visible from \(facing)")
        }
        expect(same(render(pose(.back)),render(pose(.back,face:strongFace))),
            "a rear-facing head never paints eyes or mouth on the back of the hair")
        let arbitrary=pose(joints:[.leftShoulder:-73.8,.leftElbow:112.2,.leftWrist:-38.7,
            .rightShoulder:31.4,.rightElbow:-44.5,.rightWrist:66.2,.leftHip:-35.5,.leftKnee:88.1,
            .rightHip:22.2,.rightKnee:-16.4,.torsoLean:17.1,.headTilt:-21.2])
        try arbitrary.validate()
        expect(!same(neutral,render(arbitrary)),"a non-preset pose is accepted and rendered")
        expect(abs(bounds(render(arbitrary))!.minY-55)<=3,"bent legs keep the lowest sole on the floor")
        expect(same(render(arbitrary),render(arbitrary)),"rendering is deterministic without host-local animation or RNG")
        for facing in AgentFacing.allCases {
            for sign in [-1.0,1.0] {
                var extreme=pose(facing)
                for joint in AgentJoint.allCases { extreme.joints[joint.rawValue]=sign<0 ? joint.limits.lowerBound:joint.limits.upperBound }
                let image=render(extreme)
                let box=bounds(image)!
                expect(box.minX>0 && box.maxX<CGFloat(width) && box.minY>0 && box.maxY<CGFloat(height),
                    "extreme legal joints remain finite and inside the review image")
            }
        }
        var invalid=pose();invalid.x = .nan
        expect(bounds(render(invalid))==nil,"invalid root coordinates draw no geometry")
        expect(bounds(render(pose(),scale:.infinity))==nil,"invalid scale cannot create unbounded surfaces")
        var invalidAngle=pose();invalidAngle.joints[AgentJoint.leftElbow.rawValue] = .infinity
        expect(same(neutral,render(invalidAngle)),"a defensive invalid angle resolves to its neutral value")
        try contactSheet()
        print("PASS: \(checks) continuous pixel human joint, expression, projection and finite-render checks")
    }
}
