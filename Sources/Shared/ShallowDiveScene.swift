import AppKit

/// The shallow reef uses the same snapshots as the cabin, with floating
/// characters and a submarine for each live session.
enum ShallowDiveScene {
    // Oversized heads and compact neoprene bodies give the diver a cartoon silhouette.
    private static let diverFace = [
        ".........OOOOO..........",
        "......OOOHHHHHOO........",
        "....OOHLLHHHHLHHOO......",
        "...OHLLLLHHHLLHHHHO.....",
        "..OHLLHHHHHHHHHHHHHO....",
        "..OHHHHHHAAAHHHHHAAO....",
        ".OHHHHAAAPPPAHHHAAAO....",
        ".OAAAPPFPPPPPPAAPAAO....",
        "OPOAPPPPPPPPPPPPPPOPO...",
        "OPOODDDDDDDDDDDDDDOPO...",
        ".OODMJJJJJJJJJJJMDOO....",
        "..ODJJJkJJJJJkJJJDO.....",
        "..ODJJJkJJJJJkJJJDO.....",
        "...ODJJJJJDJJJJJDO......",
        "....ODDDDPPPDDDDO.......",
        "....OPPPPPPPPPPPO.......",
        "......OPPPFFPPO.........",
        ".........OOO............",
        "........................"
    ]
    private static let diverSideFace = [
        ".......OOOOOO...........",
        ".....OOHHHHHHOOO........",
        "....OHLLLHHHHHHOOO......",
        "...OHLLHHHHHHHLHHOO.....",
        "...OHHHHHAAAHHHHHHHO....",
        "..OHHHHAAAPPAHHHHAAO....",
        "..OHHAAAPPPPPAHHAAAO....",
        "..OAAAPPFPPPPPPPPPOO....",
        "..OAPOPPPPPPPPPPPPPO....",
        "..OAPODDDDDDDDDDDDDO...",
        "...OPODMJJJJJJJJJMDO...",
        "...OOODJJkJJJJJJJDOO...",
        "....OODJJkJJJJJJJDOO...",
        ".....ODJJJJJJJDJPDO....",
        "......ODDDDDDDPDPOO....",
        ".......OPPPPPFPPO......",
        ".........OPPPPO.........",
        "...........OOO.........."
    ]
    private static let diverPonytail = [
        "...OOO.....", "..OTTOO....", "..OHHHOO...", ".OHLHHHHO..",
        ".OHHHHHAO..", ".OHHHAAAO..", "OHLHHAAO...", "OHLLHAAO...",
        "OHHHAAO....", ".OHHAAO....", "..OAAO.....", "...OO......"
    ]
    private static let wetsuitFront = [
        "....OOOOOOOOO....",
        "..OOTTSSSSTTOO...",
        ".OTTTSSUUSSTTTO..",
        ".OTTSNSUUSNSTTO..",
        ".OSSNSNUUNSNSO...",
        "..OSSSSUUSSSSO...",
        "..OSSSSUUSSSSO...",
        "..OSNNNUUNNSSO...",
        "..OSNSSUUSNSSO...",
        "..ONTTCWCTTNNO...",
        "...ONNSSSSNNO....",
        "...ONNSSSSNNO....",
        "....OOOOOOOO....."
    ]
    private static let wetsuitSide = [
        ".....OOOOOOOOOO.......",
        "...OONNTTNNNSSSOO.....",
        "..ONNSSTTSSSUUSSOO....",
        ".ONNSSSTTSSSUUUSTOO...",
        ".ONNSSSTTSSSUUUSTTOO..",
        "ONNNSSSTTSSSUUUSTTOO..",
        "ONNNSSCCSSSSUUUSTTO...",
        "ONNNNNNNNNSSSSSTTO....",
        ".ONNNNNNNNNSSSSOO.....",
        "..OOOOOOOOOOOOO......."
    ]
    private static let silverTank = [
        "....OOO...", "...OMMO...", "..OOGOOO..", ".OOWWWGOO.", ".OWWWWGGO.",
        "OWWWMMGGGO", "OWWWMMGGGO", "OOOOMMOOOO", "OWWWMMGGGO", "OWWWMMGGGO",
        "OWWWMMGGGO", "OWWWMMGGGO", "OOOOMMOOOO", ".OWWMMGGO.", ".OOWMMGOO.", "..OOOOOO.."
    ]
    private static let suitSleeve = [
        "..OOOO..", ".OTTTTO.", ".OTTTTO.", ".OSSUSO.", ".OSSUSO.", ".OSSUSO.",
        ".ONSSNO.", ".ONSSNO.", ".OTTTTO.", ".ONSSNO.", "ONSUSNOO", "ONSUSNSO",
        "ONSUSNOO", ".ONNNOO.", "..OOO..."
    ]
    // The trouser leg, ankle and blade share a single hip pivot.
    private static let finnedLeg = [
        "...OOOOO...", "..ONUSSO...", "..ONUSSO...", "..ONUSSO...",
        "..ONUSSO...", "..ONSSSO...", "..ONSSO....", "..OTTTO....",
        "..ONSSO....", "..OSUSNO...", ".OSUUSNNO..", ".OSUUSNNO..",
        "OSUUSUNNNO.", "OSUUSUNNNO.", "OTTCTTCTTO.", ".OOOOOOOO.."
    ]
    private static let diverColors: [Character: UInt32] = [
        "O": 0x163247, "H": 0x71414F, "L": 0xAD6370, "A": 0x4A293F,
        "P": 0xF2B284, "F": 0xDC8D6B, "G": 0x467481, "M": 0x9CB8BC,
        "J": 0xBBF2EC, "k": 0x27364B, "D": 0x263A44, "W": 0xE3F1E9,
        "N": 0x983F32, "S": 0xE96F32, "U": 0xFFA84F, "T": 0xF7BE67, "C": 0xFFE2A0
    ]
    private static let sealBody = [
        "......OOO.......OOO......",
        ".....OBBSO.....OSBBO.....",
        ".....OBBBOOOOOOOBBBO.....",
        "....OBBBHHHHBBBBBBBBO....",
        "...OBBHHHHBBBBBBBBBBBO...",
        "..OBBHHHBBBBBBBBBBBBBBO..",
        ".OBBBBBBBBBBBBBBBHBBBBBO.",
        ".OBBBBBBBBBBBBBBHHHBBBBO.",
        "OBBBBBBBBBBBBBBBBHBBSBBBO",
        "OBBBBBBBBBBBBBBBBBBSSBBBO",
        "OBBBBBBBBBBBBBBBBBBBSBBBO",
        "OBBBBBBBBBBBBBBBBBBBBBBBO",
        "OBBBBBBBBBBBBBBBBBBBBBBBO",
        "OBBCCBBBBBBBBBBBCCBBBBBBO",
        "OBCCCCCBBBBBBCCCCCCBBBBO.",
        ".OCCCCCCCCCCCCCCCCCCBBBO.",
        ".OCCCCCCCCCCCCCCCCCCCBBO.",
        "..OCCCCCCCCCCCCCCCCCCBO..",
        "...OCCCCCCCCCCCCCCCCBO...",
        "....OCCCCCCCCCCCCCCBO....",
        ".....OOCCCCCCCCCCBOO.....",
        ".......OOOOOOOOOOO......."
    ]
    private static let sealEye = [".KKK.", "KWKKK", "KWWKK", "KKKKK", ".KKK."]
    private static let sealFlipper = [
        "....OOO.", "..OOBBOO", ".OBHBBBO", "OBBBBBO.", ".OOOBO..", "...OO..."
    ]
    private static let sealTail = [
        "......OOOO...", "....OOBHBOO..", "...OBBBBBO...", ".OOBBSBOO....",
        "OBBBBBBOO....", ".OOBBSBBBO...", "...OOBBSBOO..", ".....OOOOO..."
    ]
    private static let sealMuzzle = [
        "......K....K......",
        "..................",
        ".K.............K..",
        ".K.....KK......K..",
        "..KKKKK..KKKKKK..."
    ]
    private static let sealColors: [Character: UInt32] = [
        "O": 0x39596F, "B": 0x9BC4D8, "S": 0x689AB8, "H": 0xD9F0F6,
        "C": 0xF5EDE1, "K": 0x24384A, "W": 0xFFFFFF
    ]
    private static let clownfish = [
        "...OOO........O.", "..OWAAOO..O..OAO", ".OAAWAWWOOAOOAAO",
        "OKAAWAWWAAOOOOAO", ".OAAWAWWOOA..OAO", "..OWAAOO......O.", "...OOO.........."
    ]
    private static let blueTang = [
        "....OOOOO........", "..OOBBKBOOO....YY", ".OBBKKKKBBBO..YYY",
        "OKBBBBKKBBBBYYYYY", ".OBBHBBBBBBO..YYY", "..OOBBBBBOO....YY", "....OOOOO........"
    ]
    private static let butterflyfish = [
        ".......OOO......", ".....OOYYOO.....", "...OOWYYYYOO...Y",
        "OOWKWWYYYYYYOYYY", ".OWKWWYYYYOO...Y", "...OOYYYYOO.....", ".....OOOO......."
    ]
    private static let fishColors: [Character: UInt32] = [
        "O": 0x23576D, "K": 0x142F47, "A": 0xF28043, "W": 0xF9EED0,
        "B": 0x3D78CF, "H": 0x7FB7F3, "Y": 0xF9D46B
    ]

