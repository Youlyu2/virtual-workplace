import AppKit

/// Artwork faces left. Tails are layered separately so each species can swim
/// at its own tempo. Decode the original pixel grids once for every host.
enum OceanWildlife {
    private struct Sprite {
        let image: CGImage
        var width: CGFloat { CGFloat(image.width) }
        var height: CGFloat { CGFloat(image.height) }

        init(_ rows: [String], _ palette: [Character: UInt32]) {
            let width = rows.map(\.count).max()!
            let context = CGContext(data: nil, width: width, height: rows.count, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setShouldAntialias(false)
            for (row, line) in rows.enumerated() {
                for (column, pixel) in line.enumerated() {
                    guard let color = palette[pixel] else { continue }
                    context.setFillColor(WorldAtmosphere.color(color).cgColor)
                    context.fill(CGRect(x: column, y: rows.count - row - 1, width: 1, height: 1))
                }
            }
            image = context.makeImage()!
        }

        func draw(in c: CGContext, x: CGFloat, top: CGFloat) {
            c.draw(image, in: CGRect(x: x, y: top - height, width: width, height: height))
        }
    }

    private struct Swimmer {
        let body: Sprite
        let tail: Sprite
        let joint: CGPoint
        let glow: CGPoint?

        init(_ body: [String], tail: [String], palette: [Character: UInt32],
             joint: CGPoint, glow: CGPoint? = nil) {
            self.body = Sprite(body, palette)
            self.tail = Sprite(tail, palette)
            self.joint = joint
            self.glow = glow
        }

        func draw(in c: CGContext, x: Double, y: Double, unit: CGFloat, toRight: Bool = false,
                  flap: Double, alpha: CGFloat) {
            c.saveGState()
            c.interpolationQuality = .none
            c.setAlpha(alpha)
            c.translateBy(x: x.rounded(), y: y.rounded())
            c.scaleBy(x: toRight ? -unit : unit, y: unit)
            if let glow {
                // Warm light from the lure spills into the surrounding water.
                let rings: [(CGFloat, CGFloat)] = [(7, 0.07), (5, 0.10), (3.5, 0.18)]
                for (radius, opacity) in rings {
                    c.setFillColor(WorldAtmosphere.color(0xFFDB72, alpha: opacity).cgColor)
                    c.fillEllipse(in: CGRect(x: glow.x - radius, y: glow.y - radius,
                                             width: radius * 2, height: radius * 2))
                }
            }
            c.saveGState()
            c.translateBy(x: joint.x, y: joint.y)
            c.rotate(by: flap)
            tail.draw(in: c, x: -1, top: (tail.height / 2).rounded(.up))
            c.restoreGState()
            body.draw(in: c, x: 0, top: 0)
            c.restoreGState()
        }
    }

    private static let silverfish = Swimmer([
        ".......OOOH.........",
        "....OOOHHHBOO.......",
        "..OOHHHHBBBBBOOO....",
        ".OHKJHHSSSSBBBBBOO..",
        "OHKKJHSSSSSSSSBBSBOO",
        "OBHHSSSSSSSSSSBBBBOO",
        ".OBBSSSSSSSSBBBBOO..",
        "...OOOBBBBBBOOO.....",
        "......OOBBO.........",
        "........OO.........."
    ], tail: [
        "....OO..", "...OBHO.", ".OOBHHO.", "OBSHOO..",
        "OBBBOO..", ".OOBBBO.", "...OBBO.", "....OO.."
    ], palette: [
        "O": 0x29576B, "B": 0x54899B, "S": 0x8AB8BA, "H": 0xADCED0,
        "K": 0x182D40, "J": 0xE3F4EF
    ], joint: CGPoint(x: 18, y: -4.5))

    private static let violetFish = Swimmer([
        ".........OO.........",
        ".......OOHOO........",
        ".....OOHSSBOO.......",
        "..OOHHSSSSBBOOO.....",
        ".OHKJHSSBBBBBHBOO...",
        "OHKKHHSSSSBBBBBBBOO.",
        "OBBHHSSSSSBBSBSBBBOO",
        ".OBBBSSSSSSBBBBBBOO.",
        "...OOBBBBBBBBOOO....",
        "......OOBBOOO.......",
        ".........OO........."
    ], tail: [
        "......OO", "....OOSO", "..OOSSO.", "OBSSOO..",
        "OBBBOO..", "..OOBSO.", "....OOSO", "......OO"
    ], palette: [
        "O": 0x3D4168, "B": 0x665E92, "S": 0x8B7BB0, "H": 0xABA0C3,
        "K": 0x242941, "J": 0xE9DFF4
    ], joint: CGPoint(x: 18, y: -6.5))

