import SwiftUI

/// The drill is drawn in one place so the home screen, the shop preview and the
/// run all show the exact same machine — including upgrade attachments.
///
/// Everything is authored in local metres around the body centre, and lit from
/// the top left: highlights go on upper-left edges, core shadow on lower-right.
enum DrillArt {

    static let bodyHalfWidth = 0.62
    static let bitTipY = 1.35

    /// - Parameters:
    ///   - context: drawn into as-is; the function scopes its own transforms.
    ///   - center: screen point of the drill *body* centre.
    ///   - scale: screen points per world metre.
    ///   - spin: accumulated bit rotation.
    ///   - tilt: -1 ... 1 steering lean.
    ///   - heading: radians the bit is turned from straight down.
    static func draw(in context: GraphicsContext,
                     center: CGPoint,
                     scale: CGFloat,
                     spin: Double,
                     tilt: Double,
                     heading: Double = 0,
                     levels: UpgradeLevels,
                     skin: DrillSkin,
                     build: ShipBuild = .standard,
                     damageFlash: Double = 0,
                     working: Bool = false,
                     headlight: Bool = true,
                     reduceMotion: Bool = false) {
        var ctx = context
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: .radians(heading + tilt * 9 * .pi / 180))
        ctx.scaleBy(x: scale, y: scale)

        if headlight { drawHeadlightCone(ctx, working: working, spin: spin, reduceMotion: reduceMotion) }

        if damageFlash > 0.01 {
        }

        drawGroundShadow(ctx)
        if build.tracks == .echoWings { drawWings(ctx, spin: spin, working: working, reduceMotion: reduceMotion) }
        if build.bit == .twinAuger {
            // Two narrower augers side by side.
            for side in [-1.0, 1.0] {
                var auger = ctx
                auger.translateBy(x: side * 0.28, y: 0)
                auger.scaleBy(x: 0.56, y: 0.92)
                drawBit(auger, spin: spin + side, power: levels.power, skin: skin, part: .standardBit,
                        reduceMotion: reduceMotion)
            }
        } else {
            drawBit(ctx, spin: spin, power: levels.power, skin: skin, part: build.bit, reduceMotion: reduceMotion)
            if build.bit == .voidDrill {
                // Stars glinting in the void-metal.
                for (k, spot) in [CGPoint(x: -0.12, y: 0.7), CGPoint(x: 0.14, y: 0.92), CGPoint(x: -0.02, y: 1.15)].enumerated() {
                    let twinkle = reduceMotion ? 0.8 : 0.5 + 0.5 * sin(spin * 0.3 + Double(k) * 2)
                    let star = Shapes.spikePath(center: spot, radius: 0.08, points: 4, inner: 0.35, angle: 0)
                    ctx.fill(star, with: .color(Palette.starlight.opacity(twinkle)))
                }
            }
        }
        let treadColor: Color? = build.tracks == .sportTracks ? Palette.window
            : (build.tracks == .overclockTreads ? Palette.hazard : (build.tracks == .frostRunners ? Palette.frost : nil))
        if build.tracks == .hoverSkids {
            drawSkid(ctx, side: -1, spin: spin, working: working, reduceMotion: reduceMotion)
            drawSkid(ctx, side: 1, spin: spin, working: working, reduceMotion: reduceMotion)
        } else {
            drawTrack(ctx, side: -1, armor: levels.armor, spin: spin, tread: treadColor, reduceMotion: reduceMotion)
            drawTrack(ctx, side: 1, armor: levels.armor, spin: spin, tread: treadColor, reduceMotion: reduceMotion)
        }
        if build.tracks == .overclockTreads { drawOverclockVents(ctx, working: working, spin: spin, reduceMotion: reduceMotion) }
        if build.tracks == .frostRunners { drawRunners(ctx) }
        drawModule(ctx, build.module, spin: spin, reduceMotion: reduceMotion)
        drawFuelCanister(ctx, level: levels.fuel)
        drawCargoCrate(ctx, level: build.hull == .cargoHull ? 6 : levels.cargo, wide: build.hull == .cargoHull)
        drawExhaust(ctx, working: working)
        drawBody(ctx, skin: skin, light: build.hull == .lightFrame)
        if build.hull == .carapace { drawCarapace(ctx) }
        if build.hull == .heatShield { drawHeatShield(ctx, spin: spin, reduceMotion: reduceMotion) }
        if build.hull == .bulwarkHull { drawBulwark(ctx) }
        if build.hull == .pharaohShroud { drawShroud(ctx) }
        drawArmorPlating(ctx, level: levels.armor)
        drawCabin(ctx, skin: skin, working: working)