    static func drawReefFish(in c: CGContext, phase: Double) {
        // Blue tang cross open water. Clownfish stay close to their corner
        // of the reef and butterflyfish travel in small, loose groups.
        for i in 0..<8 {
            let track = WorldAtmosphere.positiveRemainder(phase * 31 + Double(i * 38 + 940), 1840)
            let y = 695 + Double(i % 4) * 25 + sin(phase * 0.7 + Double(i) * 0.8) * 15
            pixelSprite(c, rows: blueTang, colors: fishColors, x: track - 70, y: y, unit: -2.4, alpha: 0.8)
        }
        for i in 0..<4 {
            let angle = phase * 0.34 + Double(i) * 0.55
            let x = 315 + cos(angle) * 76 + Double(i) * 24
            let y = 280 + Double(i % 2) * 29 + sin(angle) * 22
            pixelSprite(c, rows: clownfish, colors: fishColors, x: x, y: y,
                        unit: sin(angle) > 0 ? 2.7 : -2.7, alpha: 0.92)
        }
        for i in 0..<5 {
            let track = WorldAtmosphere.positiveRemainder(phase * 23 + Double(i * 45 + 470), 1840)
            let y = 525 + Double(i % 3) * 30 + sin(phase * 0.7 + Double(i)) * 11
            pixelSprite(c, rows: butterflyfish, colors: fishColors, x: 1740 - track, y: y, unit: 2.5, alpha: 0.85)
        }
    }