    private static let anglerfish = Swimmer([
        "..........OOOOOOO....................",
        ".......OOOOHHHHOOOO..................",
        ".....OOOH.........HOO................",
        "....OOH............HOO...............",
        "...OOH..............HOO..............",
        "...OH................HOO....OO.......",
        "..OOH.................HOO..OBBO......",
        "..OH...................HOOOBBBO......",
        "..OH....................OOHBBBOOO....",
        "..OH..................OOHBBBBBBBBBO..",
        "..OH.................OHBHBBBBBBBBBOO.",
        "..OH...............OOHHBBBSBBBBBBBBO.",
        ".OYYO.............OOHHBKJHBSBBSBBBBO.",
        "OYWLYO............OHBBKKHBBBBBSBBBBOO",
        "OYWLYO...........OHHHBBHHBBBSBBBBBBOO",
        ".OYYO............OHHHHHHHBBBBBBBBBBOO",
        ".................OHHHBBBBBSBBBBBBBBBO",
        "..................OKKKKBOOSBBBBBBBBO.",
        ".................OWKKWKKKKOSBBBBBBOO.",
        "..................OKKKKKKKKOSBBBBOO..",
        ".................OKKWKKWKKKOBBBBOO...",
        ".................OWHWHHWWHHBBBBBO....",
        "..................OHHHHHBBBBBBBO.....",
        "...................OOOOOBBBBBOO......",
        ".......................OBBSOO........",
        "........................OOOO........."
    ], tail: [
        "......OO", "....OBBO", "...OBHBO", ".OOBBBO.",
        "OBBBOO..", "OBBBOO..", ".OOBBBO.", "...OBBO.", ".....OO."
    ], palette: [
        "O": 0x473A3B, "B": 0x805847, "S": 0x684842, "H": 0xB1845D,
        "K": 0x281E29, "J": 0xF1CA83, "W": 0xFFF0BD, "L": 0xFFF8BE, "Y": 0xFFCE59
    ], joint: CGPoint(x: 35, y: -15.5), glow: CGPoint(x: 3, y: -14.5))

    private static let shark = Swimmer([
        "................OO.......................",
        "................OBO......................",
        "...............OBBO......................",
        "...............OBBBO.....................",
        "..............OBBBBOO....................",
        ".........OOOOOHBBBBBOOOO.................",
        ".....OOOOHHHHHHBBBBBBBBBOOOO.............",
        "...OOHHHHHHHHBBBBBBBBBBBBBBBOOOO.........",
        ".OOHHHKKHBBBBBBBBBBBBBBBBBBBBBBBOOO......",
        "OHHHHHJKHBBGGBBBBBBBBBBBBBBBBBBBBBBOOO...",
        "OHHHBBBBBBBGGGBBBBBBBBBBBBBBBBBBBBBBBBOO.",
        ".ODDDDDDSBBGGBBBBBBBBBBBBBBBBBBBBBBBBBBOO",
        "..OSSSSSSSSGGSSSSSSSSSSSSSSSSSBBBOOOOOO.",
        "....OWWSSSSSSSSSSSSSSSSSBBBBBBOOO........",
        "......OOWSSSSSSSBBBBBBBOOOOOOO...........",
        ".........OOOSSSBBBBBBOO..................",
        ".............OBBBBBBO....................",
        "..............OBBBBO.....................",
        "...............OBBO......................",
        "................OO......................."
    ], tail: [
        ".......OO", ".......OO", "......OBO", ".....OBBO", "....OBBBO", "...OBBBO.",
        ".OOBBBO..", "OBBBBO...", "OSBBBO...", ".OSBBBO..", "..OSBBO..", "...OSBBO.",
        "....OBBO.", ".....OO.."
    ], palette: [
        "O": 0x264B62, "B": 0x508397, "H": 0x7EA9B2, "S": 0xA6C6C9,
        "W": 0xD2E4DE, "G": 0x325E75, "D": 0x294756, "K": 0x172C3A, "J": 0xE3EFE8
    ], joint: CGPoint(x: 39, y: -11.3))

