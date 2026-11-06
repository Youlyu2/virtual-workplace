import AppKit

/// One garden visitor per personal reminder. Identity, seat and walking phase
/// survive redraws and host restarts; only the real date advances the waiting
/// label. This layer is intentionally absent from the room's window backdrop.
enum PendingNoteVisitors {
    struct Motion: Equatable {
        let offset: CGPoint
        let direction: PixelWalkDirection
        let distance: CGFloat
        let isMoving: Bool
    }

    struct Placement {
        let note: PendingNote
        let slot: Int
        let cell: CGRect
        let bubble: CGRect
        let feet: CGPoint
        let spriteHeight: CGFloat
        let scale: CGFloat
        let motion: Motion
        let accent: UInt32
        let waitingLabel: String

        var spriteBounds: CGRect {
            CGRect(x: feet.x - spriteHeight * 0.5, y: feet.y,
                   width: spriteHeight, height: spriteHeight + 2 * scale)
        }
    }

    private static let palette: [UInt32] = [0x487A68, 0x8C6AAA, 0xB87840, 0x447F9D,
                                            0xA65D73, 0x6E7D3F, 0x946B4C, 0x4F7B85]
    // Character size follows the scene's scale, not how many notes happen to
    // exist. Leave enough vertical space for an adult silhouette and its card;
    // squeezing the whole queue into half the scene made every person tiny.
    private static let spriteHeight: CGFloat = 144
    private static let rowPitch: CGFloat = 250
    private static let rowDepth: CGFloat = 110
    private static let bottomMargin: CGFloat = 82
    private static let bubbleHeight: CGFloat = 68
    private static let bubbleGap: CGFloat = 22

    /// Swift's randomized hash must never decide a visitor's visual identity.
    static func identitySeed(_ id: String) -> UInt64 {
        id.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }

    static func motion(for id: String, at date: Date, reduceMotion: Bool) -> Motion {
        guard !reduceMotion else { return Motion(offset: .zero, direction: .down, distance: 0, isMoving: false) }
        let seed = identitySeed(id)
        let halfWidth = CGFloat(14 + seed % 9)
        let halfDepth = CGFloat(6 + (seed >> 8) % 7)
        let speed = CGFloat(7 + (seed >> 16) % 5)
        let pause = Double(5 + (seed >> 24) % 4)
        let nodes = [CGPoint(x: -halfWidth, y: -halfDepth), CGPoint(x: halfWidth, y: -halfDepth),
                     CGPoint(x: halfWidth, y: halfDepth), CGPoint(x: -halfWidth, y: halfDepth)]
        let headings: [PixelWalkDirection] = [.right, .up, .left, .down]
        let lengths = [halfWidth * 2, halfDepth * 2, halfWidth * 2, halfDepth * 2]
        let cycle = lengths.reduce(0.0) { $0 + Double($1 / speed) + pause }
        let clock = date.timeIntervalSinceReferenceDate
        var phase = WorldAtmosphere.positiveRemainder((clock.isFinite ? clock : 0)
            + Double(seed % 10_000), cycle)
        var travelled: CGFloat = 0
        for index in 0..<4 {
            let duration = Double(lengths[index] / speed)
            let start = nodes[index], end = nodes[(index + 1) % 4]
            if phase < duration {
                let t = CGFloat(phase / duration)
                return Motion(offset: CGPoint(x: start.x + (end.x - start.x) * t,
                                              y: start.y + (end.y - start.y) * t),
                    direction: headings[index], distance: travelled + lengths[index] * t, isMoving: true)
            }
            phase -= duration; travelled += lengths[index]
            if phase < pause {
                return Motion(offset: end, direction: headings[index], distance: travelled, isMoving: false)
            }
            phase -= pause
        }
        return Motion(offset: nodes[0], direction: .down, distance: 0, isMoving: false)
    }