    static func submarineSlots(for tasks: [WorkplaceTask]) -> [Int] {
        Set(0..<3).union(tasks.map(\.slot).filter { (3..<6).contains($0) }).sorted()
    }

    static func draw(in c: CGContext, bounds: CGRect, snapshot: SceneSnapshot, world: SceneWorld,
                     at date: Date, reduceMotion: Bool, animationOffset: TimeInterval = 0, pendingAlert: Bool = false) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        UnderwaterWorkplaceScene.draw(in: c, bounds: bounds, deep: false, world: world,
                                      at: date, reduceMotion: reduceMotion, animationOffset: animationOffset)
        c.saveGState()
        c.clip(to: bounds)
        // Fit three submarines across even when the full-bleed reef is cropped.
        let scale = min(bounds.width / 1070, bounds.height / 810)
        c.translateBy(x: bounds.minX, y: bounds.minY)
        c.scaleBy(x: scale, y: scale)
        let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        let clock = date.timeIntervalSinceReferenceDate
        let time = !reduceMotion && clock.isFinite ? clock + animationOffset : 0
        let slots = submarineSlots(for: snapshot.tasks)
        let columns = 3
        let count = slots.count
        let rows = (count + columns - 1) / columns
        let action = snapshot.action.flatMap { $0.isActive(at: date) ? $0 : nil }
        let progress = action.map { reduceMotion ? 0.5 : $0.progress(at: date) } ?? 0
        let swimmerY = min(size.height * 0.45, size.height - 224 - CGFloat(rows - 1) * 155 - 104)
        drawCompanions(in: c, center: CGPoint(x: size.width / 2, y: swimmerY),
                       mode: snapshot.mode, action: action?.kind, progress: progress,
                       time: time, reduceMotion: reduceMotion)