    private static let whaleShark = Swimmer([
        "...........................OOO........................",
        ".........................OOHHOO.......................",
        "........................OHHBHBOO......................",
        ".......................OHBPBBBBOO.....................",
        ".....................OOHBBBBPBBBOO....................",
        ".............OOOOOOOOHHBBBBBBBBBBOOO.......OO.........",
        ".......OOOOOOHHHHHHHHHBBBBPBBBBPBBBOOOOOOOOHBOO.......",
        "....OOOHHHPHHHHPHHHHHHHBBBBBBBBBBBBBBBHPHHHBBBOOO.....",
        "..OOHHHPHHHHHPHHHHPHHHHHPBBBBPBBBPBBBBBPBBBBBBOOOO....",
        ".OHHHHPHHHHPHHHHHHHHHBBBBBBBBBBBBBBBBBBBBBBBBBBBBBOOO.",
        "OHHHHPHHHHHHHHHPHHHHHHHHPBBBPBBBPBBBPBBBPBBBBBBBBBBOO",
        "OHHPHHHHKKHHHHHHHHPHHHHHHHHHHHHHHHHHHHHHHHHHBBBBBBBOO",
        "OHHHHHHHJKHHBPBBBBBBBPBBBPBBBPBBBPBBBPBBBPBBBBBBBBBOO",
        "ODDDDBBBBBBBGGGBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBOOO.",
        ".OSSSSSSBBBBGGGSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSOOOOO....",
        "..OSSSSSSSSSGGGSSSSSSSSSSSSSSSSSSSSSSSSSSSOOO.........",
        "....OOSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSOOOO............",
        "......OOOSSSSSSSSSSSSSSSSSSSSSSSSSOOOO................",
        ".........OOOOSSSSSSSSSSSSSOOOOOOOO....................",
        ".............OOOOBBBBBBOOO............................",
        ".................OBPBBBBO............................",
        "..................OBBBPBOO...........................",
        "...................OOBBBBOO..........................",
        ".....................OOOOOO.........................."
    ], tail: [
        "...............OO", ".............OOHO", "...........OOHHBO",
        ".........OOHHBBO.", ".......OOHBBPBO..", ".....OOHBBBBBO...",
        "...OOHBBBBBBO....", "OOOHBBBBBBBO.....", "OBBBBBBBBOO......",
        "OSSSBBBBBOO......", ".OOSSBBBBBOO.....", "...OOSSBBBBOO....",
        ".....OOSSBBBO....", ".......OOSSBO....", ".........OOOO...."
    ], palette: [
        "O": 0x203D56, "B": 0x466D83, "H": 0x6C99A6, "P": 0xC8DCD3,
        "S": 0x83AFB6, "G": 0x2E5269, "D": 0x284457, "K": 0x132B3C, "J": 0xE0F1E7
    ], joint: CGPoint(x: 51, y: -12.3))