    static func placements(notes: [PendingNote], bounds: CGRect, at date: Date,
                           reduceMotion: Bool) -> [Placement] {
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { return [] }
        var seen = Set<String>()
        let unique = notes.filter { seen.insert($0.id).inserted }.sorted { $0.id < $1.id }
            .prefix(PendingNote.maximumCount)
        guard !unique.isEmpty else { return [] }
        var seats: [String: Int] = [:], occupied = Set<Int>()
        for note in unique {
            if let slot = note.slot, (0..<PendingNote.maximumCount).contains(slot), occupied.insert(slot).inserted {
                seats[note.id] = slot
            }
        }
        // Compatibility for snapshots written before slots were introduced.
        // New notes persist their seat, so deleting a neighbor cannot move them.
        for note in unique where seats[note.id] == nil {
            let first = Int(identitySeed(note.id) % UInt64(PendingNote.maximumCount))
            if let slot = (0..<PendingNote.maximumCount).map({ (first + $0) % PendingNote.maximumCount })
                .first(where: { !occupied.contains($0) }) {
                occupied.insert(slot); seats[note.id] = slot
            }
        }
        // Two staggered ground rows, four people each. Alternating columns
        // let the farther people stand between the nearer cards, so enlarging
        // a person never pushes their feet up onto the fence or mountains.
        // The management panel retains full-size text beside its small preview.
        let columns = 4
        let scale = min(bounds.width / 1672, bounds.height / 941)
        let margin = max(24 * scale, min(bounds.width * 0.04, 60 * scale))
        let cellWidth = (bounds.width - margin * 2) / CGFloat(columns * 2)
        let bubbleWidth = min(210 * scale, cellWidth - 12 * scale)
        let hudScale = min(bounds.height / 941, bounds.width / 400)
        let firstFeetY = max(bottomMargin * scale, 60 * hudScale + 24 * scale)
        return unique.compactMap { note in
            guard let slot = seats[note.id] else { return nil }
            let row = slot / columns, column = (slot % columns) * 2 + row
            let centerX = bounds.minX + margin + (CGFloat(column) + 0.5) * cellWidth
            let baseY = bounds.minY + firstFeetY + CGFloat(row) * rowDepth * scale
            let movement = motion(for: note.id, at: date, reduceMotion: reduceMotion)
            let cell = CGRect(x: bounds.minX + margin + CGFloat(column) * cellWidth,
                y: baseY - 14 * scale, width: cellWidth, height: rowPitch * scale)
            return Placement(note: note, slot: slot, cell: cell,
                bubble: CGRect(x: centerX - bubbleWidth / 2, y: baseY + (spriteHeight + bubbleGap) * scale,
                    width: bubbleWidth, height: bubbleHeight * scale),
                feet: CGPoint(x: centerX + movement.offset.x * scale, y: baseY + movement.offset.y * scale),
                spriteHeight: spriteHeight * scale, scale: scale, motion: movement,
                accent: palette[slot % palette.count],
                waitingLabel: note.waitingLabel(at: date))
        }
    }

    static func draw(in c: CGContext, bounds: CGRect, notes: [PendingNote], world: SceneWorld,
                     at date: Date, reduceMotion: Bool) {
        let visitors = placements(notes: notes, bounds: bounds, at: date, reduceMotion: reduceMotion)
        guard !visitors.isEmpty else { return }
        let darkness = CGFloat(world.environment(at: date).darkness)
        c.saveGState(); c.clip(to: bounds); c.setShouldAntialias(false); c.interpolationQuality = .none
        // Far feet first, like the rest of the game's flat foreground layers.
        for visitor in visitors.sorted(by: { $0.feet.y > $1.feet.y }) {
            let s = visitor.scale
            c.setFillColor(WorldAtmosphere.color(0x29372B, alpha: 0.25).cgColor)
            c.fill(CGRect(x: visitor.feet.x - 25 * s, y: visitor.feet.y - 2 * s,
                          width: 50 * s, height: 6 * s).integral)
            // Each visitor needs an isolated tint, not a display-sized backing
            // surface. Leave generous room for hats and every walking profile.
            let layerBounds = CGRect(x: visitor.feet.x - visitor.spriteHeight,
                y: visitor.feet.y - 4 * s, width: visitor.spriteHeight * 2,
                height: visitor.spriteHeight + 8 * s).integral
            c.saveGState(); c.beginTransparencyLayer(in: layerBounds, auxiliaryInfo: nil)
            let drawn = PendingVisitorSprites.draw(in: c, variant: visitor.slot,
                direction: visitor.motion.direction, distance: visitor.motion.distance,
                isMoving: visitor.motion.isMoving, feet: visitor.feet, targetHeight: visitor.spriteHeight)
            if !drawn { fallbackVisitor(in: c, visitor: visitor) }
            if darkness > 0.001 {
                c.setBlendMode(.sourceAtop)
                c.setFillColor(WorldAtmosphere.color(0x324562, alpha: darkness * 0.38).cgColor)
                c.fill(visitor.spriteBounds)
            }
            c.endTransparencyLayer(); c.restoreGState()
            drawBubble(in: c, visitor: visitor)
        }
        c.restoreGState()
    }

