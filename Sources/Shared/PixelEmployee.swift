import AppKit

/// Original, hand-placed 16-bit RPG sprites. All three states face away from the
/// camera; the sleeping state exposes only the back of the head above a quilt.
enum PixelEmployee {
    /// True only when the three production sprites were decoded successfully.
    static var hasSprites: Bool { PixelEmployeeSprites.isAvailable }
    private static let outline: UInt32 = 0x2F332A
    private static let greenDark: UInt32 = 0x405C35
    private static let green: UInt32 = 0x66854A
    private static let greenLight: UInt32 = 0x8EA45C
    private static let greenHighlight: UInt32 = 0xAFB979
    private static let trousersDark: UInt32 = 0x303C4D
    private static let trousers: UInt32 = 0x46526A
    private static let trousersLight: UInt32 = 0x62718B
    private static let skin: UInt32 = 0xC99C6B
    private static let skinLight: UInt32 = 0xE0B783
    private static let shoeShadow: UInt32 = 0xA39273
    private static let shoe: UInt32 = 0xD7C8A2
    private static let shoeLight: UInt32 = 0xF0E2BC

    /// Production poses include their painted pixel detail; the missing-resource
    /// fallback is 24×36 grid pixels seated and 24×44 standing. Both show only backs.
    static func drawWorking(in c: CGContext, standing: CGFloat, time: TimeInterval,
                            activity: EmployeeActivity, feet: CGPoint, pixelSize: CGFloat = 3) {
        if PixelEmployeeSprites.drawWorking(in: c, standing: standing, time: time,
                                            activity: activity, feet: feet, pixelSize: pixelSize) { return }
        let unit = max(1, pixelSize)
        let extensionPixels = Int((max(0, min(1, standing)) * 8).rounded())
        let legTop = 8 + extensionPixels
        let typing = activity == .working && time > 0
        let handPhase = typing ? Int((time * 3).rounded(.down)) % 2 : 0
        c.saveGState()
        c.setShouldAntialias(false)
        c.translateBy(x: (feet.x / unit).rounded() * unit,
                      y: (feet.y / unit).rounded() * unit)
        c.scaleBy(x: unit, y: unit)
        c.translateBy(x: -12, y: 0)

        // Shoes stay on the same ground line through the whole standing transition.
        r(c, 4, 0, 8, 3, outline); r(c, 13, 0, 8, 3, outline)
        r(c, 5, 1, 6, 2, shoe); r(c, 14, 1, 6, 2, shoe)
        r(c, 5, 2, 6, 1, shoeLight); r(c, 14, 2, 6, 1, shoeLight)
        r(c, 5, 0, 6, 1, shoeShadow); r(c, 14, 0, 6, 1, shoeShadow)
        r(c, 8, 1, 2, 1, shoeLight); r(c, 17, 1, 2, 1, shoeLight)

        // Straight, separated legs: shorter when sitting, with no sideways kick.
        r(c, 5, 3, 7, legTop - 1, trousersDark)
        r(c, 13, 3, 7, legTop - 1, trousersDark)
        r(c, 6, 3, 5, legTop - 2, trousers)
        r(c, 14, 3, 5, legTop - 2, trousers)
        r(c, 6, 4, 1, legTop - 3, trousersLight)
        r(c, 14, 4, 1, legTop - 3, trousersLight)
        r(c, 5, 3, 7, 1, trousersLight); r(c, 13, 3, 7, 1, trousersLight)
        r(c, 5, legTop - 1, 15, 4, trousersDark)
        r(c, 7, legTop, 11, 3, trousers)
        r(c, 11, legTop, 2, 2, trousersDark)

        // Loose, shaded green shirt. One-pixel ramps replace smooth lighting.
        r(c, 5, legTop + 2, 14, 15, outline)
        r(c, 3, legTop + 8, 18, 9, outline)
        r(c, 2, legTop + 11, 20, 5, outline)
        r(c, 6, legTop + 3, 12, 12, green)
        r(c, 4, legTop + 8, 16, 8, green)
        r(c, 3, legTop + 12, 18, 3, green)
        r(c, 5, legTop + 5, 2, 8, greenDark)
        r(c, 17, legTop + 4, 2, 9, greenDark)
        r(c, 7, legTop + 4, 1, 7, greenLight)
        r(c, 8, legTop + 3, 8, 1, greenDark)
        r(c, 8, legTop + 4, 8, 1, greenLight)
        r(c, 8, legTop + 6, 6, 1, greenLight)
        r(c, 10, legTop + 9, 7, 1, greenDark)
        r(c, 5, legTop + 14, 2, 1, greenHighlight)
        r(c, 18, legTop + 13, 2, 1, greenLight)

        // Short sleeves point toward the desk. Only the backs of tiny hands show.
        r(c, 1, legTop + 12, 3, 4, greenDark)
        r(c, 21, legTop + 12, 2, 4, greenDark)
        r(c, 1, legTop + 15 + handPhase, 3, 2, outline)
        r(c, 2, legTop + 16 + handPhase, 2, 1, skinLight)
        r(c, 21, legTop + 16 - handPhase, 2, 2, outline)
        r(c, 21, legTop + 17 - handPhase, 2, 1, skin)
        r(c, 2, legTop + 13, 2, 2, greenLight)
        r(c, 20, legTop + 13, 2, 2, green)

        // Back of the hood, including a tiny centre seam and the pointed fold.
        r(c, 7, legTop + 12, 10, 6, greenDark)
        r(c, 8, legTop + 13, 8, 5, greenLight)
        r(c, 9, legTop + 12, 6, 2, green)
        r(c, 10, legTop + 11, 4, 2, greenDark)
        r(c, 11, legTop + 12, 2, 4, green)
        r(c, 8, legTop + 17, 8, 1, greenHighlight)
        drawHair(in: c, x: 3, y: legTop + 15)
        c.restoreGState()
    }