        for index in 0..<count {
            let row = index / columns
            let inRow = min(columns, count - row * columns)
            let column = index % columns
            let stagger: CGFloat = column.isMultiple(of: 2) ? 0 : 16
            let x = size.width / 2 + (CGFloat(column) - CGFloat(inRow - 1) / 2) * 276
            let y = size.height - 158 - CGFloat(row) * 155 + stagger + sin(time * 0.9 + Double(index)) * 5
            let slot = slots[index]
            let task = snapshot.tasks.first { $0.slot == slot }
            taskSubmarine(in: c, center: CGPoint(x: x, y: y), slot: slot, task: task, fresh: snapshot.isFresh(at: date))
        }
        clockReadout(in: c, size: size, world: world, at: date)
        UnderwaterWorkplaceScene.badge(in: c, bounds: CGRect(origin: .zero, size: size), deep: false, world: world, pendingAlert: pendingAlert)
        c.restoreGState()
    }

    private static func clockReadout(in c: CGContext, size: CGSize, world: SceneWorld, at date: Date) {
        let clock = CGRect(x: size.width - 124, y: size.height - 120, width: 104, height: 104)
        let darkInk = UnderwaterWorkplaceScene.shallowTextIsDark(behind: clock, in: size, world: world, at: date)
        let ink: UInt32 = darkInk ? 0x092C3A : 0xF4FFFD
        let halo: UInt32 = darkInk ? 0xE9FFFA : 0x153748
        c.saveGState()
        c.setShouldAntialias(true)
        c.setStrokeColor(WorldAtmosphere.color(0x16647C, alpha: 0.55).cgColor)
        c.setLineWidth(3)
        c.strokeEllipse(in: clock)
        c.setStrokeColor(WorldAtmosphere.color(0xD6FFF7, alpha: 0.92).cgColor)
        c.setLineWidth(1.8)
        c.strokeEllipse(in: clock.insetBy(dx: 1.5, dy: 1.5))
        c.setLineCap(.round)
        c.setLineWidth(2.5)
        c.beginPath()
        c.addArc(center: CGPoint(x: clock.midX, y: clock.midY), radius: clock.width / 2 - 7,
                 startAngle: .pi * 0.62, endAngle: .pi * 0.84, clockwise: false)
        c.strokePath()
        text(SceneReadouts.dateText(at: date), x: clock.midX - 46, y: clock.midY + 10,
             width: 92, size: 11, color: ink, weight: .medium, centered: true, halo: halo)
        text(SceneReadouts.timeText(at: date), x: clock.midX - 45, y: clock.midY - 24,
             width: 90, size: 25, color: ink, weight: .semibold, centered: true, halo: halo)
        c.restoreGState()
    }

    private static func taskSubmarine(in c: CGContext, center: CGPoint, slot: Int, task: WorkplaceTask?, fresh: Bool) {
        c.saveGState()
        c.translateBy(x: (center.x - 108).rounded(), y: center.y.rounded())
        c.setShouldAntialias(false)
        let outline: UInt32 = 0x3D525D

        // Propeller, tower and periscope sit behind the stepped steel hull.
        fill(c, CGRect(x: -11, y: -7, width: 31, height: 14), outline)
        fill(c, CGRect(x: -14, y: -23, width: 9, height: 46), outline)
        fill(c, CGRect(x: -11, y: -18, width: 4, height: 36), 0xA0AEB3)
        fill(c, CGRect(x: 66, y: 39, width: 53, height: 23), outline)
        fill(c, CGRect(x: 70, y: 43, width: 45, height: 15), 0xA3AEB3)
        fill(c, CGRect(x: 85, y: 60, width: 9, height: 16), outline)
        fill(c, CGRect(x: 85, y: 72, width: 18, height: 7), outline)
        fill(c, CGRect(x: 95, y: 74, width: 7, height: 3), 0xCDD7D8)

        let hull = CGMutablePath()
        hull.addLines(between: [
            CGPoint(x: 0, y: -19), CGPoint(x: 12, y: -19), CGPoint(x: 12, y: -33),
            CGPoint(x: 27, y: -33), CGPoint(x: 27, y: -48), CGPoint(x: 188, y: -48),
            CGPoint(x: 188, y: -41), CGPoint(x: 204, y: -41), CGPoint(x: 204, y: -30),
            CGPoint(x: 215, y: -30), CGPoint(x: 215, y: -17), CGPoint(x: 223, y: -17),
            CGPoint(x: 223, y: 20), CGPoint(x: 215, y: 20), CGPoint(x: 215, y: 34),
            CGPoint(x: 202, y: 34), CGPoint(x: 202, y: 43), CGPoint(x: 184, y: 43),
            CGPoint(x: 184, y: 48), CGPoint(x: 27, y: 48), CGPoint(x: 27, y: 34),
            CGPoint(x: 12, y: 34), CGPoint(x: 12, y: 20), CGPoint(x: 0, y: 20)
        ])
        hull.closeSubpath()
        c.saveGState()
        c.addPath(hull)
        c.clip()
        fill(c, CGRect(x: 0, y: -48, width: 223, height: 96), 0xC5CDD0)
        fill(c, CGRect(x: 0, y: -48, width: 223, height: 12), 0x829199)
        fill(c, CGRect(x: 21, y: 40, width: 182, height: 8), 0xE3E8E8)
        c.restoreGState()
        c.addPath(hull)
        c.setLineWidth(4)
        c.setStrokeColor(WorldAtmosphere.color(outline).cgColor)
        c.strokePath()
        fill(c, CGRect(x: 189, y: -11, width: 23, height: 23), outline)
        fill(c, CGRect(x: 192, y: -8, width: 17, height: 17), 0x7C9AA5)
        fill(c, CGRect(x: 194, y: 3, width: 9, height: 4), 0xDCEEF0)
        fill(c, CGRect(x: 22, y: 23, width: 6, height: 6), 0x627B85)

        let ink: UInt32 = 0x243C46
        let headline = task?.title ?? "等待任务"
        let status = task.map { fresh ? $0.activityTitle : "离线" } ?? "待机"
        let details = task?.executionDetails
        let tool = details?.toolName.map { "工具 · \($0)" }
        let detail = fresh ? (details?.latestUpdate ?? tool ?? task?.currentStep ?? task?.nextStep ?? task?.sourceLabel)
            : task.map { _ in "打开主应用后恢复同步" }
        let prefix = String(format: "%02d · ", slot + 1)
        text(prefix + status, x: 34, y: 17, width: 150, size: 12, color: ink, weight: .semibold)
        text(headline, x: 34, y: -24, width: 150, size: 14, color: ink, weight: .bold, lines: 2)
        let percentage = task?.progress.flatMap { value in
            fresh && value.isFinite ? Int(max(0, min(1, value)) * 100) : nil
        }
        if let detail {
            text(detail, x: 34, y: -34, width: percentage == nil ? 150 : 109, size: 11, color: ink)
        }
        if let percentage {
            text("\(percentage)%", x: 148, y: -34, width: 36, size: 11, color: ink, weight: .semibold)
        }
        c.restoreGState()
    }

    private static func drawCompanions(in c: CGContext, center: CGPoint, mode: EmployeeMode, action: EmployeeAction?,
                                       progress: Double, time: Double, reduceMotion: Bool) {
        let playing = action == .playWithCat
        let swimming = action == .walk || (mode == .standing && action == nil)
        let paddling = mode == .slacking && action == nil
        let turning = action == .stretch
        let side = swimming || playing || turning
        let arrival = playing ? min(1, min(progress, 1 - progress) * 4) : 0
        let approach = arrival * arrival * (3 - 2 * arrival)
        let swimPhase = action == .walk ? progress * 2 * .pi : time * 0.26
        let facingLeft = swimming && cos(swimPhase) < 0
        let travel = swimming && !reduceMotion ? sin(swimPhase) * 104 : 0
        let diver = CGPoint(x: center.x - 155 + approach * 173 + travel,
                            y: center.y + sin(time * (paddling ? 2.4 : 0.85)) * (paddling ? 12 : 6))
        let sealPhase = time * 0.49
        let sealTravel = reduceMotion ? 0 : sin(sealPhase) * 56 * (1 - approach)
        let seal = CGPoint(x: center.x + 227 - approach * 38 + sealTravel,
                           y: center.y - 41 + approach * 24 + sin(time * 1.15) * 12)
        let stroke = (swimming || paddling || playing) && !reduceMotion ? sin(time * 5) : 0
        drawDiver(in: c, center: diver, side: side, facingLeft: facingLeft, stroke: stroke,
                  paddling: paddling, turning: turning ? sin(progress * .pi) : 0, waving: action == .wave)

        let rollTime = playing ? (progress - 0.37) / 0.29
            : (WorldAtmosphere.positiveRemainder(time, 23) - 18) / 2.6
        let roll = reduceMotion ? 0 : max(0, min(1, rollTime))
        let rollAngle = roll * roll * (3 - 2 * roll) * 2 * .pi
        let faceRight = !reduceMotion && approach < 0.5 && cos(sealPhase) > 0
        let turnWidth = reduceMotion || approach >= 0.5 ? 1 : 0.72 + abs(cos(sealPhase)) * 0.28
        drawSeal(in: c, center: seal, facingRight: faceRight, turnWidth: turnWidth,
                 roll: rollAngle, stroke: reduceMotion ? 0 : sin(time * 4.1), nod: approach)

        if playing && approach > 0.75 {
            let contactX = (diver.x + 74 + seal.x - 53) / 2
            for i in 0..<4 {
                let drift = reduceMotion ? Double(i * 11) : WorldAtmosphere.positiveRemainder(time * 31 + Double(i * 21), 82)
                bubble(in: c, x: contactX + Double(i * 10) - 13, y: seal.y + 31 + drift,
                       diameter: Double(8 + i * 3))
            }
        }
        for i in 0..<(action == .coffee ? 6 : 3) {
            let rise = reduceMotion ? Double(i * 14 + 7) : WorldAtmosphere.positiveRemainder(time * 33 + Double(i * 25), 98)
            let mouthX = diver.x + (side ? (facingLeft ? -95 : 95) : 32)
            bubble(in: c, x: mouthX + 12 + sin(rise * 0.06) * 9,
                   y: diver.y + (side ? 13 : 37) + rise, diameter: Double(6 + i * 2))
        }
    }

    private static func drawSeal(in c: CGContext, center: CGPoint, facingRight: Bool, turnWidth: CGFloat,
                                 roll: CGFloat, stroke: CGFloat, nod: CGFloat) {
        c.saveGState()
        c.translateBy(x: center.x, y: center.y)
        c.rotate(by: roll + nod * 0.11 + stroke * 0.035)
        c.scaleBy(x: facingRight ? -turnWidth : turnWidth, y: 1)
        c.saveGState()
        c.translateBy(x: 45, y: -18)
        c.rotate(by: stroke * 0.27)
        pixelSprite(c, rows: sealTail, colors: sealColors, x: -3, y: 16, unit: 3.2, alpha: 1)
        c.restoreGState()
        c.saveGState()
        c.translateBy(x: -47, y: -25)
        c.rotate(by: -0.12 - stroke * 0.21)
        pixelSprite(c, rows: sealFlipper, colors: sealColors, x: -5, y: 8, unit: -3.4, alpha: 1)
        c.restoreGState()
        pixelSprite(c, rows: sealBody, colors: sealColors, x: -62, y: 53, unit: 5, alpha: 1)
        pixelSprite(c, rows: sealEye, colors: sealColors, x: -48, y: 13, unit: 2.7, alpha: 1)
        pixelSprite(c, rows: sealEye, colors: sealColors, x: 7, y: 12, unit: 2.7, alpha: 1)
        pixelSprite(c, rows: sealMuzzle, colors: sealColors, x: -49, y: -5, unit: 4, alpha: 1)
        c.saveGState()
        c.translateBy(x: 30, y: -36)
        c.rotate(by: 0.12 + stroke * 0.28)
        pixelSprite(c, rows: sealFlipper, colors: sealColors, x: -9, y: 9, unit: 3.8, alpha: 1)
        c.restoreGState()
        c.restoreGState()
    }

    private static func drawDiver(in c: CGContext, center: CGPoint, side: Bool, facingLeft: Bool,
                                  stroke: CGFloat, paddling: Bool, turning: CGFloat, waving: Bool) {
        c.saveGState()
        c.translateBy(x: center.x.rounded(), y: center.y.rounded())
        if facingLeft { c.scaleBy(x: -1, y: 1) }
        if side {
            c.rotate(by: turning * 0.76 + stroke * 0.055)
            diverPiece(in: c, silverTank, at: CGPoint(x: -23, y: 33), angle: -.pi / 2, unit: 4.4)
            drawDiverLimb(in: c, finnedLeg, at: CGPoint(x: -61, y: 6),
                         angle: -.pi / 2 - 0.12 + stroke * 0.18, unit: 3.8)
            drawDiverLimb(in: c, suitSleeve, at: CGPoint(x: 11, y: 0),
                       angle: .pi * 0.31 - stroke * 0.27, unit: 3.1)
            diverPiece(in: c, wetsuitSide, at: CGPoint(x: -21, y: -2), unit: 5)
            drawDiverLimb(in: c, finnedLeg, at: CGPoint(x: -61, y: -8),
                         angle: -.pi / 2 + 0.14 - stroke * 0.19, unit: 4.1)
            diverPiece(in: c, diverPonytail, at: CGPoint(x: 21, y: 33), angle: -.pi / 2.4, unit: 4.3)
            diverPiece(in: c, diverSideFace, at: CGPoint(x: 53, y: 9), angle: -.pi / 12, unit: 5.1)
            drawDiverLimb(in: c, suitSleeve, at: CGPoint(x: 15, y: -6),
                       angle: .pi * 0.38 + stroke * 0.24, unit: 3.7)
        } else {
            c.rotate(by: stroke * 0.05)
            diverPiece(in: c, silverTank, at: CGPoint(x: -35, y: -20), angle: -0.13, unit: 4.5)
            drawDiverLimb(in: c, finnedLeg, at: CGPoint(x: -13, y: -43),
                         angle: -0.14 + stroke * 0.16, unit: 3.8)
            drawDiverLimb(in: c, finnedLeg, at: CGPoint(x: 13, y: -43),
                         angle: 0.14 - stroke * 0.16, unit: 3.8)
            drawDiverLimb(in: c, suitSleeve, at: CGPoint(x: -25, y: -8),
                       angle: -0.35 - (paddling ? 0.49 + stroke * 0.40 : 0), unit: 3.4)
            drawDiverLimb(in: c, suitSleeve, at: CGPoint(x: 25, y: -8),
                       angle: waving ? 2.11 + stroke * 0.18 : 0.37 + (paddling ? 0.50 - stroke * 0.40 : 0),
                       unit: 3.6)
            diverPiece(in: c, wetsuitFront, at: CGPoint(x: 0, y: -23), unit: 4.6)
            diverPiece(in: c, diverPonytail, at: CGPoint(x: 48, y: 37), angle: 0.20 + stroke * 0.08, unit: 4.6)
            diverPiece(in: c, diverFace, at: CGPoint(x: 2, y: 42), unit: 5.1)
        }
        c.restoreGState()
    }

    // Rotate at the top of each limb so the shoulder or hip stays fixed.
    private static func drawDiverLimb(in c: CGContext, _ rows: [String], at pivot: CGPoint,
                                      angle: CGFloat, unit: CGFloat) {
        c.saveGState()
        c.translateBy(x: pivot.x, y: pivot.y)
        c.rotate(by: angle)
        let width = CGFloat(rows[0].count) * unit
        pixelSprite(c, rows: rows, colors: diverColors, x: -width / 2, y: unit, unit: unit, alpha: 1)
        c.restoreGState()
    }

    private static func diverPiece(in c: CGContext, _ rows: [String], at center: CGPoint,
                                   angle: CGFloat = 0, unit: CGFloat) {
        let columns = rows[0].count
        c.saveGState()
        c.translateBy(x: center.x, y: center.y)
        c.rotate(by: angle)
        pixelSprite(c, rows: rows, colors: diverColors, x: -CGFloat(columns) * unit / 2,
                    y: CGFloat(rows.count - 1) * unit / 2, unit: unit, alpha: 1)
        c.restoreGState()
    }

    private static func bubble(in c: CGContext, x: CGFloat, y: CGFloat, diameter: CGFloat) {
        let r = CGRect(x: x, y: y, width: diameter, height: diameter)
        c.setStrokeColor(WorldAtmosphere.color(0xD8FFF4, alpha: 0.82).cgColor)
        c.setLineWidth(1.6)
        c.strokeEllipse(in: r)
    }

    private static func text(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat,
                             color: UInt32, weight: NSFont.Weight = .regular, centered: Bool = false,
                             halo: UInt32? = nil, lines: Int = 1) {
        let style = NSMutableParagraphStyle()
        style.alignment = centered ? .center : .left
        style.lineBreakMode = lines > 1 ? .byWordWrapping : .byTruncatingTail
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: WorldAtmosphere.color(color),
            .paragraphStyle: style
        ]
        if let halo {
            let shadow = NSShadow()
            shadow.shadowOffset = .zero
            shadow.shadowBlurRadius = 2.5
            shadow.shadowColor = WorldAtmosphere.color(halo, alpha: 0.75)
            attributes[.shadow] = shadow
        }
        let rect = CGRect(x: x, y: y, width: width, height: size * 1.4 * CGFloat(lines))
        if lines > 1 {
            (value as NSString).draw(with: rect,
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
        } else {
            (value as NSString).draw(in: rect, withAttributes: attributes)
        }
    }

    private static func pixelSprite(_ c: CGContext, rows: [String], colors: [Character: UInt32],
                                    x: CGFloat, y: CGFloat, unit: CGFloat, alpha: CGFloat) {
        c.saveGState()
        c.setShouldAntialias(false)
        let side = abs(unit)
        for (row, line) in rows.enumerated() {
            for (column, pixel) in line.enumerated() where pixel != "." {
                guard let color = colors[pixel] else { continue }
                let left = (x + CGFloat(column) * unit).rounded()
                let right = (x + CGFloat(column) * unit + side).rounded()
                let bottom = (y - CGFloat(row) * side).rounded()
                let top = (y - CGFloat(row - 1) * side).rounded()
                fill(c, CGRect(x: left, y: bottom, width: right - left, height: top - bottom), color, alpha: alpha)
            }
        }
        c.restoreGState()
    }

    private static func fill(_ c: CGContext, _ rect: CGRect, _ color: UInt32, alpha: CGFloat = 1) {
        c.setFillColor(WorldAtmosphere.color(color, alpha: alpha).cgColor)
        c.fill(rect.integral)
    }
}