    private static func fallbackVisitor(in c: CGContext, visitor: Placement) {
        let s = visitor.spriteHeight / 88, x = visitor.feet.x, y = visitor.feet.y
        c.setFillColor(WorldAtmosphere.color(0x342B25).cgColor)
        c.fill(CGRect(x: x - 14 * s, y: y, width: 10 * s, height: 28 * s))
        c.fill(CGRect(x: x + 4 * s, y: y, width: 10 * s, height: 28 * s))
        c.setFillColor(WorldAtmosphere.color(visitor.accent).cgColor)
        c.fill(CGRect(x: x - 18 * s, y: y + 24 * s, width: 36 * s, height: 34 * s))
        c.setFillColor(WorldAtmosphere.color(0x8B6041).cgColor)
        c.fill(CGRect(x: x - 15 * s, y: y + 56 * s, width: 30 * s, height: 30 * s))
    }

    static func summary(_ text: String) -> String {
        let compact = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return compact.count > 56 ? String(compact.prefix(55)) + "…" : compact
    }

    private struct BubbleKey: Hashable {
        let id: String, text: String, waiting: String
        let slot: Int, width: Int, height: Int, scale: Int
        let accent: UInt32
    }
    private static let bubbleLock = NSLock()
    private static var bubbleImages: [BubbleKey: CGImage] = [:]

    private static func drawBubble(in c: CGContext, visitor: Placement) {
        let r = visitor.bubble, s = visitor.scale
        let tail = CGMutablePath()
        tail.addLines(between: [CGPoint(x: visitor.feet.x - 5 * s, y: r.minY + 2 * s),
            CGPoint(x: visitor.feet.x + 5 * s, y: r.minY + 2 * s),
            CGPoint(x: visitor.feet.x, y: r.minY - 7 * s)])
        tail.closeSubpath(); c.addPath(tail)
        c.setFillColor(WorldAtmosphere.color(0x51412F).cgColor); c.fillPath()
        if let image = bubbleImage(visitor) { c.draw(image, in: r) }
    }

    private static func bubbleImage(_ visitor: Placement) -> CGImage? {
        let r = visitor.bubble, s = visitor.scale
        let key = BubbleKey(id: visitor.note.id, text: summary(visitor.note.text), waiting: visitor.waitingLabel,
            slot: visitor.slot, width: Int(ceil(r.width * 2)), height: Int(ceil(r.height * 2)),
            scale: Int((s * 10_000).rounded()), accent: visitor.accent)
        bubbleLock.lock(); defer { bubbleLock.unlock() }
        if let cached = bubbleImages[key] { return cached }
        guard let c = CGContext(data: nil, width: max(1, key.width), height: max(1, key.height),
            bitsPerComponent: 8, bytesPerRow: max(1, key.width) * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.scaleBy(x: 2, y: 2); c.setShouldAntialias(false)
        let body = CGRect(x: 0, y: 0, width: r.width, height: r.height)
        let corner = 3 * s
        c.setFillColor(WorldAtmosphere.color(0x51412F).cgColor)
        c.fill(body.insetBy(dx: corner, dy: 0)); c.fill(body.insetBy(dx: 0, dy: corner))
        c.setFillColor(WorldAtmosphere.color(0xF7E8C8).cgColor)
        c.fill(body.insetBy(dx: 2 * s, dy: 2 * s))
        c.setFillColor(WorldAtmosphere.color(visitor.accent).cgColor)
        c.fill(CGRect(x: 10 * s, y: 7 * s, width: 14 * s, height: 14 * s))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
        c.setShouldAntialias(true)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
        paragraph.minimumLineHeight = 16.5 * s; paragraph.maximumLineHeight = 16.5 * s
        (key.text as NSString).draw(with: CGRect(x: 11 * s, y: 27 * s, width: r.width - 22 * s, height: 34 * s),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [.font: NSFont.systemFont(ofSize: 15 * s, weight: .medium),
                         .foregroundColor: WorldAtmosphere.color(0x3B3226), .paragraphStyle: paragraph])
        let footer = NSMutableParagraphStyle(); footer.lineBreakMode = .byTruncatingTail
        (key.waiting as NSString).draw(in: CGRect(x: 31 * s, y: 6 * s, width: r.width - 42 * s, height: 16 * s),
            withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12.5 * s, weight: .medium),
                             .foregroundColor: WorldAtmosphere.color(0x67533A), .paragraphStyle: footer])
        let badge = NSMutableParagraphStyle(); badge.alignment = .center
        (String(visitor.slot + 1) as NSString).draw(in: CGRect(x: 10 * s, y: 7 * s, width: 14 * s, height: 14 * s),
            withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11 * s, weight: .bold),
                             .foregroundColor: NSColor.white, .paragraphStyle: badge])
        NSGraphicsContext.restoreGraphicsState()
        guard let image = c.makeImage() else { return nil }
        if bubbleImages.count >= 64 { bubbleImages.removeAll(keepingCapacity: true) }
        bubbleImages[key] = image
        return image
    }
}