    private static let dolphin = Swimmer([
        ".....................OO...................",
        "...................OOHBO..................",
        "..................OHBBOO..................",
        ".................OHBBBO...................",
        "........OOOOOOOOOHBBBBBOOOO...............",
        "......OOHHHHHHHHHHBBBBBBBBBOOOO...........",
        ".....OHHHHHHHHHHBBBBBBBBBBBBBBBOOOO.......",
        "....OHHHHHHHHBBBBBBBBBBBBBBBBBBBBBBOOO....",
        "....OHHHKJHBBBBBBBBBBBBBBBBBBBBBBBBBBOOO..",
        "...OHHHHKKHSSBBBBBBBBBBBBBBBBBBBBBBBBBBOOO",
        "OOOHHHHHHHHSSSSSBBBBBBBBBBBBBBBBBBBBBBBOOO",
        "OHHHHSSSSSSSSSSSSSSBBBBBBBBBBBBBBBBBOOOOOO",
        "ODDDDDSSSSSSSSSSSSSSSSBBBBBBBBBBOOOOO....",
        ".OOOOSSSSSSSSSSSSSSSSSSSBBBOOOOO.........",
        ".....OOSSSSSSSSSSSSSSSBBBOOO..............",
        ".......OOOOOSSSSSSSBBBOOO.................",
        "............OOOOOOBBBBO...................",
        "..................OBBBOO..................",
        "...................OBBBO..................",
        ".....................OOO.................."
    ], tail: [
        "...........OOOO...", ".........OOHHBOO..", ".......OOHHBBBO...",
        ".....OOHBBBBOO....", "...OOHBBBBOO......", "OOHBBBBBOO........",
        "OBBBBBBBOO........", "OSSBBBBBOOOO......", ".OOOSSBBBBBBOO....",
        "....OOOSSSBBBBOO..", ".......OOOSSBBBO..", "..........OOOOOO.."
    ], palette: [
        "O": 0x714964, "B": 0xE6819F, "H": 0xFFB1C6, "S": 0xFFD7DE,
        "K": 0x4B344F, "J": 0xFFF4F3, "D": 0xAC607D
    ], joint: CGPoint(x: 40, y: -10))

    static func drawShallowDolphin(in c: CGContext, clock: Double, reduceMotion: Bool, haze: CGFloat) {
        let elapsed = WorldAtmosphere.positiveRemainder(clock, 120)
        guard !reduceMotion, elapsed < 37 else { return }
        dolphin.draw(in: c, x: 1830 - elapsed * 59, y: 640 + sin(elapsed * 0.46) * 19,
                     unit: 5.6, flap: sin(elapsed * 2.9) * 0.23, alpha: 0.92 - haze * 0.34)
    }

    static func drawDeep(in c: CGContext, phase: Double, clock: Double, reduceMotion: Bool, haze: CGFloat) {
        let encounterCycle = WorldAtmosphere.positiveRemainder(clock, 288)
        let encounter = WorldAtmosphere.positiveRemainder(encounterCycle, 144)
        if !reduceMotion && encounter < 37 {
            let isWhaleShark = encounterCycle < 144
            let giant = isWhaleShark ? whaleShark : shark
            giant.draw(in: c, x: 1870 - encounter * (isWhaleShark ? 61 : 64),
                       y: (isWhaleShark ? 655 : 635) + sin(encounter * 0.47) * 13,
                       unit: isWhaleShark ? 7.0 : 6.1, flap: sin(encounter * (isWhaleShark ? 1.5 : 3.1)) * 0.15,
                       alpha: 0.93 - haze * 0.38)
        }

        for member in 0..<8 {
            let track = WorldAtmosphere.positiveRemainder(phase * 23 + Double(450 + member * 69), 1910)
            let y = 759 + Double(member % 4) * 28 + sin(phase * 0.76 + Double(member) * 0.55) * 13
            silverfish.draw(in: c, x: 1770 - track, y: y, unit: member.isMultiple(of: 3) ? 3.1 : 2.5,
                            flap: reduceMotion ? 0 : sin(phase * 6.5 + Double(member)) * 0.27,
                            alpha: 0.84 - haze * 0.42)
        }
        for member in 0..<6 {
            let track = WorldAtmosphere.positiveRemainder(phase * 19 + Double(780 + member * 71), 1880)
            let y = 532 + Double(member % 3) * 27 + sin(phase * 0.54 + Double(member) * 0.62) * 12
            violetFish.draw(in: c, x: track - 84, y: y, unit: member.isMultiple(of: 2) ? 3.1 : 2.5,
                            toRight: true, flap: reduceMotion ? 0 : sin(phase * 5 + Double(member)) * 0.28,
                            alpha: 0.83 - haze * 0.40)
        }
        let anglerPass = WorldAtmosphere.positiveRemainder(clock + 22, 125)
        if reduceMotion || anglerPass < 75 {
            let x = reduceMotion ? 620 : 1800 - anglerPass * 28
            let y = 288 + sin(phase * 0.62) * 14
            anglerfish.draw(in: c, x: x, y: y, unit: 4, flap: reduceMotion ? 0 : sin(phase * 3.8) * 0.22,
                            alpha: 0.95 - haze * 0.25)
        }
    }
}