    /// The seated production sprite already contains its chair. The room calls
    /// this separately only when the employee is standing or has gone to bed.
    static func drawEmptyChair(in c: CGContext, standing: CGFloat, feet: CGPoint,
                               pixelSize: CGFloat = 6) {
        PixelEmployeeSprites.drawEmptyChair(in: c, standing: standing, feet: feet, pixelSize: pixelSize)
    }

    /// The pillow and quilt belong to the room. This sprite is only a rear head
    /// and a small green collar, so no bent legs can protrude from the bed.
    static func drawSleeping(in c: CGContext, time: TimeInterval, headCenter: CGPoint,
                             pixelSize: CGFloat = 3) {
        if PixelEmployeeSprites.drawSleeping(in: c, headCenter: headCenter, pixelSize: pixelSize) { return }
        let unit = max(1, pixelSize)
        c.saveGState()
        c.setShouldAntialias(false)
        c.translateBy(x: (headCenter.x / unit).rounded() * unit,
                      y: (headCenter.y / unit).rounded() * unit)
        c.scaleBy(x: unit, y: unit)
        r(c, -6, -8, 12, 4, greenDark)
        r(c, -5, -7, 10, 2, green)
        let breath = time > 0 && Int(time * 0.7) % 3 == 1 ? 1 : 0
        r(c, -3, -7 + breath, 6, 1, greenLight)
        drawHair(in: c, x: -9, y: -6)
        c.restoreGState()
    }

    /// A little 38×17 grid-pixel balloon with the exact bitmap lettering Zzzzz.
    static func drawSleepBubble(in c: CGContext, time: TimeInterval, origin: CGPoint,
                               pixelSize: CGFloat = 3) {
        let unit = max(1, pixelSize)
        let rise = time > 0 && Int(time * 0.8) % 3 == 1 ? 1 : 0
        c.saveGState()
        c.setShouldAntialias(false)
        c.translateBy(x: (origin.x / unit).rounded() * unit,
                      y: (origin.y / unit).rounded() * unit + CGFloat(rise) * unit)
        c.scaleBy(x: unit, y: unit)
        let border: UInt32 = 0x72512F
        let paper: UInt32 = 0xF6E7BD
        r(c, 2, 4, 34, 13, border)
        r(c, 0, 6, 38, 9, border)
        r(c, 6, 1, 5, 5, border)
        r(c, 2, 5, 34, 11, paper)
        r(c, 1, 6, 36, 9, paper)
        r(c, 7, 2, 3, 4, paper)
        r(c, 3, 15, 32, 1, 0xFFF2D1)
        let upper = ["11111", "00001", "00010", "00100", "01000", "10000", "11111"]
        let lower = ["0000", "0000", "1111", "0010", "0100", "1000", "1111"]
        bitmap(in: c, rows: upper, x: 5, y: 7, tint: border)
        for column in 0..<4 { bitmap(in: c, rows: lower, x: 11 + column * 5, y: 7, tint: border) }
        c.restoreGState()
    }

    // Eighteen columns and thirteen rows of deliberately irregular, shaded hair.
    // Every visible detail is on the rear crown; no face pixels are present.
    private static let hair = [
        "......OOOOOO......",
        "....OOKKHHKKOO....",
        "...OKHHMMHHKKKO...",
        "..OKHMMMHHKKKHKO..",
        ".OKHHMMHHKHHHHKKO.",
        ".OKHMHHKKHMMHHKKO.",
        "OKHHHKKKHHMHHKKKKO",
        "OKHHKKHMMHHHKKKKKO",
        ".OKKKHHMHHKKKHHKO.",
        ".OKKHMMHHKKHHHKKO.",
        "..OKHHHKKKHHKKKO..",
        "...OKKKHHKKKKKO...",
        "....OOKKKKKKOO...."
    ]

    private static func drawHair(in c: CGContext, x: Int, y: Int) {
        let palette: [Character: UInt32] = ["O": 0x2E231E, "K": 0x4B3325, "H": 0x6B4B30, "M": 0x8F673D]
        for (row, value) in hair.enumerated() {
            for (column, character) in value.enumerated() {
                if let tint = palette[character] { r(c, x + column, y + hair.count - 1 - row, 1, 1, tint) }
            }
        }
    }

    private static func bitmap(in c: CGContext, rows: [String], x: Int, y: Int, tint: UInt32) {
        for (row, value) in rows.enumerated() {
            for (column, character) in value.enumerated() where character == "1" {
                r(c, x + column, y + rows.count - 1 - row, 1, 1, tint)
            }
        }
    }

    private static func r(_ c: CGContext, _ x: Int, _ y: Int, _ width: Int, _ height: Int, _ tint: UInt32) {
        guard width > 0 && height > 0 else { return }
        c.setFillColor(CGColor(red: CGFloat((tint >> 16) & 255) / 255,
                              green: CGFloat((tint >> 8) & 255) / 255,
                              blue: CGFloat(tint & 255) / 255, alpha: 1))
        c.fill(CGRect(x: x, y: y, width: width, height: height))
    }
}