        if damageFlash > 0.01 { drawDamage(ctx, amount: damageFlash) }
    }

    // MARK: - Light

    private static func drawHeadlightCone(_ ctx: GraphicsContext, working: Bool,
                                          spin: Double, reduceMotion: Bool) {
        let flicker = reduceMotion ? 1.0 : 0.93 + 0.07 * sin(spin * 3.1)
        let strength = (working ? 0.22 : 0.1) * flicker
        var beam = ctx
        beam.blendMode = .plusLighter
        let cone = Blob.chunky([CGPoint(x: -0.26, y: 0.3),
                                CGPoint(x: 0.26, y: 0.3),
                                CGPoint(x: 1.9, y: 4.2),
                                CGPoint(x: -1.9, y: 4.2)], rounding: 0.4)
        // Two stacked flat wedges: a posterised beam, not an airbrushed one.
        beam.fill(cone, with: .color(Palette.gold.opacity(strength * 0.22)))
        beam.fill(cone.applying(CGAffineTransform(scaleX: 0.6, y: 0.75)), with: .color(Palette.gold.opacity(strength * 0.18)))
        // Warm pool right at the bit.
        beam.fill(Path(ellipseIn: CGRect(x: -0.6, y: 0.62, width: 1.2, height: 1.2)), with: .color(Palette.gold.opacity(strength * 0.3)))
    }

    // MARK: - Pieces

    private static func drawGroundShadow(_ ctx: GraphicsContext) {
        ctx.fill(Path(ellipseIn: CGRect(x: -0.74, y: 0.24, width: 1.48, height: 0.46)), with: .color(Palette.ink.opacity(0.3)))
    }

    private static func drawBody(_ ctx: GraphicsContext, skin: DrillSkin, light: Bool = false) {
        let rect = CGRect(x: -bodyHalfWidth, y: -0.52, width: bodyHalfWidth * 2, height: 0.98)
        let body = Path(roundedRect: rect, cornerRadius: 0.26)
        ctx.fill(body, with: .color(skin.body))

        var inner = ctx
        inner.clip(to: body)

        // Core shadow along the bottom, lit bevel along the top.
        inner.fill(Path(CGRect(x: -0.7, y: 0.18, width: 1.4, height: 0.5)),
                   with: .color(skin.shadow))
        inner.fill(Path(CGRect(x: -0.7, y: -0.56, width: 1.4, height: 0.13)),
                   with: .color(.white.opacity(0.2)))
        inner.fill(Path(CGRect(x: 0.4, y: -0.6, width: 0.34, height: 1.2)),
                   with: .color(.black.opacity(0.07)))

        if light {
            // Light Frame: racing stripe and lightening holes instead of chevrons.
            inner.fill(Path(CGRect(x: -0.09, y: -0.6, width: 0.18, height: 1.2)),
                       with: .color(.white.opacity(0.75)))
            for holeY in [-0.3, 0.0, 0.28] {
                for side in [-1.0, 1.0] {
                    inner.fill(Path(ellipseIn: CGRect(x: side * 0.38 - 0.07, y: holeY - 0.07, width: 0.14, height: 0.14)),
                               with: .color(Palette.track.opacity(0.85)))
                }
            }
            Ink.outline(ctx, body, width: 0.055)
            return
        }

        // Hazard chevrons across the waist — the industrial signature.
        var stripes = inner
        let band = CGRect(x: -0.7, y: -0.08, width: 1.4, height: 0.2)
        stripes.clip(to: Path(band))
        stripes.fill(Path(band), with: .color(skin.shadow.opacity(0.75)))
        var x = -0.78
        while x < 0.72 {
            stripes.fill(Blob.chunky([CGPoint(x: x, y: -0.1),
                                      CGPoint(x: x + 0.1, y: -0.1),
                                      CGPoint(x: x - 0.09, y: 0.14),
                                      CGPoint(x: x - 0.19, y: 0.14)], rounding: 0.03),
                         with: .color(Palette.track.opacity(0.85)))
            x += 0.24
        }

        // Plate seams and rivet rows.
        for seamX in [-0.26, 0.26] {
            inner.fill(Path(CGRect(x: seamX, y: -0.56, width: 0.022, height: 1.1)),
                       with: .color(.black.opacity(0.16)))
        }
        for rivetX in stride(from: -0.46, through: 0.46, by: 0.23) {
            for rivetY in [-0.44, 0.36] {
                inner.fill(Path(ellipseIn: CGRect(x: rivetX - 0.028, y: rivetY - 0.028,
                                                  width: 0.056, height: 0.056)),
                           with: .color(.black.opacity(0.22)))
                inner.fill(Path(ellipseIn: CGRect(x: rivetX - 0.028, y: rivetY - 0.04,
                                                  width: 0.045, height: 0.045)),
                           with: .color(.white.opacity(0.22)))
            }
        }

        // Small maker's plate.
        inner.fill(Path(roundedRect: CGRect(x: -0.5, y: -0.36, width: 0.2, height: 0.11),
                        cornerRadius: 0.035),
                   with: .color(.black.opacity(0.2)))

        Ink.outline(ctx, body, width: 0.055)
    }

    private static func drawCabin(_ ctx: GraphicsContext, skin: DrillSkin, working: Bool) {
        let cabin = Path(roundedRect: CGRect(x: -0.33, y: -0.9, width: 0.66, height: 0.52),
                         cornerRadius: 0.22)
        ctx.fill(cabin, with: .color(skin.body))
        var frame = ctx
        frame.clip(to: cabin)
        frame.fill(Path(CGRect(x: -0.4, y: -0.52, width: 0.8, height: 0.2)),
                   with: .color(skin.shadow))
        frame.fill(Path(CGRect(x: -0.4, y: -0.93, width: 0.8, height: 0.08)),
                   with: .color(.white.opacity(0.22)))
        Ink.outline(ctx, cabin, width: 0.055)

        // Glass: darker lower half, bright diagonal reflection, inner frame.
        let window = Path(roundedRect: CGRect(x: -0.235, y: -0.825, width: 0.47, height: 0.33),
                          cornerRadius: 0.12)
        ctx.fill(window, with: .color(skin.window))
        var glass = ctx
        glass.clip(to: window)
        glass.fill(Path(CGRect(x: -0.3, y: -0.63, width: 0.6, height: 0.2)),
                   with: .color(.black.opacity(0.18)))
        glass.fill(Blob.chunky([CGPoint(x: -0.3, y: -0.85),
                                CGPoint(x: -0.06, y: -0.85),
                                CGPoint(x: -0.2, y: -0.47),
                                CGPoint(x: -0.34, y: -0.47)], rounding: 0.05),
                   with: .color(.white.opacity(0.4)))
        glass.fill(Blob.chunky([CGPoint(x: 0.02, y: -0.85),
                                CGPoint(x: 0.1, y: -0.85),
                                CGPoint(x: -0.04, y: -0.47),
                                CGPoint(x: -0.12, y: -0.47)], rounding: 0.05),
                   with: .color(.white.opacity(0.22)))
        ctx.stroke(window, with: .color(Palette.ink), lineWidth: 0.035)

        // Roof beacon, lit while the bit is turning.
        let beacon = Path(roundedRect: CGRect(x: 0.14, y: -0.99, width: 0.13, height: 0.12),
                          cornerRadius: 0.055)
        if working {
            Ink.halo(ctx, center: CGPoint(x: 0.205, y: -0.93), radius: 0.18, color: Palette.hazard, strength: 2)
        }
        ctx.fill(beacon, with: .color(working ? Palette.hazard : Palette.hazardShadow))
        ctx.fill(Path(ellipseIn: CGRect(x: 0.16, y: -0.97, width: 0.05, height: 0.05)),
                 with: .color(.white.opacity(0.6)))

        // Headlight housing under the cabin lip.
        let lamp = Path(roundedRect: CGRect(x: -0.1, y: -0.46, width: 0.2, height: 0.1),
                        cornerRadius: 0.045)
        ctx.fill(lamp, with: .color(Palette.drillBit))
        ctx.fill(Path(roundedRect: CGRect(x: -0.075, y: -0.44, width: 0.15, height: 0.06),
                      cornerRadius: 0.03),
                 with: .color(Palette.gold))
    }

    private static func drawTrack(_ ctx: GraphicsContext, side: Double, armor: Int,
                                  spin: Double, tread: Color? = nil, reduceMotion: Bool) {
        let centerX = side * 0.82
        let halfWidth = 0.17
        let belt = Path(roundedRect: CGRect(x: centerX - halfWidth, y: -0.46,
                                            width: halfWidth * 2, height: 1.08),
                        cornerRadius: halfWidth)
        ctx.fill(belt, with: .color(Palette.track))

        var inner = ctx
        inner.clip(to: belt)

        // Tread blocks ride the outer edge and scroll with the machine.
        let offset = reduceMotion ? 0 : (spin * 0.05).truncatingRemainder(dividingBy: 0.17)
        var blockY = -0.52 + offset
        while blockY < 0.62 {
            inner.fill(Path(roundedRect: CGRect(x: centerX - halfWidth - 0.02, y: blockY,
                                                width: halfWidth * 2 + 0.04, height: 0.085),
                            cornerRadius: 0.03),
                       with: .color(tread ?? Palette.trackBlock))
            inner.fill(Path(CGRect(x: centerX - halfWidth, y: blockY,
                                   width: halfWidth * 2, height: 0.025)),
                       with: .color(.white.opacity(0.14)))
            blockY += 0.17
        }

        // Sprockets at each end, road wheels between — lighter than the belt
        // so the running gear actually reads.
        for (wheelY, radius) in [(-0.27, 0.115), (0.43, 0.115), (0.02, 0.07), (0.22, 0.07)] {
            let hub = CGRect(x: centerX - radius, y: wheelY - radius,
                             width: radius * 2, height: radius * 2)
            inner.fill(Path(ellipseIn: hub), with: .color(Palette.trackWheel))
            inner.fill(Path(ellipseIn: hub.insetBy(dx: radius * 0.42, dy: radius * 0.42)),
                       with: .color(Palette.track))
            inner.stroke(Path(ellipseIn: hub), with: .color(.black.opacity(0.4)), lineWidth: 0.028)
        }
        // Inner guide rail.
        inner.fill(Path(roundedRect: CGRect(x: centerX - 0.035, y: -0.2,
                                            width: 0.07, height: 0.58),
                        cornerRadius: 0.035),
                   with: .color(Palette.trackWheel.opacity(0.55)))

        Ink.outline(ctx, belt, width: 0.05)

        if armor >= 3 {
            let plate = Path(roundedRect: CGRect(x: centerX - 0.15, y: 0.04,
                                                 width: 0.3, height: 0.28),
                             cornerRadius: 0.1)
            ctx.fill(plate, with: .color(Palette.drillBitShadow))
            ctx.fill(Path(roundedRect: CGRect(x: centerX - 0.15, y: 0.04,
                                              width: 0.3, height: 0.085),
                          cornerRadius: 0.042),
                     with: .color(Palette.drillBit))
            ctx.stroke(plate, with: .color(Palette.ink), lineWidth: 0.035)
        }
    }

    private static func drawBit(_ ctx: GraphicsContext, spin: Double, power: Int,
                                skin: DrillSkin, part: ShipPart = .standardBit, reduceMotion: Bool) {
        var halfWidth = 0.5 + Double(power) * 0.022
        var tip = bitTipY + Double(power) * 0.05
        var metal = skin.bit
        switch part {
        case .heavyBit: halfWidth += 0.12; tip -= 0.08; metal = Palette.drillBitShadow
        case .needleBit: halfWidth *= 0.62; tip += 0.3
        case .queenFang: halfWidth += 0.06; tip += 0.1; metal = Palette.wormBelly
        case .voidDrill: halfWidth += 0.05; tip += 0.12; metal = Palette.imp
        case .glassCannon: halfWidth += 0.04; tip += 0.12; metal = Palette.window.opacity(0.55)
        default: break
        }
        if part == .queenFang {
            // Curved fangs flanking the cone.
            for side in [-1.0, 1.0] {
                var fang = Path()
                fang.move(to: CGPoint(x: side * (halfWidth - 0.05), y: 0.3))
                fang.addQuadCurve(to: CGPoint(x: side * (halfWidth * 0.35), y: tip * 0.82),
                                  control: CGPoint(x: side * (halfWidth + 0.25), y: tip * 0.6))
                fang.addLine(to: CGPoint(x: side * (halfWidth * 0.62), y: 0.3))
                fang.closeSubpath()
                ctx.fill(fang, with: .color(.white))
                ctx.stroke(fang, with: .color(Palette.ink), lineWidth: 0.04)
            }
        }
        let bit = Blob.chunky([CGPoint(x: -halfWidth, y: 0.3),
                               CGPoint(x: halfWidth, y: 0.3),
                               CGPoint(x: 0, y: tip)], rounding: 0.09)
        ctx.fill(bit, with: .color(metal))

        var flutes = ctx
        flutes.clip(to: bit)
        // Helical flutes: curved bands sliding sideways read as rotation.
        let bands = 4
        let offset = reduceMotion ? 0 : spin * 0.1
        for index in 0..<bands {
            let t = (Double(index) / Double(bands) + offset).truncatingRemainder(dividingBy: 1)
            let x = -halfWidth * 1.4 + t * halfWidth * 2.8
            var flute = Path()
            flute.move(to: CGPoint(x: x, y: 0.26))
            flute.addQuadCurve(to: CGPoint(x: x + 0.3, y: tip + 0.12),
                               control: CGPoint(x: x + 0.02, y: tip * 0.6))
            flute.addLine(to: CGPoint(x: x + 0.46, y: tip + 0.12))
            flute.addQuadCurve(to: CGPoint(x: x + 0.16, y: 0.26),
                               control: CGPoint(x: x + 0.18, y: tip * 0.6))
            flute.closeSubpath()
            flutes.fill(flute, with: .color((part == .queenFang ? Palette.worm : Palette.drillBitShadow).opacity(0.8)))
            flutes.stroke(flute, with: .color(.black.opacity(0.14)), lineWidth: 0.02)
        }
        // Lit left edge and a dark right edge give the cone volume.
        flutes.fill(Blob.chunky([CGPoint(x: -halfWidth, y: 0.3),
                                 CGPoint(x: -halfWidth * 0.55, y: 0.3),
                                 CGPoint(x: 0, y: tip)], rounding: 0.1),
                    with: .color(.white.opacity(0.26)))
        flutes.fill(Blob.chunky([CGPoint(x: halfWidth * 0.55, y: 0.3),
                                 CGPoint(x: halfWidth, y: 0.3),
                                 CGPoint(x: 0, y: tip)], rounding: 0.1),
                    with: .color(.black.opacity(0.14)))
        Ink.outline(ctx, bit, width: 0.055)

        // Collar with bolts, thicker as Power goes up.
        let collarHeight = 0.14 + Double(power) * 0.012
        let collar = Path(roundedRect: CGRect(x: -halfWidth - 0.05, y: 0.22,
                                              width: halfWidth * 2 + 0.1, height: collarHeight),
                          cornerRadius: collarHeight / 2)
        ctx.fill(collar, with: .color(part == .queenFang ? Palette.worm : Palette.drillBit))
        ctx.fill(Path(roundedRect: CGRect(x: -halfWidth - 0.05, y: 0.22,
                                          width: halfWidth * 2 + 0.1, height: collarHeight * 0.4),
                      cornerRadius: collarHeight * 0.2),
                 with: .color(.white.opacity(0.3)))
        for boltX in stride(from: -halfWidth + 0.08, through: halfWidth - 0.08, by: 0.19) {
            ctx.fill(Path(ellipseIn: CGRect(x: boltX - 0.03, y: 0.25,
                                            width: 0.06, height: 0.06)),
                     with: .color(Palette.drillBitShadow))
        }
        ctx.stroke(collar, with: .color(Palette.ink), lineWidth: 0.04)

        if part == .glassCannon {
            // Cracked glass: a few bright fracture lines and glints.
            var cracks = ctx
            cracks.clip(to: bit)
            cracks.stroke(Blob.fissures(center: CGPoint(x: 0, y: (0.3 + tip) / 2), radius: halfWidth, count: 3, seed: 41),
                          with: .color(.white.opacity(0.8)), lineWidth: 0.025)
            Ink.shine(ctx, at: CGPoint(x: 0.12, y: tip - 0.5), size: 0.22 * 0.9, opacity: 0.9)
        }
        if power >= 4 {
            Ink.shine(ctx, at: CGPoint(x: -0.13, y: tip - 0.42), size: 0.2 * 0.9, opacity: 0.8)
        }
    }

    private static func drawExhaust(_ ctx: GraphicsContext, working: Bool) {
        let pipe = Path(roundedRect: CGRect(x: -0.36, y: -1.12, width: 0.18, height: 0.38),
                        cornerRadius: 0.06)
        ctx.fill(pipe, with: .color(Palette.exhaust))
        ctx.stroke(pipe, with: .color(Palette.ink), lineWidth: 0.04)
        ctx.fill(Path(CGRect(x: -0.36, y: -1.12, width: 0.06, height: 0.38)),
                 with: .color(.white.opacity(0.25)))
        // Collar rings and a dark mouth.
        for ringY in [-1.0, -0.88] {
            ctx.fill(Path(roundedRect: CGRect(x: -0.39, y: ringY, width: 0.24, height: 0.05),
                          cornerRadius: 0.025),
                     with: .color(Palette.drillShadow))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: -0.355, y: -1.145, width: 0.17, height: 0.075)),
                 with: .color(.black.opacity(working ? 0.55 : 0.35)))
    }

    private static func drawFuelCanister(_ ctx: GraphicsContext, level: Int) {
        guard level > 0 else { return }
        let height = 0.16 + Double(min(level, 5)) * 0.045
        let rect = CGRect(x: -0.62, y: -0.52 - height, width: 0.28, height: height + 0.06)
        let can = Path(roundedRect: rect, cornerRadius: 0.06)
        ctx.fill(can, with: .color(Palette.mint))
        var inner = ctx
        inner.clip(to: can)
        inner.fill(Path(CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height)),
                   with: .color(Palette.mintShadow))
        inner.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: 0.06, height: rect.height)),
                   with: .color(.white.opacity(0.28)))
        // Sight glass showing the level.
        inner.fill(Path(roundedRect: CGRect(x: rect.midX - 0.03, y: rect.minY + 0.05,
                                            width: 0.06, height: height * 0.6),
                        cornerRadius: 0.025),
                   with: .color(Palette.textPrimary.opacity(0.5)))
        ctx.stroke(can, with: .color(Palette.ink), lineWidth: 0.04)
        // Filler cap.
        ctx.fill(Path(roundedRect: CGRect(x: rect.minX + 0.05, y: rect.minY - 0.05,
                                          width: 0.1, height: 0.07),
                      cornerRadius: 0.03),
                 with: .color(Palette.mintShadow))
    }

    private static func drawCargoCrate(_ ctx: GraphicsContext, level: Int, wide: Bool = false) {
        guard level > 0 else { return }
        let height = 0.15 + Double(min(level, 6)) * 0.05
        let rect = wide
            ? CGRect(x: 0.2, y: -0.5 - height, width: 0.5, height: height + 0.06)
            : CGRect(x: 0.34, y: -0.5 - height, width: 0.3, height: height + 0.06)
        let crate = Path(roundedRect: rect, cornerRadius: 0.05)
        ctx.fill(crate, with: .color(Palette.crate))
        var inner = ctx
        inner.clip(to: crate)
        // Timber planks and iron banding.
        var plankY = rect.minY + 0.06
        while plankY < rect.maxY {
            inner.fill(Path(CGRect(x: rect.minX, y: plankY, width: rect.width, height: 0.02)),
                       with: .color(.black.opacity(0.22)))
            plankY += 0.11
        }
        inner.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 0.05)),
                   with: .color(.white.opacity(0.16)))
        inner.fill(Path(CGRect(x: rect.midX - 0.03, y: rect.minY,
                               width: 0.06, height: rect.height)),
                   with: .color(Palette.drillShadow.opacity(0.9)))
        ctx.stroke(crate, with: .color(Palette.ink), lineWidth: 0.04)
        if level >= 3 {
            ctx.fill(Path(ellipseIn: CGRect(x: rect.minX + 0.04, y: rect.minY - 0.06,
                                            width: 0.09, height: 0.09)),
                     with: .color(Palette.gold))
            Ink.shine(ctx, at: CGPoint(x: rect.maxX - 0.07, y: rect.minY + 0.05), size: 0.1 * 0.9, opacity: 0.9)
        }
    }

    private static func drawArmorPlating(_ ctx: GraphicsContext, level: Int) {
        guard level > 0 else { return }
        let bumper = Path(roundedRect: CGRect(x: -0.56, y: 0.2, width: 1.12, height: 0.28),
                          cornerRadius: 0.11)
        ctx.fill(bumper, with: .color(Palette.drillBitShadow))
        var inner = ctx
        inner.clip(to: bumper)
        inner.fill(Path(CGRect(x: -0.6, y: 0.2, width: 1.2, height: 0.09)),
                   with: .color(Palette.drillBit))
        inner.fill(Path(CGRect(x: -0.6, y: 0.4, width: 1.2, height: 0.1)),
                   with: .color(Palette.track.opacity(0.4)))
        let bolts = min(level, 4) + 1
        for index in 0..<bolts {
            let x = -0.42 + Double(index) * (0.84 / Double(max(bolts - 1, 1)))
            inner.fill(Path(ellipseIn: CGRect(x: x - 0.045, y: 0.29, width: 0.09, height: 0.09)),
                       with: .color(Palette.track.opacity(0.7)))
            inner.fill(Path(ellipseIn: CGRect(x: x - 0.032, y: 0.295, width: 0.064, height: 0.064)),
                       with: .color(Palette.drillBit))
        }
        ctx.stroke(bumper, with: .color(Palette.ink), lineWidth: 0.045)
    }

    // MARK: - Garage parts

    /// Beetle shell plates over the hull.
    private static func drawCarapace(_ ctx: GraphicsContext) {
        for side in [-1.0, 1.0] {
            let plate = Blob.chunky([CGPoint(x: side * 0.03, y: -0.5),
                                     CGPoint(x: side * 0.64, y: -0.36),
                                     CGPoint(x: side * 0.66, y: 0.3),
                                     CGPoint(x: side * 0.03, y: 0.44)], rounding: 0.18)
            ctx.fill(plate, with: .color(Palette.beetle))
            var sheen = ctx
            sheen.clip(to: plate)
            sheen.fill(Path(ellipseIn: CGRect(x: side < 0 ? -0.52 : 0.14, y: -0.4, width: 0.26, height: 0.5)),
                       with: .color(Palette.beetleSheen.opacity(0.55)))
            ctx.stroke(plate, with: .color(Palette.ink), lineWidth: 0.045)
        }
    }

    /// Frost Runners: ice-skate blades along each track, with frosted tips.
    private static func drawRunners(_ ctx: GraphicsContext) {
        for side in [-1.0, 1.0] {
            let blade = Path(roundedRect: CGRect(x: side * 0.98 - 0.05, y: -0.55, width: 0.1, height: 1.15), cornerRadius: 0.05)
            ctx.fill(blade, with: .color(Palette.wisp))
            ctx.stroke(blade, with: .color(Palette.ink), lineWidth: 0.035)
            let tip = Shapes.spikePath(center: CGPoint(x: side * 0.98, y: 0.62), radius: 0.12, points: 6, inner: 0.4, angle: 0)
            ctx.fill(tip, with: .color(Palette.frost))
        }
    }

    /// Linen wrappings over the hull, held by a gold and lapis collar.
    private static func drawShroud(_ ctx: GraphicsContext) {
        let shell = Path(roundedRect: CGRect(x: -0.6, y: -0.48, width: 1.2, height: 0.9), cornerRadius: 0.24)
        ctx.fill(shell, with: .color(Palette.wraith))
        var inner = ctx
        inner.clip(to: shell)
        for k in 0..<5 {
            var band = Path()
            let y = -0.4 + Double(k) * 0.2
            band.move(to: CGPoint(x: -0.7, y: y + 0.08))
            band.addLine(to: CGPoint(x: 0.7, y: y - 0.06))
            inner.stroke(band, with: .color(Palette.wraithShadow), lineWidth: 0.035)
        }
        let collar = Path(roundedRect: CGRect(x: -0.62, y: -0.5, width: 1.24, height: 0.2), cornerRadius: 0.08)
        ctx.fill(collar, with: .color(Palette.pharaoh))
        for k in 0..<5 {
            ctx.fill(Path(CGRect(x: -0.5 + Double(k) * 0.22, y: -0.5, width: 0.08, height: 0.2)), with: .color(Palette.lapis))
        }
        ctx.stroke(collar, with: .color(Palette.ink), lineWidth: 0.04)
        ctx.stroke(shell, with: .color(Palette.ink), lineWidth: 0.045)
    }

    /// Riveted steel slabs bolted over the hull.
    private static func drawBulwark(_ ctx: GraphicsContext) {
        for (index, rect) in [CGRect(x: -0.6, y: -0.46, width: 1.2, height: 0.42),
                              CGRect(x: -0.6, y: 0.0, width: 1.2, height: 0.42)].enumerated() {
            let slab = Path(roundedRect: rect, cornerRadius: 0.1)
            ctx.fill(slab, with: .color(index == 0 ? Palette.drillBit : Palette.drillBitShadow))
            ctx.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 0.07)),
                     with: .color(Palette.shine.opacity(0.35)))
            for x in stride(from: rect.minX + 0.1, through: rect.maxX - 0.1, by: 0.25) {
                ctx.fill(Path(ellipseIn: CGRect(x: x - 0.03, y: rect.midY - 0.03, width: 0.06, height: 0.06)),
                         with: .color(Palette.ink.opacity(0.55)))
            }
            ctx.stroke(slab, with: .color(Palette.ink), lineWidth: 0.045)
        }
    }

    /// Hover Skids: a sled runner with a thruster glow underneath.
    private static func drawSkid(_ ctx: GraphicsContext, side: Double, spin: Double, working: Bool,
                                 reduceMotion: Bool) {
        let x = side * 0.82
        let flicker = reduceMotion ? 1 : 0.85 + 0.15 * sin(spin * 1.3 + side)
        Ink.halo(ctx, center: CGPoint(x: x, y: 0.1), radius: 0.32 * flicker, color: Palette.window,
                 strength: working ? 2 : 1.2, aspect: 1.6)
        let skid = Path(roundedRect: CGRect(x: x - 0.12, y: -0.5, width: 0.24, height: 1.1), cornerRadius: 0.12)
        ctx.fill(skid, with: .color(Palette.trackWheel))
        ctx.fill(Path(roundedRect: CGRect(x: x - 0.06, y: -0.38, width: 0.12, height: 0.86), cornerRadius: 0.06),
                 with: .color(Palette.window.opacity(0.85)))
        ctx.stroke(skid, with: .color(Palette.ink), lineWidth: 0.045)
    }

    /// Molten-orange plating with glowing seams.
    private static func drawHeatShield(_ ctx: GraphicsContext, spin: Double, reduceMotion: Bool) {
        let shell = Path(roundedRect: CGRect(x: -0.6, y: -0.48, width: 1.2, height: 0.9), cornerRadius: 0.24)
        ctx.fill(shell, with: .color(Palette.lavaCrust))
        var inner = ctx
        inner.clip(to: shell)
        let glow = reduceMotion ? 0.8 : 0.6 + 0.3 * sin(spin * 0.25)
        for y in [-0.22, 0.04, 0.28] {
            inner.fill(Path(CGRect(x: -0.7, y: y, width: 1.4, height: 0.05)), with: .color(Palette.lava.opacity(glow)))
        }
        inner.fill(Path(CGRect(x: -0.7, y: -0.5, width: 1.4, height: 0.12)), with: .color(Palette.lavaGlow.opacity(0.35)))
        ctx.stroke(shell, with: .color(Palette.ink), lineWidth: 0.05)
    }

    /// Exhaust vents on the tracks that spit flame while drilling.
    private static func drawOverclockVents(_ ctx: GraphicsContext, working: Bool, spin: Double, reduceMotion: Bool) {
        for side in [-1.0, 1.0] {
            let vent = Path(roundedRect: CGRect(x: side * 0.82 - 0.09, y: -0.62, width: 0.18, height: 0.14), cornerRadius: 0.04)
            ctx.fill(vent, with: .color(Palette.track))
            guard working else { continue }
            let lick = reduceMotion ? 0.2 : 0.16 + 0.1 * abs(sin(spin * 0.8 + side))
            var flame = Path()
            flame.move(to: CGPoint(x: side * 0.82 - 0.07, y: -0.62))
            flame.addQuadCurve(to: CGPoint(x: side * 0.82, y: -0.62 - lick * 2), control: CGPoint(x: side * 0.82 - 0.1, y: -0.62 - lick))
            flame.addQuadCurve(to: CGPoint(x: side * 0.82 + 0.07, y: -0.62), control: CGPoint(x: side * 0.82 + 0.1, y: -0.62 - lick))
            ctx.fill(flame, with: .color(Palette.exhaust))
        }
    }

    /// Bat membrane wings behind the tracks; they beat while drilling.
    private static func drawWings(_ ctx: GraphicsContext, spin: Double, working: Bool, reduceMotion: Bool) {
        let flap = reduceMotion ? 0.5 : (sin(spin * (working ? 0.9 : 0.3)) + 1) / 2
        for side in [-1.0, 1.0] {
            var wing = Path()
            wing.move(to: CGPoint(x: side * 0.7, y: -0.4))
            wing.addLine(to: CGPoint(x: side * (1.45 + 0.1 * flap), y: -0.75 + 0.35 * flap))
            wing.addQuadCurve(to: CGPoint(x: side * 1.2, y: 0.05),
                              control: CGPoint(x: side * 1.5, y: -0.2))
            wing.addQuadCurve(to: CGPoint(x: side * 0.95, y: 0.15),
                              control: CGPoint(x: side * 1.05, y: -0.05))
            wing.addQuadCurve(to: CGPoint(x: side * 0.72, y: 0.3),
                              control: CGPoint(x: side * 0.8, y: 0.05))
            wing.closeSubpath()
            ctx.fill(wing, with: .color(Palette.batWing))
            ctx.stroke(wing, with: .color(Palette.ink), lineWidth: 0.045)
        }
    }

    /// The module sits on the rear deck, behind the cabin.
    private static func drawModule(_ ctx: GraphicsContext, _ part: ShipPart, spin: Double, reduceMotion: Bool) {
        let center = CGPoint(x: 0.08, y: -1.12)
        switch part {
        case .magnetCoil:
            var horseshoe = Path()
            horseshoe.addArc(center: center, radius: 0.18, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            ctx.stroke(horseshoe, with: .color(Palette.hazard), style: StrokeStyle(lineWidth: 0.12, lineCap: .butt))
            for side in [-1.0, 1.0] {
                ctx.fill(Path(CGRect(x: center.x + side * 0.18 - 0.06, y: center.y - 0.12, width: 0.12, height: 0.1)),
                         with: .color(Palette.drillBit))
            }
        case .fuelRecycler:
            let tank = Path(roundedRect: CGRect(x: center.x - 0.17, y: center.y - 0.14, width: 0.34, height: 0.3),
                            cornerRadius: 0.08)
            ctx.fill(tank, with: .color(Palette.mint))
            var arrows = Path()
            arrows.addArc(center: CGPoint(x: center.x, y: center.y + 0.01), radius: 0.08,
                          startAngle: .degrees(-30), endAngle: .degrees(240), clockwise: false)
            ctx.stroke(arrows, with: .color(.white.opacity(0.85)), lineWidth: 0.035)
            ctx.stroke(tank, with: .color(Palette.ink), lineWidth: 0.04)
        case .abyssLantern:
            // A ship's lantern on a hook, glowing abyss-green.
            var hook = Path()
            hook.move(to: CGPoint(x: center.x - 0.12, y: center.y + 0.12))
            hook.addLine(to: CGPoint(x: center.x - 0.12, y: center.y - 0.22))
            hook.addLine(to: CGPoint(x: center.x + 0.04, y: center.y - 0.22))
            ctx.stroke(hook, with: .color(Palette.ink), lineWidth: 0.04)
            Ink.halo(ctx, center: CGPoint(x: center.x + 0.04, y: center.y - 0.05), radius: 0.3,
                     color: Palette.abyssGlow, strength: 1.8)
            let lamp = Path(roundedRect: CGRect(x: center.x - 0.05, y: center.y - 0.17, width: 0.18, height: 0.22),
                            cornerRadius: 0.05)
            ctx.fill(lamp, with: .color(Palette.abyssGlow))
            ctx.stroke(lamp, with: .color(Palette.ink), lineWidth: 0.035)
        case .oreScanner:
            // A little radar dish on a mast, sweeping.
            let sweep = reduceMotion ? 0 : sin(spin * 0.2) * 0.35
            ctx.fill(Path(CGRect(x: center.x - 0.025, y: center.y - 0.05, width: 0.05, height: 0.2)),
                     with: .color(Palette.drillBitShadow))
            var dish = ctx
            dish.translateBy(x: center.x, y: center.y - 0.08)
            dish.rotate(by: .radians(sweep))
            let bowl = Path(ellipseIn: CGRect(x: -0.2, y: -0.11, width: 0.4, height: 0.2))
            dish.fill(bowl, with: .color(Palette.drillBit))
            dish.fill(Path(ellipseIn: CGRect(x: -0.13, y: -0.07, width: 0.26, height: 0.12)),
                      with: .color(Palette.drillBitShadow))
            dish.stroke(bowl, with: .color(Palette.ink), lineWidth: 0.035)
            dish.fill(Path(ellipseIn: CGRect(x: -0.035, y: -0.2, width: 0.07, height: 0.07)), with: .color(Palette.gold))
        case .shieldModule:
            let dome = Path(ellipseIn: CGRect(x: center.x - 0.2, y: center.y - 0.18, width: 0.4, height: 0.32))
            ctx.fill(Path(roundedRect: CGRect(x: center.x - 0.22, y: center.y + 0.04, width: 0.44, height: 0.1), cornerRadius: 0.04),
                     with: .color(Palette.drillBitShadow))
            ctx.fill(dome, with: .color(Palette.window.opacity(0.85)))
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - 0.12, y: center.y - 0.13, width: 0.1, height: 0.08)),
                     with: .color(.white.opacity(0.8)))
            ctx.stroke(dome, with: .color(Palette.ink), lineWidth: 0.035)
        case .sporeFilter:
            // A gas-mask canister with a spore-green filter window.
            let can = Path(roundedRect: CGRect(x: center.x - 0.15, y: center.y - 0.16, width: 0.3, height: 0.32), cornerRadius: 0.1)
            ctx.fill(can, with: .color(Palette.drillBitShadow))
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - 0.1, y: center.y - 0.1, width: 0.2, height: 0.2)), with: .color(Palette.spore))
            for k in 0..<3 {
                ctx.fill(Path(CGRect(x: center.x - 0.08, y: center.y - 0.06 + Double(k) * 0.05, width: 0.16, height: 0.015)),
                         with: .color(Palette.sporeShadow))
            }
            ctx.stroke(can, with: .color(Palette.ink), lineWidth: 0.035)
        case .crystalCore:
            let pulse = reduceMotion ? 1 : 0.8 + 0.2 * sin(spin * 0.3)
            Ink.halo(ctx, center: center, radius: 0.32, color: Palette.spitter, strength: 2 * pulse)
            for (lean, height) in [(-0.1, 0.26), (0.0, 0.36), (0.1, 0.24)] {
                let shard = Blob.chunky([CGPoint(x: center.x + lean - 0.07, y: center.y + 0.12),
                                         CGPoint(x: center.x + lean * 1.8, y: center.y + 0.12 - height),
                                         CGPoint(x: center.x + lean + 0.07, y: center.y + 0.12)], rounding: 0.05)
                ctx.fill(shard, with: .color(Palette.spitter))
                ctx.stroke(shard, with: .color(Palette.ink), lineWidth: 0.03)
            }
        default:
            break
        }
    }

    private static func drawDamage(_ ctx: GraphicsContext, amount: Double) {
        let body = Path(roundedRect: CGRect(x: -bodyHalfWidth, y: -0.52,
                                            width: bodyHalfWidth * 2, height: 0.98),
                        cornerRadius: 0.26)
        let cabin = Path(roundedRect: CGRect(x: -0.33, y: -0.9, width: 0.66, height: 0.52),
                         cornerRadius: 0.22)
        ctx.stroke(body, with: .color(Palette.hazard.opacity(amount)), lineWidth: 0.1)
        ctx.stroke(cabin, with: .color(Palette.hazard.opacity(amount)), lineWidth: 0.08)

        var fractures = ctx
        fractures.clip(to: body)
        fractures.stroke(Blob.fissures(center: .zero, radius: 0.6, count: 4,
                                       seed: UInt64(amount * 10_000) | 1),
                         with: .color(Palette.hazard.opacity(0.85 * amount)),
                         style: StrokeStyle(lineWidth: 0.045, lineCap: .round, lineJoin: .round))
    }
}
