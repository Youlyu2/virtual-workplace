import AppKit

/// The camera is directly behind the employee. Screens and the desk keep their
/// own layers so a new task remains a real screen rather than part of a bitmap.
enum RearWorkplaceScene {
    private static func color(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: alpha)
    }
    private static let ink = color(0x3C5148)
    private static let secondary = color(0x889488)

    static func draw(in c: CGContext, snapshot: SceneSnapshot, frame: SceneFrame,
                     time: TimeInterval, reduceMotion: Bool) {
        let t = reduceMotion ? 0 : time
        let rise = frame.standing * 65
        backdrop(c, time: t)
        floor(c)
        plant(c, origin: CGPoint(x: 1038, y: 226), size: 1.12, time: t)
        sideCabinet(c)
        desk(c, rise: rise)
        for (task, opacity) in frame.screens where opacity > 0.005 {
            c.saveGState()
            c.setAlpha(opacity)
            monitor(c, task: task, rise: rise, appearance: opacity, online: snapshot.isFresh(), time: t)
            c.restoreGState()
        }
        deskObjects(c, rise: rise, time: t)
        if !CartoonCharacter.draw(in: c, frame: frame, activity: snapshot.resolvedActivity(),
                                  time: t, sipping: 0, origin: CGPoint(x: 600, y: 125)) {
            rearSilhouette(c, frame: frame)
        }
        chair(c, frame: frame)
        captions(c, snapshot: snapshot)
    }

    private static func round(_ c: CGContext, _ rect: CGRect, _ radius: CGFloat,
                              _ fill: NSColor, stroke: NSColor? = nil, width: CGFloat = 1) {
        c.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        c.setFillColor(fill.cgColor)
        if let stroke {
            c.setLineWidth(width); c.setStrokeColor(stroke.cgColor); c.drawPath(using: .fillStroke)
        } else { c.fillPath() }
    }
    private static func ellipse(_ c: CGContext, _ rect: CGRect, _ fill: NSColor) {
        c.setFillColor(fill.cgColor); c.fillEllipse(in: rect)
    }
    private static func polygon(_ c: CGContext, _ points: [CGPoint], _ fill: NSColor) {
        guard let first = points.first else { return }
        c.beginPath(); c.move(to: first)
        points.dropFirst().forEach { c.addLine(to: $0) }; c.closePath()
        c.setFillColor(fill.cgColor); c.fillPath()
    }
    private static func line(_ c: CGContext, _ points: [CGPoint], _ stroke: NSColor, width: CGFloat = 2) {
        guard let first = points.first else { return }
        c.beginPath(); c.move(to: first); points.dropFirst().forEach { c.addLine(to: $0) }
        c.setLineWidth(width); c.setLineCap(.round); c.setLineJoin(.round)
        c.setStrokeColor(stroke.cgColor); c.strokePath()
    }
    private static func text(_ string: String, _ point: CGPoint, size: CGFloat,
                             color: NSColor = ink, weight: NSFont.Weight = .regular) {
        (string as NSString).draw(at: point, withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color
        ])
    }

    private static func backdrop(_ c: CGContext, time: TimeInterval) {
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -9), blur: 27, color: color(0x7A8A75, alpha: 0.10).cgColor)
        round(c, CGRect(x: 90, y: 280, width: 1020, height: 474), 24, color(0xE7EBDF))
        c.restoreGState()
        // An almost frontal, gently receding room. It never swings around to a face.
        polygon(c, [CGPoint(x: 90, y: 280), CGPoint(x: 145, y: 310),
                    CGPoint(x: 145, y: 728), CGPoint(x: 90, y: 754)], color(0xD9E2D3))
        polygon(c, [CGPoint(x: 1055, y: 310), CGPoint(x: 1110, y: 280),
                    CGPoint(x: 1110, y: 754), CGPoint(x: 1055, y: 728)], color(0xD5DECF))
        line(c, [CGPoint(x: 145, y: 313), CGPoint(x: 1055, y: 313)], color(0xB5C4AE), width: 8)
        line(c, [CGPoint(x: 145, y: 321), CGPoint(x: 1055, y: 321)], color(0xEEF0E4), width: 2)
        window(c, time: time)
        shelf(c)
        // A little paper print establishes the wall without competing with screens.
        round(c, CGRect(x: 938, y: 546, width: 83, height: 122), 3, color(0xBBC7B3))
        round(c, CGRect(x: 944, y: 552, width: 71, height: 110), 1, color(0xF4EDD9))
        ellipse(c, CGRect(x: 960, y: 603, width: 37, height: 37), color(0xD8A477))
        polygon(c, [CGPoint(x: 951, y: 585), CGPoint(x: 976, y: 618), CGPoint(x: 1008, y: 585)], color(0x829B7F))
        text("TAKE IT SLOW", CGPoint(x: 951, y: 566), size: 7.2, color: color(0x7B8973), weight: .semibold)
    }

    private static func window(_ c: CGContext, time: TimeInterval) {
        let frame = CGRect(x: 170, y: 475, width: 176, height: 218)
        round(c, frame.insetBy(dx: -8, dy: -8), 10, color(0xC1CAB6))
        round(c, frame, 5, color(0xF2EBD8))
        c.saveGState()
        c.addPath(CGPath(roundedRect: frame.insetBy(dx: 10, dy: 10), cornerWidth: 2, cornerHeight: 2, transform: nil))
        c.clip()
        c.setFillColor(color(0xBDD4CB).cgColor); c.fill(frame)
        ellipse(c, CGRect(x: 282, y: 621, width: 35, height: 35), color(0xF4D49A))
        ellipse(c, CGRect(x: 115, y: 414, width: 235, height: 150), color(0x9AB7A4))
        ellipse(c, CGRect(x: 239, y: 413, width: 205, height: 136), color(0x83A693))
        let drift = time == 0 ? 0 : CGFloat(sin(time * 0.025)) * 5
        round(c, CGRect(x: 190 + drift, y: 641, width: 43, height: 5), 3, color(0xEFF1E1, alpha: 0.9))
        round(c, CGRect(x: 222 + drift, y: 604, width: 53, height: 5), 3, color(0xEFF1E1, alpha: 0.7))
        c.restoreGState()
        round(c, CGRect(x: 253, y: 484, width: 8, height: 200), 0, color(0xF2EBD8))
        round(c, CGRect(x: 179, y: 579, width: 158, height: 8), 0, color(0xF2EBD8))
        round(c, CGRect(x: 158, y: 468, width: 201, height: 12), 3, color(0xC4B89A))
        // Warm sunlight stays on the left half, leaving the character's silhouette clear.
        polygon(c, [CGPoint(x: 180, y: 470), CGPoint(x: 326, y: 470),
                    CGPoint(x: 433, y: 321), CGPoint(x: 226, y: 321)], color(0xF4E7BE, alpha: 0.23))
    }

    private static func shelf(_ c: CGContext) {
        round(c, CGRect(x: 855, y: 434, width: 168, height: 10), 2, color(0xB88D65))
        round(c, CGRect(x: 855, y: 444, width: 168, height: 5), 1, color(0xD2AE81))
        let books: [(CGFloat, CGFloat, CGFloat, UInt32)] = [
            (870, 13, 42, 0xC88C70), (885, 12, 54, 0xDFCA99),
            (900, 15, 46, 0x8DA58B), (918, 12, 50, 0xA9B99D)
        ]
        for (x, width, height, tint) in books {
            round(c, CGRect(x: x, y: 449, width: width, height: height), 1.5, color(tint))
            line(c, [CGPoint(x: x + 3, y: 457), CGPoint(x: x + width - 3, y: 457)], color(0xF0E5C9, alpha: 0.6), width: 1)
        }
        round(c, CGRect(x: 970, y: 450, width: 28, height: 26), 5, color(0xC89070))
        ellipse(c, CGRect(x: 968, y: 469, width: 32, height: 9), color(0xD9A787))
        line(c, [CGPoint(x: 984, y: 473), CGPoint(x: 984, y: 507)], color(0x74916A), width: 3)
        ellipse(c, CGRect(x: 970, y: 489, width: 16, height: 23), color(0x829E75))
        ellipse(c, CGRect(x: 983, y: 496, width: 16, height: 25), color(0x6E8C63))
    }

    private static func floor(_ c: CGContext) {
        polygon(c, [CGPoint(x: 90, y: 280), CGPoint(x: 145, y: 310),
                    CGPoint(x: 1055, y: 310), CGPoint(x: 1110, y: 280),
                    CGPoint(x: 1140, y: 82), CGPoint(x: 60, y: 82)], color(0xD5BC99))
        for index in 0...10 {
            let start = CGFloat(145 + index * 91)
            let end = CGFloat(60 + index * 108)
            line(c, [CGPoint(x: start, y: 308), CGPoint(x: end, y: 85)], color(0xB99B77, alpha: 0.32), width: 1)
        }
        for y: CGFloat in [123, 183, 247] {
            line(c, [CGPoint(x: 77, y: y), CGPoint(x: 1123, y: y)], color(0xB99B77, alpha: 0.20), width: 1)
        }
        round(c, CGRect(x: 321, y: 92, width: 558, height: 165), 56, color(0x92AC9B))
        round(c, CGRect(x: 334, y: 103, width: 532, height: 143), 47, color(0xA8BFAE))
        for y in stride(from: 117, through: 230, by: 13) {
            line(c, [CGPoint(x: 365, y: y), CGPoint(x: 835, y: y)], color(0xDCE3CE, alpha: 0.23), width: 1)
        }
    }

    private static func sideCabinet(_ c: CGContext) {
        round(c, CGRect(x: 173, y: 205, width: 103, height: 102), 6, color(0xC3AE8D))
        round(c, CGRect(x: 170, y: 301, width: 109, height: 10), 3, color(0xDDCAA4))
        for y: CGFloat in [238, 272] {
            line(c, [CGPoint(x: 180, y: y), CGPoint(x: 269, y: y)], color(0xA69375), width: 1)
            round(c, CGRect(x: 212, y: y + 12, width: 25, height: 3), 1.5, color(0x8F876C))
        }
        round(c, CGRect(x: 193, y: 310, width: 35, height: 10), 1, color(0x8A9E89))
        round(c, CGRect(x: 199, y: 321, width: 37, height: 6), 1, color(0xD6B890))
        let p = CGPoint(x: 248, y: 312)
        round(c, CGRect(x: p.x - 7, y: p.y, width: 15, height: 22), 3, color(0xEDE1C6))
        ellipse(c, CGRect(x: p.x - 6, y: p.y + 18, width: 13, height: 5), color(0x9B7758))
    }

    private static func plant(_ c: CGContext, origin: CGPoint, size: CGFloat, time: TimeInterval) {
        c.saveGState(); c.translateBy(x: origin.x, y: origin.y); c.scaleBy(x: size, y: size)
        ellipse(c, CGRect(x: -35, y: -5, width: 70, height: 16), color(0x556D51, alpha: 0.13))
        polygon(c, [CGPoint(x: -30, y: 46), CGPoint(x: 30, y: 46),
                    CGPoint(x: 22, y: 0), CGPoint(x: -22, y: 0)], color(0xC99170))
        ellipse(c, CGRect(x: -30, y: 38, width: 60, height: 17), color(0xDCAD88))
        ellipse(c, CGRect(x: -24, y: 41, width: 48, height: 10), color(0x7C7357))
        let sway = time == 0 ? 0 : CGFloat(sin(time * 0.6)) * 1.5
        for index in 0..<7 {
            let angle = CGFloat(index - 3) * 0.27
            let end = CGPoint(x: sin(angle) * 54 + sway, y: 161 - CGFloat(abs(index - 3)) * 15)
            line(c, [CGPoint(x: 0, y: 45), CGPoint(x: end.x, y: end.y - 10)], color(0x6A865E), width: 3)
            c.saveGState(); c.translateBy(x: end.x, y: end.y); c.rotate(by: -angle)
            ellipse(c, CGRect(x: -13, y: -23, width: 26, height: 48), color(index % 2 == 0 ? 0x75936B : 0x8BA278))
            line(c, [CGPoint(x: 0, y: -16), CGPoint(x: 0, y: 17)], color(0xC0CBA9, alpha: 0.6), width: 1)
            c.restoreGState()
        }
        c.restoreGState()
    }

    private static func desk(_ c: CGContext, rise: CGFloat) {
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -7), blur: 14, color: color(0x5C6D55, alpha: 0.12).cgColor)
        // The legs telescope, keeping the same ground contact in both postures.
        for x: CGFloat in [300, 900] {
            round(c, CGRect(x: x - 9, y: 155, width: 18, height: 154 + rise), 5, color(0x667D6C))
            round(c, CGRect(x: x - 6, y: 228, width: 12, height: 74 + rise), 3, color(0xA4B5A1))
            round(c, CGRect(x: x - 32, y: 150, width: 64, height: 10), 5, color(0x5A7160))
        }
        c.restoreGState()
        polygon(c, [CGPoint(x: 270, y: 305 + rise), CGPoint(x: 930, y: 305 + rise),
                    CGPoint(x: 885, y: 403 + rise), CGPoint(x: 315, y: 403 + rise)], color(0xD7AE7F))
        round(c, CGRect(x: 270, y: 293 + rise, width: 660, height: 14), 4, color(0xB98A5D))
        line(c, [CGPoint(x: 274, y: 305 + rise), CGPoint(x: 926, y: 305 + rise)], color(0xE9C99B), width: 3)
        for y: CGFloat in [326, 349, 377] {
            line(c, [CGPoint(x: 295, y: y + rise), CGPoint(x: 905, y: y + rise)], color(0xBB8E62, alpha: 0.23), width: 1)
        }
        round(c, CGRect(x: 862, y: 297 + rise, width: 23, height: 5), 2, color(0x6D7C65))
        ellipse(c, CGRect(x: 879, y: 298 + rise, width: 2.5, height: 2.5), color(0xBDD6A4))
    }

    private static func monitor(_ c: CGContext, task: WorkplaceTask, rise: CGFloat,
                                appearance: CGFloat, online: Bool, time: TimeInterval) {
        let isUpper = task.slot >= 3
        let centers: [CGFloat] = [600, 390, 810, 390, 600, 810]
        let x = centers[task.slot]
        let width: CGFloat = isUpper ? 176 : 184
        let height: CGFloat = isUpper ? 95 : 112
        let bottom: CGFloat = (isUpper ? 557 : 425) + rise + (1 - appearance) * 12
        let rect = CGRect(x: x - width / 2, y: bottom, width: width, height: height)
        if isUpper {
            line(c, [CGPoint(x: x + 72, y: 408 + rise), CGPoint(x: x + 72, y: bottom + 34),
                     CGPoint(x: x + 46, y: bottom + 34)], color(0x7D9180), width: 4)
        } else {
            round(c, CGRect(x: x - 5, y: 397 + rise, width: 10, height: 31), 2, color(0x637C6C))
            round(c, CGRect(x: x - 31, y: 393 + rise, width: 62, height: 7), 3, color(0x7F9481))
        }
        c.saveGState()
        c.setShadow(offset: CGSize(width: 1, height: -4), blur: 9, color: color(0x3E5547, alpha: 0.17).cgColor)
        round(c, rect, 7, color(0x536D60)); c.restoreGState()
        round(c, rect.insetBy(dx: 3, dy: 3), 5, color(0x243E34))
        let screen = rect.insetBy(dx: 8, dy: 8)
        round(c, screen, 2, color(online ? 0x244137 : 0x3D4A40))
        let tint: NSColor = !online ? color(0xA2AEA0) : task.status == .running ? color(0xB9D4AA)
            : task.status == .waiting ? color(0xEBC983) : task.status == .failed ? color(0xE9A488) : color(0xA9D5B7)
        let headerY = screen.maxY - 14
        ellipse(c, CGRect(x: screen.minX + 7, y: headerY + 2, width: 4, height: 4), tint)
        text(String(format: "SESSION %02d", task.slot + 1), CGPoint(x: screen.minX + 16, y: headerY), size: 6, color: color(0xCCDCC5), weight: .medium)
        line(c, [CGPoint(x: screen.minX + 7, y: headerY - 5), CGPoint(x: screen.maxX - 7, y: headerY - 5)], color(0x5C7866, alpha: 0.5), width: 0.7)
        if task.status == .completed && online {
            line(c, [CGPoint(x: x - 12, y: screen.midY + 2), CGPoint(x: x - 3, y: screen.midY - 7),
                     CGPoint(x: x + 14, y: screen.midY + 10)], tint, width: 3)
        } else if (task.status == .waiting || task.status == .failed) && online {
            text(task.status == .failed ? "!" : "…", CGPoint(x: x - 5, y: screen.midY - 10), size: 24, color: tint, weight: .medium)
        } else {
            let count = isUpper ? 4 : 5
            let lengths: [CGFloat] = [59, 99, 77, 116, 67]
            for index in 0..<count {
                let shift: CGFloat = index % 2 == 0 ? 0 : 12
                let pulse = time > 0 && online ? CGFloat(sin(time * 1.2 + Double(index))) * 0.04 + 0.96 : 0.94
                round(c, CGRect(x: screen.minX + 8 + shift, y: headerY - 16 - CGFloat(index) * 9,
                                width: lengths[index] * pulse, height: 2.5), 1,
                      color(index % 3 == 0 ? 0xD1BC91 : 0x96B69D, alpha: online ? 0.85 : 0.24))
            }
        }
        let glyph = !online ? "○" : task.status == .completed ? "✓" : task.status == .failed ? "!" : task.status == .waiting ? "◷" : "●"
        text(glyph + " " + (online ? task.status.title : "已离线"), CGPoint(x: screen.minX + 8, y: screen.minY + 5), size: 6.5, color: tint)
        ellipse(c, CGRect(x: rect.midX - 1.2, y: rect.minY + 2, width: 2.4, height: 2.4), tint)
    }

    private static func deskObjects(_ c: CGContext, rise: CGFloat, time: TimeInterval) {
        polygon(c, [CGPoint(x: 481, y: 316 + rise), CGPoint(x: 719, y: 316 + rise),
                    CGPoint(x: 704, y: 374 + rise), CGPoint(x: 496, y: 374 + rise)], color(0x809A86))
        polygon(c, [CGPoint(x: 527, y: 333 + rise), CGPoint(x: 663, y: 333 + rise),
                    CGPoint(x: 657, y: 360 + rise), CGPoint(x: 533, y: 360 + rise)], color(0xE6DDC3))
        for row in 0..<3 {
            for column in 0..<11 {
                round(c, CGRect(x: 536 + CGFloat(column) * 10.6, y: 337 + CGFloat(row) * 7 + rise,
                                width: 7.2, height: 3), 0.7, color(0xB5BCA5))
            }
        }
        ellipse(c, CGRect(x: 679, y: 340 + rise, width: 18, height: 24), color(0xE3D8BC))
        // Small angled lamp stays outside the screen wall.
        ellipse(c, CGRect(x: 320, y: 335 + rise, width: 44, height: 12), color(0xAC835A))
        line(c, [CGPoint(x: 342, y: 341 + rise), CGPoint(x: 338, y: 420 + rise),
                 CGPoint(x: 373, y: 448 + rise)], color(0xB28B5C), width: 5)
        ellipse(c, CGRect(x: 333, y: 416 + rise, width: 10, height: 10), color(0xD4AE75))
        polygon(c, [CGPoint(x: 361, y: 454 + rise), CGPoint(x: 393, y: 438 + rise),
                    CGPoint(x: 401, y: 420 + rise), CGPoint(x: 350, y: 438 + rise)], color(0xCFAB72))
        ellipse(c, CGRect(x: 355, y: 428 + rise, width: 42, height: 10), color(0xF5DFAD))
        // Coffee and paper make the foreground readable when no sessions are open.
        round(c, CGRect(x: 421, y: 332 + rise, width: 22, height: 27), 4, color(0xF0E6CD))
        c.setStrokeColor(color(0xDECDAF).cgColor); c.setLineWidth(4)
        c.strokeEllipse(in: CGRect(x: 438, y: 337 + rise, width: 13, height: 15))
        ellipse(c, CGRect(x: 423, y: 354 + rise, width: 18, height: 6), color(0x9C7754))
        if time > 0 {
            let drift = CGFloat(sin(time * 1.5)) * 2
            line(c, [CGPoint(x: 431, y: 365 + rise), CGPoint(x: 432 + drift, y: 375 + rise),
                     CGPoint(x: 430, y: 383 + rise)], color(0xF1E6CD, alpha: 0.7), width: 2)
        }
        polygon(c, [CGPoint(x: 760, y: 328 + rise), CGPoint(x: 824, y: 328 + rise),
                    CGPoint(x: 816, y: 370 + rise), CGPoint(x: 766, y: 370 + rise)], color(0xF1E2C0))
        for index in 0..<4 {
            line(c, [CGPoint(x: 773, y: 336 + CGFloat(index) * 8 + rise),
                     CGPoint(x: 809, y: 336 + CGFloat(index) * 8 + rise)], color(0xC9BB98), width: 1)
        }
        line(c, [CGPoint(x: 817, y: 333 + rise), CGPoint(x: 829, y: 363 + rise)], color(0xBA7960), width: 3)
    }

    private static func chair(_ c: CGContext, frame: SceneFrame) {
        let stand = frame.standing, slack = frame.slacking
        let x: CGFloat = 600 + 238 * stand
        let y: CGFloat = 125 - 10 * stand - 7 * slack
        c.saveGState(); c.translateBy(x: x, y: y)
        ellipse(c, CGRect(x: -65, y: -8, width: 130, height: 21), color(0x526D57, alpha: 0.12))
        line(c, [CGPoint(x: 0, y: 9), CGPoint(x: 0, y: 86)], color(0x5D7663), width: 8)
        for index in 0..<5 {
            let angle = CGFloat(index) * .pi * 2 / 5
            let end = CGPoint(x: cos(angle) * 58, y: sin(angle) * 15 + 6)
            line(c, [CGPoint(x: 0, y: 14), end], color(0x5A715F), width: 5)
            ellipse(c, CGRect(x: end.x - 6, y: end.y - 5, width: 12, height: 9), color(0x465F4D))
        }
        round(c, CGRect(x: -56, y: 81, width: 112, height: 16), 8, color(0x597662))
        // Camera sees the outer chair back; it naturally overlaps only the lower hoodie.
        let backY: CGFloat = 97 - 7 * slack
        round(c, CGRect(x: -61, y: backY, width: 122, height: 94), 23, color(0x56765F))
        round(c, CGRect(x: -55, y: backY + 7, width: 110, height: 82), 19, color(0x789881))
        line(c, [CGPoint(x: -37, y: backY + 20), CGPoint(x: -37, y: backY + 69)], color(0x9BB49A, alpha: 0.4), width: 1.3)
        line(c, [CGPoint(x: 37, y: backY + 20), CGPoint(x: 37, y: backY + 69)], color(0x9BB49A, alpha: 0.4), width: 1.3)
        round(c, CGRect(x: -17, y: backY + 39, width: 34, height: 6), 3, color(0x5F7E66, alpha: 0.5))
        c.restoreGState()
    }

    private static func rearSilhouette(_ c: CGContext, frame: SceneFrame) {
        let top: CGFloat = 425 + frame.standing * 60 - frame.slacking * 10
        // Resource failure must never reintroduce the former face-facing figure.
        round(c, CGRect(x: 554, y: top - 180, width: 92, height: 102), 27, color(0x8BAA91))
        ellipse(c, CGRect(x: 547, y: top - 95, width: 106, height: 102), color(0x51493F))
        ellipse(c, CGRect(x: 565, y: top - 131, width: 70, height: 53), color(0x9BB69A))
        line(c, [CGPoint(x: 581, y: 248), CGPoint(x: 577, y: 138)], color(0x48576A), width: 20)
        line(c, [CGPoint(x: 619, y: 248), CGPoint(x: 623, y: 138)], color(0x48576A), width: 20)
        round(c, CGRect(x: 559, y: 125, width: 32, height: 17), 6, color(0xEEE2C6))
        round(c, CGRect(x: 609, y: 125, width: 32, height: 17), 6, color(0xEEE2C6))
    }

    private static func captions(_ c: CGContext, snapshot: SceneSnapshot) {
        text("YOUR LITTLE WORKPLACE", CGPoint(x: 99, y: 790), size: 10, color: secondary, weight: .medium)
        let caption: String
        switch snapshot.resolvedActivity() {
        case .working: caption = snapshot.resolvedPose() == .standing ? "站起来，也继续专注。" : "把今天的进展，交给这个背影。"
        case .waiting: caption = "准备好了，等你回来。"
        case .resting: caption = "稍微摸会儿鱼，也没关系。"
        case .offline: caption = "工位休息中，欢迎随时回来。"
        }
        text(caption, CGPoint(x: 99, y: 761), size: 19, color: ink, weight: .medium)
        text(String(format: "%02d", snapshot.tasks.count), CGPoint(x: 1030, y: 775), size: 28, color: ink, weight: .light)
        text("个模拟会话", CGPoint(x: 1018, y: 757), size: 9, color: secondary)
        let footer = snapshot.demoRunning && snapshot.isFresh()
            ? "演示正在进行 · 每 60 秒循环" : "屏幕里是进展，屏幕前是你。"
        text(footer, CGPoint(x: 458, y: 38), size: 11, color: secondary)
    }
}
