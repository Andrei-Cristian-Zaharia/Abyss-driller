import SwiftUI

/// Draws one frame of the world. Pure function of `GameWorld` — it never
/// mutates the simulation.
struct GameRenderer {
    let world: GameWorld
    let size: CGSize

    var scale: CGFloat { size.width / GameWorld.shaftWidth }
    var cameraTop: Double { world.camera }
    var cameraBottom: Double { world.camera + Double(size.height / scale) }

    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: x * Double(scale), y: (y - cameraTop) * Double(scale))
    }

    func render(into context: GraphicsContext) {
        var ctx = context

        // Impact shake moves the world, never the HUD.
        if world.shake > 0.01, world.shakeScale > 0 {
            var shakeRNG = SeededRandom(seed: UInt64(world.shake * 100_000) | 1)
            let magnitude = world.shake * world.shake * 11 * world.shakeScale
            ctx.translateBy(x: shakeRNG.double(-magnitude...magnitude),
                            y: shakeRNG.double(-magnitude...magnitude))
        }

        drawStrata(ctx)
        drawDecor(ctx)
        drawChamberGlow(ctx)
        drawTrail(ctx)
        drawChambers(ctx)
        drawBestLine(ctx)
        drawLava(ctx)
        drawTrailHints(ctx)
        drawPickups(ctx)
        drawObstacles(ctx)
        drawArenaSeal(ctx)
        drawEnemies(ctx)
        drawBoss(ctx)
        drawParticles(ctx)
        drawOverdriveAura(ctx)
        drawGeysers(ctx)
        drawDrill(ctx)
        drawShieldBubble(ctx)
        drawCracks(ctx)
        drawDarkness(context)

        // Screen-space flourishes sit outside the shake transform.
        drawSpeedLines(context)
        drawPopups(context)
        drawFlying(context)
        drawShouts(context)
        drawVignettes(context)
        drawBossIntro(context)
        PaperGrain.draw(context, size: size)
    }

    /// Field Guide portrait: only the critters and boss in `world`, drawn by
    /// the same code as the run. The caller frames it with a transform.
    func drawPortrait(into context: GraphicsContext) {
        drawEnemies(context)
        drawBoss(context)
    }

    // MARK: - Ground

    private func drawStrata(_ ctx: GraphicsContext) {
        let width = Double(size.width)

        if cameraTop < 0 { drawSurface(ctx, width: width) }

        for (index, layer) in Strata.layers.enumerated() {
            let top = max(layer.startDepth, 0)
            let bottom = index + 1 < Strata.layers.count
                ? Strata.layers[index + 1].startDepth
                : max(cameraBottom + 40, top + 40)
            guard bottom > cameraTop, top < cameraBottom else { continue }

            let topY = point(0, top).y
            let bottomY = point(0, bottom).y
            let rect = CGRect(x: -40, y: topY, width: width + 80, height: bottomY - topY)
            // Flat colour, like a painted layer; texture comes from the hatching.
            ctx.fill(Path(rect), with: .color(layer.soil))
        }

        // Layer boundaries: a wavy hand-cut edge with an ink line, not a blur.
        for index in 1..<Strata.layers.count {
            let boundary = Strata.layers[index].startDepth
            guard boundary > cameraTop - 10, boundary < cameraBottom + 10 else { continue }
            let below = Strata.layers[index]
            var rng = SeededRandom(seed: UInt64(boundary) | 1)
            var edge = Path()
            let y0 = point(0, boundary).y
            edge.move(to: CGPoint(x: -20, y: y0))
            var x = -20.0
            while x < width + 20 {
                let next = x + rng.double(28...52)
                edge.addQuadCurve(to: CGPoint(x: next, y: y0 + rng.double(-9...9)),
                                  control: CGPoint(x: (x + next) / 2, y: y0 + rng.double(-14...14)))
                x = next
            }
            var fill = edge
            fill.addLine(to: CGPoint(x: width + 20, y: y0 + 40))
            fill.addLine(to: CGPoint(x: -20, y: y0 + 40))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(below.soil))
            ctx.stroke(edge, with: .color(below.bedding.opacity(0.5)), lineWidth: 2)
            Ink.outline(ctx, edge.offsetBy(dx: 0, dy: -2), width: 2, color: Palette.ink.opacity(0.55))
            drawLayerMarker(ctx, at: boundary, name: below.name)
        }

        drawSoilTexture(ctx)
        drawStrataLines(ctx)
    }

    /// The mine at night, where every run starts: sky, moon, hills, the
    /// headframe over the shaft and a sign. Drawn in world space so it
    /// scrolls up and away as the drill digs in.
    private func drawSurface(_ ctx: GraphicsContext, width: Double) {
        let ground = point(0, 0).y
        let m = Double(scale)
        // Stepped night sky.
        let bands: [Color] = [Palette.background, Palette.panelSunken, Palette.panel]
        let skyTop = point(0, -14).y
        for (index, color) in bands.enumerated() {
            // The first band also covers anything above the sky's top edge.
            let band = skyTop + (ground - skyTop) * Double(index) / Double(bands.count)
            let top = index == 0 ? min(band, -40) : band
            ctx.fill(Path(CGRect(x: -40, y: top, width: width + 80, height: ground - top)), with: .color(color))
        }
        // Stars and moon.
        var rng = SeededRandom(seed: 0x5EA7)
        for k in 0..<26 {
            let p = point(rng.double(0...GameWorld.shaftWidth), rng.double(-13 ... -2.2))
            let twinkle = world.reduceMotion ? 0.7 : 0.45 + 0.4 * sin(world.spin * 0.5 + Double(k))
            let r = rng.double(0.8...1.8)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                     with: .color(Palette.shine.opacity(twinkle)))
        }
        let moonC = point(1.7, -6.2)
        let moon = CGRect(x: moonC.x - 0.55 * m, y: moonC.y - 0.55 * m, width: 1.1 * m, height: 1.1 * m)
        ctx.fill(Path(ellipseIn: moon), with: .color(Palette.shine))
        ctx.fill(Path(ellipseIn: moon.offsetBy(dx: 0.28 * m, dy: -0.15 * m)), with: .color(Palette.panelSunken))
        Ink.outline(ctx, Path(ellipseIn: moon), width: 2, color: Palette.ink.opacity(0.6))
        // Two rows of hills, inked along their tops.
        for (index, tint) in [Palette.panelRaised.opacity(0.65), Palette.panelRaised].enumerated() {
            var hr = SeededRandom(seed: UInt64(41 + index))
            let base = point(0, index == 0 ? -1.1 : -0.45).y
            var hills = Path()
            hills.move(to: CGPoint(x: -20, y: ground))
            hills.addLine(to: CGPoint(x: -20, y: base))
            var x = -20.0
            while x < width + 20 {
                let next = x + hr.double(60...110)
                hills.addQuadCurve(to: CGPoint(x: next, y: base + hr.double(-4...6)),
                                   control: CGPoint(x: (x + next) / 2, y: base - hr.double(12...30)))
                x = next
            }
            hills.addLine(to: CGPoint(x: width + 20, y: ground))
            hills.closeSubpath()
            ctx.fill(hills, with: .color(tint))
            ctx.stroke(hills, with: .color(Palette.ink.opacity(0.5)), lineWidth: 1.6)
        }
        // Timber headframe over the shaft, pulley turning, cable down to the rig.
        let foot = point(7.1, 0)
        let peak = point(6.6, -2.5)
        var frame = Path()
        frame.move(to: CGPoint(x: foot.x - 0.75 * m, y: ground)); frame.addLine(to: CGPoint(x: peak.x - 0.12 * m, y: peak.y))
        frame.move(to: CGPoint(x: foot.x + 0.7 * m, y: ground)); frame.addLine(to: CGPoint(x: peak.x + 0.12 * m, y: peak.y))
        for k in 1...2 {
            let y = ground - Double(k) * 0.75 * m
            let spread = (0.72 - Double(k) * 0.2) * m
            frame.move(to: CGPoint(x: foot.x - spread - Double(k) * 0.1 * m, y: y))
            frame.addLine(to: CGPoint(x: foot.x + spread - Double(k) * 0.12 * m, y: y - 0.3 * m))
        }
        ctx.stroke(frame, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 0.2 * m, lineCap: .round))
        ctx.stroke(frame, with: .color(Palette.crate), style: StrokeStyle(lineWidth: 0.11 * m, lineCap: .round))
        var cable = Path()
        cable.move(to: CGPoint(x: peak.x - 0.35 * m, y: peak.y))
        cable.addLine(to: point(world.x + 0.3, min(world.depth - 0.9, -0.9)))
        ctx.stroke(cable, with: .color(Palette.ink.opacity(0.75)), lineWidth: 1.4)
        let wheelR = 0.38 * m
        let wheel = Path(ellipseIn: CGRect(x: peak.x - wheelR, y: peak.y - wheelR, width: wheelR * 2, height: wheelR * 2))
        ctx.fill(wheel, with: .color(Palette.drillBitShadow))
        var spokes = Path()
        for k in 0..<4 {
            let a = world.spin * 0.25 + Double(k) * .pi / 4
            spokes.move(to: CGPoint(x: peak.x - cos(a) * wheelR, y: peak.y - sin(a) * wheelR))
            spokes.addLine(to: CGPoint(x: peak.x + cos(a) * wheelR, y: peak.y + sin(a) * wheelR))
        }
        ctx.stroke(spokes, with: .color(Palette.ink.opacity(0.7)), lineWidth: 1.6)
        Ink.outline(ctx, wheel, width: 2.2)
        // Lantern on the frame.
        let lamp = point(6.1, -1.0)
        Ink.halo(ctx, center: lamp, radius: 0.75 * m, color: Palette.gold, strength: 1.4)
        let lampBody = Path(roundedRect: CGRect(x: lamp.x - 0.13 * m, y: lamp.y - 0.2 * m, width: 0.26 * m, height: 0.38 * m),
                            cornerRadius: 0.06 * m)
        ctx.fill(lampBody, with: .color(Palette.gold))
        ctx.stroke(lampBody, with: .color(Palette.ink), lineWidth: 1.6)
        // Wooden sign by the shaft.
        let post = point(1.35, 0)
        ctx.fill(Path(CGRect(x: post.x - 0.06 * m, y: ground - 1.3 * m, width: 0.12 * m, height: 1.3 * m)),
                 with: .color(Palette.crate))
        let board = CGRect(x: post.x - 0.95 * m, y: ground - 1.55 * m, width: 1.9 * m, height: 0.6 * m)
        let boardPath = Path(roundedRect: board, cornerRadius: 0.08 * m)
        ctx.fill(boardPath, with: .color(Palette.crate))
        ctx.fill(Path(CGRect(x: board.minX, y: board.midY, width: board.width, height: 1.2)), with: .color(Palette.ink.opacity(0.35)))
        Ink.outline(ctx, boardPath, width: 2)
        ctx.draw(Text("MINE No.1").font(.system(size: 0.3 * m, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.shine), at: CGPoint(x: board.midX, y: board.midY))
        // Ground lip with an inked edge and a few tufts.
        let layer = Strata.layers[0]
        ctx.fill(Path(CGRect(x: -40, y: ground - 3, width: width + 80, height: 9)), with: .color(layer.pebble))
        var lip = Path()
        lip.move(to: CGPoint(x: -40, y: ground - 3)); lip.addLine(to: CGPoint(x: width + 40, y: ground - 3))
        ctx.stroke(lip, with: .color(Palette.ink), lineWidth: 2.4)
        var tufts = Path()
        var tr = SeededRandom(seed: 0x7F7)
        for _ in 0..<9 {
            let tx = tr.double(0...width)
            guard abs(tx - point(world.x, 0).x) > 0.9 * m else { continue }
            for k in -1...1 {
                tufts.move(to: CGPoint(x: tx + Double(k) * 3, y: ground - 3))
                tufts.addLine(to: CGPoint(x: tx + Double(k) * 5, y: ground - 3 - tr.double(5...9)))
            }
        }
        ctx.stroke(tufts, with: .color(Palette.ink.opacity(0.7)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
    }

    /// Hatching and stipple, seeded per world row so they scroll with the
    /// ground. This is the hand-drawn texture that replaces gradients.
    private func drawSoilTexture(_ ctx: GraphicsContext) {
        let row = 2.5
        let width = Double(size.width)
        var depth = (max(0, cameraTop) / row).rounded(.down) * row
        while depth < cameraBottom {
            let layer = Strata.layer(for: depth)
            var rng = SeededRandom(seed: UInt64(depth * 13) &+ 0x5011)
            // Hatch clusters: three to five short parallel strokes.
            for _ in 0..<3 {
                let origin = point(rng.double(0...GameWorld.shaftWidth), depth + rng.double(0...row))
                let strokes = rng.int(3...5)
                let length = rng.double(7...13)
                var hatch = Path()
                for k in 0..<strokes {
                    let ox = origin.x + Double(k) * 4.2
                    hatch.move(to: CGPoint(x: ox, y: origin.y))
                    hatch.addLine(to: CGPoint(x: ox - length * 0.45, y: origin.y + length))
                }
                ctx.stroke(hatch, with: .color(layer.soilDeep.opacity(0.75)),
                           style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
            // Stipple: darker and lighter grains.
            for _ in 0..<16 {
                let p = point(rng.double(0...GameWorld.shaftWidth), depth + rng.double(0...row))
                let r = rng.double(0.7...1.8)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(rng.chance(0.6) ? layer.soilDeep.opacity(0.8) : layer.pebble.opacity(0.7)))
            }
            _ = width
            depth += row
        }
    }

    /// Sedimentary bedding planes: a shaded groove with a lit edge beneath it,
    /// gently undulating so the ground does not read as flat bands.
    private func drawStrataLines(_ ctx: GraphicsContext) {
        let spacing = 3.4
        let width = Double(size.width)
        var depth = (cameraTop / spacing).rounded(.down) * spacing
        while depth < cameraBottom {
            if depth > 0 {
                let y = point(0, depth).y
                var rng = SeededRandom(seed: UInt64(depth * 7) | 1)
                let layer = Strata.layer(for: depth)
                let amplitude = rng.double(2...7)
                let inset = rng.double(0...70)
                var bed = Path()
                bed.move(to: CGPoint(x: -10 + inset, y: y))
                var x = -10 + inset
                var phase = rng.double(0...6.28)
                while x < width + 10 {
                    let next = x + 46
                    phase += 0.9
                    bed.addQuadCurve(to: CGPoint(x: next, y: y + sin(phase) * amplitude * 0.35),
                                     control: CGPoint(x: x + 23, y: y + sin(phase - 0.5) * amplitude))
                    x = next
                }
                // Broken pen line: a dash pattern unique to each bed.
                let dash: [CGFloat] = [rng.double(30...90), rng.double(8...22), rng.double(10...40), rng.double(6...16)].map { CGFloat($0) }
                ctx.stroke(bed, with: .color(Palette.ink.opacity(0.2)),
                           style: StrokeStyle(lineWidth: rng.double(1.4...2.4), lineCap: .round, dash: dash))
                ctx.stroke(bed.offsetBy(dx: 0, dy: 2.2),
                           with: .color(layer.bedding.opacity(0.3)),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: dash))
            }
            depth += spacing
        }
    }

    private func drawLayerMarker(_ ctx: GraphicsContext, at depth: Double, name: String) {
        let y = point(0, depth).y
        var line = Path()
        line.move(to: CGPoint(x: 18, y: y))
        line.addLine(to: CGPoint(x: Double(size.width) - 18, y: y))
        ctx.stroke(line, with: .color(Palette.textSecondary.opacity(0.35)),
                   style: StrokeStyle(lineWidth: 1.5, dash: [5, 7]))
        let plateWidth = Double(name.count) * 7.6 + 26
        ctx.fill(Path(roundedRect: CGRect(x: Double(size.width) / 2 - plateWidth / 2,
                                          y: y - 24, width: plateWidth, height: 17),
                      cornerRadius: 8.5),
                 with: .color(Palette.background.opacity(0.6)))
        ctx.draw(Text(name)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(Palette.textSecondary),
                 at: CGPoint(x: Double(size.width) / 2, y: y - 15.5))
    }

    private func drawDecor(_ ctx: GraphicsContext) {
        for item in decorInView where item.kind == .blotch {
            drawBlotch(ctx, item)
        }
        for item in decorInView where item.kind != .blotch {
            switch item.kind {
            case .pebble: drawEmbeddedRock(ctx, item)
            case .vein: drawVein(ctx, item)
            case .crystal: drawCrystalCluster(ctx, item)
            case .blotch: break
            }
        }
    }

    private var decorInView: [Decor] {
        world.decor.filter { $0.y > cameraTop - 6 && $0.y < cameraBottom + 6 }
    }

    /// Broad soft patches that stop the soil reading as a flat gradient.
    private func drawBlotch(_ ctx: GraphicsContext, _ item: Decor) {
        let layer = Strata.layer(for: max(0, item.y))
        let center = point(item.x, item.y)
        let radius = item.size * Double(scale) * 0.5
        var rng = SeededRandom(seed: item.seed)
        let tone = rng.chance(0.5) ? layer.soilDeep : layer.pebble
        ctx.fill(Blob.stone(center: center, radius: radius, sides: 7, jitter: 0.5,
                             angle: item.angle, seed: item.seed, rounding: 0.4),
                 with: .color(tone.opacity(0.22)))
    }

    /// Background rock embedded in the wall — lit top-left, shaded bottom-right.
    private func drawEmbeddedRock(_ ctx: GraphicsContext, _ item: Decor) {
        let layer = Strata.layer(for: max(0, item.y))
        let center = point(item.x, item.y)
        let radius = item.size * Double(scale) * 0.36
        let body = Blob.stone(center: center, radius: radius, sides: 6, jitter: 0.55,
                              angle: item.angle, seed: item.seed, rounding: 0.24)
        ctx.fill(body, with: .color(layer.pebble.opacity(0.45)))
        var inner = ctx
        inner.clip(to: body)
        inner.fill(Path(CGRect(x: center.x - radius, y: center.y + radius * 0.1,
                               width: radius * 2, height: radius * 1.2)),
                   with: .color(layer.soilDeep.opacity(0.4)))
        inner.stroke(Blob.fissures(center: center, radius: radius, count: 1, seed: item.seed ^ 9),
                     with: .color(.black.opacity(0.18)), lineWidth: 1.4)
        ctx.stroke(body, with: .color(Palette.ink.opacity(0.3)), lineWidth: 1.4)
    }

    /// Mineral threads running through the rock.
    private func drawVein(_ ctx: GraphicsContext, _ item: Decor) {
        let layer = Strata.layer(for: max(0, item.y))
        let start = point(item.x, item.y)
        let path = Blob.vein(start: start, length: item.size * Double(scale),
                             angle: item.angle, seed: item.seed)
        ctx.stroke(path, with: .color(.black.opacity(0.1)),
                   style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(layer.vein.opacity(0.3)),
                   style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
        // Flecks along the seam read as mineral rather than root.
        var rng = SeededRandom(seed: item.seed ^ 0xFEC)
        for _ in 0..<5 {
            let along = path.trimmedPath(from: rng.double(0...0.95), to: 1).boundingRect
            let dot = rng.double(1.6...3.2)
            ctx.fill(Path(ellipseIn: CGRect(x: along.minX - dot / 2, y: along.minY - dot / 2,
                                            width: dot, height: dot)),
                     with: .color(layer.vein.opacity(0.45)))
        }
    }

    private func drawCrystalCluster(_ ctx: GraphicsContext, _ item: Decor) {
        let layer = Strata.layer(for: max(0, item.y))
        guard let crystal = layer.crystal else { return }
        let base = point(item.x, item.y)
        let size = item.size * Double(scale)
        let shards = Blob.crystalCluster(base: base, size: size, count: 3, seed: item.seed)
        for (shard, lean) in shards {
            ctx.fill(shard, with: .color(crystal.opacity(0.42)))
            // Lit facet down the left of each shard.
            var facet = ctx
            facet.clip(to: shard)
            facet.fill(Path(CGRect(x: base.x - size, y: base.y - size * 1.2,
                                   width: size * (0.95 + lean * 0.2), height: size * 2)),
                       with: .color(.white.opacity(0.26)))
            Ink.outline(ctx, shard, width: 1.6, color: Palette.ink.opacity(0.7))
        }
        Ink.shine(ctx, at: CGPoint(x: base.x, y: base.y - size * 0.75), size: size * 0.4 * 0.9, opacity: 0.5)
    }

    // MARK: - The hole

    private func drawTrail(_ ctx: GraphicsContext) {
        // The tunnel can double back, so keep every on-screen segment rather
        // than cutting the polyline at the first point that scrolled away.
        var path = Path()
        var drawing = false
        for (a, b) in zip(world.trail, world.trail.dropFirst()) {
            let onScreen = max(a.y, b.y) > cameraTop - 3 && min(a.y, b.y) < cameraBottom + 3
            guard onScreen else { drawing = false; continue }
            if !drawing { path.move(to: point(a.x, a.y)); drawing = true }
            path.addLine(to: point(b.x, b.y))
        }
        guard !path.isEmpty else { return }
        // The hole only exists underground: clip it at the surface so its
        // rounded rim never pokes up into the sky.
        var ctx = ctx
        let ground = point(0, 0).y
        if ground > -10 {
            ctx.clip(to: Path(CGRect(x: -40, y: ground, width: Double(size.width) + 80, height: Double(size.height) + 80)))
        }
        // Crumbled outer rim, lit lip, then the dark bore.
        let layer = Strata.layer(for: max(0, world.depth))
        // Inked outer edge first, so the tunnel reads as cut by a pen.
        ctx.stroke(path, with: .color(Palette.ink.opacity(0.85)),
                   style: StrokeStyle(lineWidth: 2.2 * scale + 4, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(layer.soilDeep),
                   style: StrokeStyle(lineWidth: 2.2 * scale, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(layer.bedding.opacity(0.45)),
                   style: StrokeStyle(lineWidth: 1.85 * scale, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(Palette.background.opacity(0.62)),
                   style: StrokeStyle(lineWidth: 1.55 * scale, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(.black.opacity(0.3)),
                   style: StrokeStyle(lineWidth: 1.0 * scale, lineCap: .round, lineJoin: .round))
    }

    private func drawBestLine(_ ctx: GraphicsContext) {
        guard world.showsBestLine else { return }
        let best = world.previousBest
        let y = point(0, best).y
        var line = Path()
        line.move(to: CGPoint(x: 12, y: y))
        line.addLine(to: CGPoint(x: Double(size.width) - 12, y: y))
        ctx.stroke(line, with: .color(Palette.gold.opacity(0.85)),
                   style: StrokeStyle(lineWidth: 2.5, dash: [9, 7]))

        let label = Text("BEST: \(Int(best)) m")
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(Palette.background)
        let pill = Path(roundedRect: CGRect(x: Double(size.width) / 2 - 46, y: y - 21,
                                            width: 92, height: 18),
                        cornerRadius: 9)
        ctx.fill(pill, with: .color(Palette.gold.opacity(0.9)))
        ctx.draw(label, at: CGPoint(x: Double(size.width) / 2, y: y - 12))
    }

    // MARK: - Treasure chambers

    private func drawChamberGlow(_ ctx: GraphicsContext) {
        for chamber in world.chambers where !chamber.opened {
            // Glows before it enters view: fades up as the drill closes in.
            let distance = chamber.y - world.depth
            guard distance > -6, distance < 55 else { continue }
            let nearness = max(0, min(1, 1 - (distance - 4) / 45))
            guard nearness > 0.02 else { continue }
            let center = point(chamber.x, chamber.y)
            let radius = chamber.radius * Double(scale) * (1.5 + 0.25 * sin(world.depth * 0.5))
            Ink.halo(ctx, center: center, radius: radius, color: Palette.gold, strength: 1.4 * nearness)
        }
    }

    private func drawChambers(_ ctx: GraphicsContext) {
        for chamber in world.chambers {
            guard chamber.y > cameraTop - 6, chamber.y < cameraBottom + 6 else { continue }
            let center = point(chamber.x, chamber.y)
            let radius = chamber.radius * Double(scale)
            let cavity = Blob.rock(center: center, radius: radius, sides: 9, jitter: 0.22,
                                   angle: 0.4, seed: UInt64(chamber.id) &* 977 | 1)
            ctx.fill(cavity, with: .color(Palette.background.opacity(0.72)))
            ctx.stroke(cavity, with: .color(Palette.gold.opacity(0.35)), lineWidth: 2.5)
            drawChest(ctx, at: CGPoint(x: center.x, y: center.y + radius * 0.25),
                      size: radius * 0.8, open: chamber.openT)
        }
    }

    private func drawChest(_ ctx: GraphicsContext, at center: CGPoint, size: Double, open: Double) {
        let width = size * 1.35
        let height = size * 0.66
        let top = center.y - height * 0.1

        let base = Path(roundedRect: CGRect(x: center.x - width / 2, y: top,
                                            width: width, height: height),
                        cornerRadius: size * 0.1)
        ctx.fill(base, with: .color(Palette.crate))
        var inner = ctx
        inner.clip(to: base)
        // Timber planks.
        var plankY = top + height * 0.3
        while plankY < top + height {
            inner.fill(Path(CGRect(x: center.x - width / 2, y: plankY, width: width, height: 2)),
                       with: .color(.black.opacity(0.25)))
            plankY += height * 0.3
        }
        inner.fill(Path(CGRect(x: center.x - width / 2, y: top + height * 0.62,
                               width: width, height: height)),
                   with: .color(.black.opacity(0.22)))
        // Iron banding with studs.
        for offset in [-0.3, 0.3] {
            let bandX = center.x + width * offset - width * 0.055
            inner.fill(Path(CGRect(x: bandX, y: top, width: width * 0.11, height: height)),
                       with: .color(Palette.gold))
            inner.fill(Path(CGRect(x: bandX, y: top, width: width * 0.04, height: height)),
                       with: .color(.white.opacity(0.3)))
            for studY in [top + height * 0.25, top + height * 0.72] {
                inner.fill(Path(ellipseIn: CGRect(x: bandX + width * 0.025, y: studY,
                                                  width: size * 0.07, height: size * 0.07)),
                           with: .color(Palette.goldShadow))
            }
        }
        Ink.outline(ctx, base, width: 2.4)

        // Lid: a shallow dome that swings back when the chest is opened.
        var lid = ctx
        lid.translateBy(x: center.x, y: top)
        lid.rotate(by: .degrees(-105 * open))
        let lidPath = Blob.chunky([CGPoint(x: -width / 2, y: 0),
                                   CGPoint(x: -width / 2, y: -height * 0.34),
                                   CGPoint(x: -width * 0.3, y: -height * 0.52),
                                   CGPoint(x: width * 0.3, y: -height * 0.52),
                                   CGPoint(x: width / 2, y: -height * 0.34),
                                   CGPoint(x: width / 2, y: 0)], rounding: 0.22)
        lid.fill(lidPath, with: .color(Palette.gold))
        var lidInner = lid
        lidInner.clip(to: lidPath)
        lidInner.fill(Path(CGRect(x: -width / 2, y: -height * 0.2, width: width, height: height * 0.3)),
                      with: .color(Palette.goldShadow))
        lidInner.fill(Path(CGRect(x: -width / 2, y: -height * 0.54, width: width, height: height * 0.1)),
                      with: .color(.white.opacity(0.3)))
        for offset in [-0.3, 0.3] {
            lidInner.fill(Path(CGRect(x: width * offset - width * 0.055, y: -height * 0.54,
                                      width: width * 0.11, height: height * 0.56)),
                          with: .color(Palette.crate.opacity(0.8)))
        }
        lid.stroke(lidPath, with: .color(Palette.goldShadow), lineWidth: 2)

        // Clasp at the seam.
        let clasp = Path(roundedRect: CGRect(x: center.x - size * 0.09, y: top - size * 0.06,
                                             width: size * 0.18, height: size * 0.2),
                         cornerRadius: size * 0.05)
        ctx.fill(clasp, with: .color(Palette.gold))
        Ink.outline(ctx, clasp, width: 1.6)
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - size * 0.03, y: top + size * 0.02,
                                        width: size * 0.06, height: size * 0.06)),
                 with: .color(Palette.goldShadow))

        // Coins spilling out once it is open.
        if open > 0.4 {
            var rng = SeededRandom(seed: 0xC0FFEE)
            for _ in 0..<7 {
                let coin = size * rng.double(0.08...0.14)
                let x = center.x + rng.double(-width * 0.45...width * 0.45)
                let y = top + height * rng.double(0.1...0.9)
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: coin, height: coin)),
                         with: .color(Palette.gold.opacity((open - 0.4) / 0.6)))
            }
        }
    }

    // MARK: - Treasure and rock

    /// A faint dotted line through the nuggets of each unbroken trail, so it
    /// reads as one thing worth sweeping.
    private func drawTrailHints(_ ctx: GraphicsContext) {
        var groups: [Int: [CGPoint]] = [:]
        var broken: Set<Int> = []
        for pickup in world.pickups {
            guard let trail = pickup.trail, !pickup.collected else { continue }
            if pickup.y < world.depth - 1.2 { broken.insert(trail) }
            groups[trail, default: []].append(point(pickup.x, pickup.y))
        }
        for (trail, points) in groups where points.count > 1 && !broken.contains(trail) {
            guard let first = points.first, Double(first.y) < Double(size.height) + 60 else { continue }
            var path = Path()
            path.move(to: first)
            for p in points.dropFirst() { path.addLine(to: p) }
            ctx.stroke(path, with: .color(Palette.gold.opacity(0.28)),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 9]))
        }
    }

    private func drawFuelCan(_ ctx: GraphicsContext, at center: CGPoint) {
        let w = 0.62 * Double(scale)
        let h = 0.8 * Double(scale)
        let body = CGRect(x: center.x - w / 2, y: center.y - h / 2 + h * 0.12,
                          width: w, height: h * 0.88)
        let shell = Path(roundedRect: body, cornerRadius: w * 0.18)
        ctx.fill(shell, with: .color(Palette.mint))
        var inner = ctx
        inner.clip(to: shell)
        inner.fill(Path(CGRect(x: body.midX, y: body.minY, width: w / 2, height: body.height)),
                   with: .color(Palette.mintShadow))
        // Cross-bracing stamped into the side, like a jerrycan.
        var brace = Path()
        brace.move(to: CGPoint(x: body.minX + w * 0.2, y: body.minY + body.height * 0.25))
        brace.addLine(to: CGPoint(x: body.maxX - w * 0.2, y: body.maxY - body.height * 0.18))
        brace.move(to: CGPoint(x: body.maxX - w * 0.2, y: body.minY + body.height * 0.25))
        brace.addLine(to: CGPoint(x: body.minX + w * 0.2, y: body.maxY - body.height * 0.18))
        inner.stroke(brace, with: .color(.white.opacity(0.35)),
                     style: StrokeStyle(lineWidth: 2, lineCap: .round))
        Ink.outline(ctx, shell, width: 2.3)
        // Spout and handle.
        let spout = Path(roundedRect: CGRect(x: center.x + w * 0.05, y: center.y - h / 2 - h * 0.02,
                                             width: w * 0.3, height: h * 0.18),
                         cornerRadius: 2)
        ctx.fill(spout, with: .color(Palette.drillBit))
        ctx.stroke(Path(roundedRect: CGRect(x: center.x - w * 0.38, y: center.y - h / 2 + h * 0.02,
                                            width: w * 0.36, height: h * 0.14),
                        cornerRadius: 3),
                   with: .color(Palette.mintShadow), lineWidth: 2.4)
        Ink.shine(ctx, at: CGPoint(x: body.minX + w * 0.22, y: body.minY + h * 0.14), size: w * 0.5 * 0.9, opacity: 0.85)
    }

    private func drawPickups(_ ctx: GraphicsContext) {
        for pickup in world.pickups where !pickup.collected {
            guard pickup.y > cameraTop - 1.5, pickup.y < cameraBottom + 1.5 else { continue }
            let bob = world.reduceMotion ? 0 : sin(world.depth * 0.8 + pickup.phase) * 0.06
            let center = point(pickup.x, pickup.y + bob)
            let opacity = pickup.deniedFlash > 0 ? 0.35 : 1.0

            switch pickup.kind {
            case .fuel:
                drawFuelCan(ctx, at: center)

            case .gold:
                // Ore: the metal comes from the layer the nugget sits in.
                let ore = Strata.layer(for: max(0, pickup.y)).ore
                let radius = 0.32 * Double(scale)
                let nugget = Blob.stone(center: center, radius: radius, sides: 7, jitter: 0.32,
                                        angle: pickup.phase, seed: UInt64(pickup.id) &* 7919 | 1,
                                        rounding: 0.14)
                ctx.fill(nugget, with: .color(ore.color.opacity(opacity)))
                var facet = ctx
                facet.clip(to: nugget)
                // Shadowed underside, two cut faces, bright top-left crown.
                facet.fill(Path(CGRect(x: center.x - radius, y: center.y + radius * 0.12,
                                       width: radius * 2, height: radius * 1.2)),
                           with: .color(ore.shadow.opacity(0.9 * opacity)))
                facet.fill(Blob.chunky([CGPoint(x: center.x - radius, y: center.y - radius * 0.2),
                                        CGPoint(x: center.x - radius * 0.1, y: center.y - radius),
                                        CGPoint(x: center.x + radius * 0.3, y: center.y - radius * 0.3),
                                        CGPoint(x: center.x - radius * 0.5, y: center.y + radius * 0.2)],
                                       rounding: 0.1),
                           with: .color(.white.opacity(0.3 * opacity)))
                facet.stroke(Blob.chunky([CGPoint(x: center.x - radius * 0.7, y: center.y + radius * 0.1),
                                          CGPoint(x: center.x, y: center.y - radius * 0.15),
                                          CGPoint(x: center.x + radius * 0.8, y: center.y + radius * 0.25)],
                                         rounding: 0.2),
                             with: .color(ore.shadow.opacity(0.7 * opacity)), lineWidth: 1.6)
                Ink.outline(ctx, nugget, width: 2.3, color: Palette.ink.opacity(opacity))
                Ink.shine(ctx, at: CGPoint(x: center.x - radius * 0.38,
                                                      y: center.y - radius * 0.46), size: radius * 0.75 * 0.9, opacity: 0.9 * opacity)

            case .gem:
                let height = 0.78 * Double(scale)
                let width = 0.56 * Double(scale)
                let body = Shapes.diamondPath(center: center, width: width, height: height)
                ctx.fill(body, with: .color(Palette.gem.opacity(opacity)))

                var cut = ctx
                cut.clip(to: body)
                let tableY = center.y - height * 0.16
                let culet = CGPoint(x: center.x, y: center.y + height / 2)
                // Crown: a bright table with facets falling away from it.
                cut.fill(Blob.chunky([CGPoint(x: center.x - width * 0.28, y: center.y - height * 0.5),
                                      CGPoint(x: center.x + width * 0.28, y: center.y - height * 0.5),
                                      CGPoint(x: center.x + width * 0.46, y: tableY),
                                      CGPoint(x: center.x - width * 0.46, y: tableY)],
                                     rounding: 0.05),
                         with: .color(.white.opacity(0.34 * opacity)))
                cut.fill(Blob.chunky([CGPoint(x: center.x - width * 0.46, y: tableY),
                                      CGPoint(x: center.x - width * 0.08, y: tableY),
                                      culet], rounding: 0.05),
                         with: .color(.white.opacity(0.2 * opacity)))
                cut.fill(Blob.chunky([CGPoint(x: center.x + width * 0.16, y: tableY),
                                      CGPoint(x: center.x + width * 0.46, y: tableY),
                                      culet], rounding: 0.05),
                         with: .color(Palette.gemShadow.opacity(0.55 * opacity)))
                // Girdle line and pavilion rays.
                var rays = Path()
                rays.move(to: CGPoint(x: center.x - width * 0.46, y: tableY))
                rays.addLine(to: CGPoint(x: center.x + width * 0.46, y: tableY))
                for offset in [-0.2, 0.2] {
                    rays.move(to: CGPoint(x: center.x + width * offset, y: tableY))
                    rays.addLine(to: culet)
                }
                cut.stroke(rays, with: .color(Palette.gemShadow.opacity(0.65 * opacity)), lineWidth: 1.5)

                Ink.outline(ctx, body, width: 2.3, color: Palette.ink.opacity(opacity))
                Ink.shine(ctx, at: CGPoint(x: center.x - width * 0.2,
                                                      y: center.y - height * 0.34), size: width * 0.55 * 0.9, opacity: 0.95 * opacity)
            }

            if pickup.deniedFlash > 0.4 {
                ctx.draw(Text("FULL")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.hazard),
                         at: CGPoint(x: center.x, y: center.y - 20))
            }
        }
    }

    private func drawObstacles(_ ctx: GraphicsContext) {
        for rock in world.obstacles where !rock.destroyed {
            guard rock.y > cameraTop - 3, rock.y < cameraBottom + 3 else { continue }
            let center = point(rock.x, rock.y)
            let dangerous = !world.canDrill(rock)
            let fill = rock.kind == .geode
                ? Palette.hazardShadow
                : Palette.rock(hardness: rock.hardness)
            let shade = rock.kind == .geode
                ? Palette.hazard
                : Palette.rockShade(hardness: rock.hardness)
            let light = rock.kind == .geode
                ? Palette.hazard
                : Palette.rockLight(hardness: rock.hardness)

            switch rock.kind {
            case .boulder:
                let radius = rock.w * 0.5 * Double(scale)
                let body = Blob.stone(center: center, radius: radius, sides: 7, jitter: 0.34,
                                      angle: rock.angle, seed: rock.seed, rounding: 0.26)
                ctx.fill(body, with: .color(fill))
                var inner = ctx
                inner.clip(to: body)
                // Core shadow lower-right, lit face upper-left.
                inner.fill(Path(CGRect(x: center.x - radius, y: center.y + radius * 0.08,
                                       width: radius * 2, height: radius * 1.2)),
                           with: .color(shade))
                inner.fill(Blob.stone(center: CGPoint(x: center.x - radius * 0.28,
                                                      y: center.y - radius * 0.34),
                                      radius: radius * 0.72, sides: 6, jitter: 0.4,
                                      angle: rock.angle + 1, seed: rock.seed ^ 3, rounding: 0.3),
                           with: .color(light))
                inner.stroke(Blob.fissures(center: center, radius: radius, count: 2,
                                           seed: rock.seed ^ 77),
                             with: .color(.black.opacity(0.26)),
                             style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                drawSpeckle(inner, center: center, radius: radius, seed: rock.seed, layer: layerFor(rock))
                strokeRim(ctx, body, dangerous: dangerous, flash: rock.hitFlash)

            case .slab:
                var slab = ctx
                slab.translateBy(x: center.x, y: center.y)
                slab.rotate(by: .radians(rock.angle))
                let rect = CGRect(x: -rock.w / 2 * Double(scale), y: -rock.h / 2 * Double(scale),
                                  width: rock.w * Double(scale), height: rock.h * Double(scale))
                let body = Path(roundedRect: rect, cornerRadius: rock.h * 0.26 * Double(scale))
                slab.fill(body, with: .color(fill))
                var inner = slab
                inner.clip(to: body)
                inner.fill(Path(CGRect(x: rect.minX, y: rect.midY + rect.height * 0.1,
                                       width: rect.width, height: rect.height)),
                           with: .color(shade))
                inner.fill(Path(CGRect(x: rect.minX, y: rect.minY,
                                       width: rect.width, height: rect.height * 0.28)),
                           with: .color(light))
                // Cut blocks with chipped, bevelled joints.
                let blocks = max(2, Int(rock.w / 1.1))
                for index in 1..<blocks {
                    let x = rect.minX + rect.width * Double(index) / Double(blocks)
                    inner.fill(Path(CGRect(x: x, y: rect.minY, width: 2.6, height: rect.height)),
                               with: .color(.black.opacity(0.3)))
                    inner.fill(Path(CGRect(x: x + 2.6, y: rect.minY, width: 1.4, height: rect.height)),
                               with: .color(light.opacity(0.7)))
                }
                inner.stroke(Blob.fissures(center: CGPoint(x: rect.midX, y: rect.midY),
                                           radius: rect.height * 0.5, count: 2, seed: rock.seed),
                             with: .color(.black.opacity(0.2)),
                             style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                strokeRim(slab, body, dangerous: dangerous, flash: rock.hitFlash)

            case .geode:
                let radius = rock.w * 0.5 * Double(scale)
                let spikes = Shapes.spikePath(center: center, radius: radius, points: 8,
                                              inner: 0.56, angle: rock.angle)
                ctx.fill(spikes, with: .color(Palette.hazard))
                //每 spike gets a lit left edge.
                var inner = ctx
                inner.clip(to: spikes)
                inner.fill(Path(CGRect(x: center.x - radius, y: center.y,
                                       width: radius * 2, height: radius)),
                           with: .color(Palette.hazardShadow))
                inner.fill(Path(CGRect(x: center.x - radius, y: center.y - radius,
                                       width: radius * 0.5, height: radius * 2)),
                           with: .color(.white.opacity(0.14)))
                let core = Path(ellipseIn: CGRect(x: center.x - radius * 0.44, y: center.y - radius * 0.44,
                                                  width: radius * 0.88, height: radius * 0.88))
                ctx.fill(core, with: .color(Palette.hazardShadow))
                ctx.stroke(core, with: .color(Palette.ink.opacity(0.6)), lineWidth: 1.8)
                // Faceted crystal heart.
                for index in 0..<5 {
                    let theta = rock.angle + Double(index) / 5 * .pi * 2
                    ctx.fill(Blob.chunky([center,
                                          CGPoint(x: center.x + cos(theta) * radius * 0.4,
                                                  y: center.y + sin(theta) * radius * 0.4),
                                          CGPoint(x: center.x + cos(theta + 0.9) * radius * 0.4,
                                                  y: center.y + sin(theta + 0.9) * radius * 0.4)],
                                         rounding: 0.05),
                             with: .color(index.isMultiple(of: 2)
                                          ? Palette.hazard.opacity(0.55)
                                          : .white.opacity(0.12)))
                }
                Ink.shine(ctx, at: CGPoint(x: center.x - radius * 0.18,
                                                      y: center.y - radius * 0.2), size: radius * 0.5 * 0.9, opacity: 0.7)
                Ink.outline(ctx, spikes, width: 2.6)
                if rock.hitFlash > 0 {
                    ctx.stroke(spikes, with: .color(.white.opacity(rock.hitFlash)), lineWidth: 3)
                }
            }
        }
    }

    // MARK: - Critters

    private func drawEnemies(_ ctx: GraphicsContext) {
        for enemy in world.enemies where !enemy.dead {
            guard enemy.y > cameraTop - 3, enemy.y < cameraBottom + 3 else { continue }
            switch enemy.kind {
            case .worm: drawWorm(ctx, enemy)
            case .bat: drawBat(ctx, enemy)
            case .beetle: drawBeetle(ctx, enemy)
            case .spitter: drawSpitter(ctx, enemy)
            case .ember: drawEmber(ctx, enemy)
            case .jelly: drawJelly(ctx, enemy)
            case .angler: drawAngler(ctx, enemy)
            case .mole: drawMole(ctx, enemy)
            case .spider: drawSpider(ctx, enemy)
            case .centipede: drawCentipede(ctx, enemy)
            case .slime: drawSlime(ctx, enemy)
            case .slug: drawSlug(ctx, enemy)
            }
        }
        drawShots(ctx)
    }

    private func drawBat(_ ctx: GraphicsContext, _ bat: Enemy, radius: Double? = nil) {
        let r = (radius ?? bat.kind.radius) * Double(scale)
        var c = point(bat.x, bat.y)
        // The tell: a fast shiver before the dive.
        if bat.mode == .windup && !world.reduceMotion {
            c.x += sin(world.spin * 9) * 2.5
        }
        if bat.chasing {
            Ink.warning(ctx, center: c, radius: r * 1.6)
        }
        let flap = world.reduceMotion ? 0.5 : (sin(world.spin * (bat.mode == .attack ? 3 : 1.6) + bat.phase) + 1) / 2
        for side in [-1.0, 1.0] {
            // Scalloped membrane wing, tip rising and falling with the flap.
            let tip = CGPoint(x: c.x + side * r * 2.3, y: c.y - r * (0.9 * flap - 0.2))
            var wing = Path()
            wing.move(to: CGPoint(x: c.x + side * r * 0.4, y: c.y - r * 0.3))
            wing.addLine(to: tip)
            wing.addQuadCurve(to: CGPoint(x: c.x + side * r * 1.5, y: c.y + r * 0.35),
                              control: CGPoint(x: c.x + side * r * 2.0, y: c.y + r * 0.1))
            wing.addQuadCurve(to: CGPoint(x: c.x + side * r * 0.85, y: c.y + r * 0.35),
                              control: CGPoint(x: c.x + side * r * 1.15, y: c.y + r * 0.05))
            wing.addQuadCurve(to: CGPoint(x: c.x + side * r * 0.35, y: c.y + r * 0.4),
                              control: CGPoint(x: c.x + side * r * 0.6, y: c.y + r * 0.1))
            wing.closeSubpath()
            ctx.fill(wing, with: .color(Palette.batWing))
            Ink.outline(ctx, wing, width: 2)
        }
        let body = Path(ellipseIn: CGRect(x: c.x - r * 0.55, y: c.y - r * 0.7, width: r * 1.1, height: r * 1.4))
        ctx.fill(body, with: .color(Palette.bat))
        // Ears.
        for side in [-1.0, 1.0] {
            ctx.fill(Blob.triangle(CGPoint(x: c.x + side * r * 0.15, y: c.y - r * 0.55),
                                   CGPoint(x: c.x + side * r * 0.5, y: c.y - r * 0.5),
                                   CGPoint(x: c.x + side * r * 0.42, y: c.y - r * 1.05)),
                     with: .color(Palette.bat))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x + side * r * 0.22 - r * 0.12, y: c.y - r * 0.32,
                                            width: r * 0.24, height: r * 0.24)),
                     with: .color(bat.chasing ? Palette.hazard : Palette.beetleEye))
        }
        // Fangs.
        for side in [-1.0, 1.0] {
            ctx.fill(Blob.triangle(CGPoint(x: c.x + side * r * 0.16 - r * 0.06, y: c.y + r * 0.08),
                                   CGPoint(x: c.x + side * r * 0.16 + r * 0.06, y: c.y + r * 0.08),
                                   CGPoint(x: c.x + side * r * 0.16, y: c.y + r * 0.3)),
                     with: .color(.white))
        }
        Ink.outline(ctx, body, width: 2.2)
        if bat.hitFlash > 0 { ctx.stroke(body, with: .color(.white.opacity(bat.hitFlash)), lineWidth: 3) }
    }

    private func drawSpitter(_ ctx: GraphicsContext, _ spitter: Enemy, radius: Double? = nil) {
        let r = (radius ?? spitter.kind.radius) * Double(scale)
        let c = point(spitter.x, spitter.y)
        let charging = spitter.mode == .windup
        if charging { Ink.halo(ctx, center: c, radius: r * 1.7, color: Palette.spitter, strength: 1.6) }
        // Stubby legs under a cluster of amber crystals.
        let step = world.reduceMotion ? 0 : sin(world.spin * 0.8 + spitter.phase) * r * 0.12
        for k in 0..<4 {
            let lx = c.x + r * (-0.6 + 0.4 * Double(k))
            var leg = Path()
            leg.move(to: CGPoint(x: lx, y: c.y + r * 0.2))
            leg.addLine(to: CGPoint(x: lx + (k % 2 == 0 ? step : -step), y: c.y + r * 0.85))
            ctx.stroke(leg, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        let base = Blob.stone(center: CGPoint(x: c.x, y: c.y + r * 0.15), radius: r * 0.75, sides: 6,
                              jitter: 0.2, angle: spitter.phase, seed: UInt64(spitter.id) | 1, rounding: 0.15)
        ctx.fill(base, with: .color(Palette.spitterShadow))
        Ink.outline(ctx, base, width: 2.2)
        for (k, lean) in [-0.5, 0.0, 0.5].enumerated() {
            let height = r * (k == 1 ? 1.25 : 0.9)
            let bx = c.x + lean * r * 0.9
            let shard = Blob.chunky([CGPoint(x: bx - r * 0.22, y: c.y + r * 0.1),
                                     CGPoint(x: bx + lean * r * 0.5, y: c.y - height),
                                     CGPoint(x: bx + r * 0.22, y: c.y + r * 0.1)], rounding: 0.08)
            ctx.fill(shard, with: .color(Palette.spitter))
            Ink.outline(ctx, shard, width: 2)
            var lit = ctx
            lit.clip(to: shard)
            lit.fill(Path(CGRect(x: bx, y: c.y - height, width: r * 0.4, height: height + r * 0.2)),
                     with: .color(Palette.spitterShadow.opacity(0.6)))
        }
        // One glowing eye that brightens as it charges.
        let eye = CGRect(x: c.x - r * 0.18, y: c.y - r * 0.05, width: r * 0.36, height: r * 0.36)
        ctx.fill(Path(ellipseIn: eye), with: .color(Palette.background))
        ctx.fill(Path(ellipseIn: eye.insetBy(dx: r * 0.07, dy: r * 0.07)),
                 with: .color(charging ? .white : Palette.hazard))
        if spitter.hitFlash > 0 { ctx.stroke(base, with: .color(.white.opacity(spitter.hitFlash)), lineWidth: 3) }
    }

    // MARK: - Bosses

    /// Bedrock band across the shaft at the arena floor while the boss lives.
    private func drawArenaSeal(_ ctx: GraphicsContext) {
        guard let boss = world.boss, !boss.defeated else { return }
        let top = point(0, boss.arenaBottom - 0.15).y
        guard top > -40, top < Double(size.height) + 40 else { return }
        let band = CGRect(x: 0, y: top, width: Double(size.width), height: 1.4 * Double(scale))
        ctx.fill(Path(band), with: .color(Palette.rockShade(hardness: 5)))
        var rng = SeededRandom(seed: UInt64(boss.arenaBottom * 10) | 1)
        var x = -10.0
        while x < Double(size.width) {
            let w = rng.double(30...60)
            let block = Blob.stone(center: CGPoint(x: x + w / 2, y: top + band.height * rng.double(0.35...0.6)),
                                   radius: w * 0.55, sides: 6, jitter: 0.25, angle: rng.double(0...6),
                                   seed: rng.next(), rounding: 0.2)
            ctx.fill(block, with: .color(Palette.rock(hardness: 5)))
            ctx.stroke(block, with: .color(Palette.ink), lineWidth: 4.4)
            ctx.stroke(block, with: .color(Palette.hazard.opacity(0.9)), lineWidth: 1.8)
            x += w * 0.9
        }
        // A pulsing warning line along the top edge.
        let pulse = world.reduceMotion ? 0.7 : 0.5 + 0.3 * sin(world.spin * 0.5)
        var edge = Path()
        edge.move(to: CGPoint(x: 0, y: top))
        edge.addLine(to: CGPoint(x: Double(size.width), y: top))
        ctx.stroke(edge, with: .color(Palette.hazard.opacity(pulse)), lineWidth: 3)
    }

    private func drawBoss(_ ctx: GraphicsContext) {
        guard let boss = world.boss, !boss.defeated else { return }
        drawScreech(ctx, boss)
        if boss.burrowed {
            drawBurrowMark(ctx, boss)
            return
        }
        guard boss.y > cameraTop - 6, boss.y < cameraBottom + 6 else { return }
        let r = boss.radius
        let c = point(boss.x, boss.y)
        let attacking = boss.mode == .windup || boss.mode == .attack
        if attacking { Ink.warning(ctx, center: c, radius: r * 1.7 * Double(scale)) }
        // Draw through the critter art, scaled up.
        var proxy = Enemy(id: 7_000_000 + boss.lap, kind: .worm, x: boss.x, y: boss.y,
                          heading: boss.heading, homeY: boss.y, hardness: 0, speed: 0, phase: 0)
        proxy.chasing = attacking
        proxy.hitFlash = boss.hitFlash
        proxy.mode = boss.mode
        switch boss.kind {
        case .wormQueen:
            proxy.segments = boss.segments
            drawWorm(ctx, proxy, radius: r)
            drawCrown(ctx, at: CGPoint(x: c.x, y: c.y - r * Double(scale) * 0.9), size: r * Double(scale))
        case .batMatriarch:
            if boss.dazed > 0 { proxy.mode = .patrol }
            drawBat(ctx, proxy, radius: r)
            drawCrown(ctx, at: CGPoint(x: c.x, y: c.y - r * Double(scale) * 1.05), size: r * Double(scale) * 0.8)
        case .beetleTank:
            // Coral rim while armoured; it goes neutral when the bit can hurt it.
            proxy.hardness = boss.dazed > 0 ? 0 : Int.max
            drawBeetle(ctx, proxy, radius: r)
        case .crystalGolem:
            drawSpitter(ctx, proxy, radius: r)
        case .magmaTitan:
            drawTitan(ctx, boss)
        case .abyssAngler:
            drawAngler(ctx, proxy, radius: r)
            drawCrown(ctx, at: CGPoint(x: c.x, y: c.y - r * Double(scale) * 0.85), size: r * Double(scale) * 0.7)
        }
        if boss.dazed > 0 { drawDazedStars(ctx, at: CGPoint(x: c.x, y: c.y - r * Double(scale) * 1.1)) }
    }

    // MARK: - Magma Core

    private func drawLava(_ ctx: GraphicsContext) {
        let bubble = world.reduceMotion ? 0 : world.spin
        for pool in world.lavaPools {
            guard pool.y > cameraTop - 3, pool.y < cameraBottom + 3 else { continue }
            let c = point(pool.x, pool.y)
            let r = pool.radius * Double(scale)
            if pool.warmup > 0 {
                // Warning: where a flood pool is about to well up.
                let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                ctx.fill(ring, with: .color(Palette.lava.opacity(0.18)))
                ctx.stroke(ring, with: .color(Palette.lava.opacity(0.9)), style: StrokeStyle(lineWidth: 2.5, dash: [7, 5]))
                continue
            }
            var ctx = ctx
            if let life = pool.life { ctx.opacity = min(1, life / 0.8) }
            Ink.halo(ctx, center: c, radius: r * 1.5, color: Palette.lava, strength: 1.3)
            let crust = Blob.rock(center: c, radius: r * 1.08, sides: 9, jitter: 0.18, angle: 0, seed: pool.seed)
            ctx.fill(crust, with: .color(Palette.lavaCrust))
            Ink.outline(ctx, crust, width: 2.4)
            let melt = Blob.rock(center: c, radius: r * 0.9, sides: 9, jitter: 0.2, angle: 1, seed: pool.seed ^ 5)
            ctx.fill(melt, with: .radialGradient(Gradient(colors: [Palette.lavaGlow, Palette.lava]),
                                                 center: c, startRadius: 0, endRadius: r))
            // Bubbles rising and popping.
            var rng = SeededRandom(seed: pool.seed)
            for _ in 0..<4 {
                let a = rng.double(0...(.pi * 2)), d = rng.double(0...(r * 0.6))
                let size = (sin(bubble * 0.3 + rng.double(0...6)) + 1) * 0.5 * r * 0.18 + 1
                ctx.fill(Path(ellipseIn: CGRect(x: c.x + cos(a) * d - size, y: c.y + sin(a) * d - size,
                                                width: size * 2, height: size * 2)),
                         with: .color(Palette.lavaGlow.opacity(0.9)))
            }
            ctx.stroke(melt, with: .color(Palette.lavaCrust.opacity(0.6)), lineWidth: 2)
        }
    }

    private func drawEmber(_ ctx: GraphicsContext, _ ember: Enemy) {
        let c = point(ember.x, ember.y)
        let swell = ember.mode == .windup ? 1 + (0.6 - max(0, ember.timer)) * 0.9 : 1
        let flicker = world.reduceMotion ? 1 : 1 + 0.08 * sin(world.spin * 1.7 + ember.phase)
        let r = ember.kind.radius * Double(scale) * swell * flicker
        Ink.halo(ctx, center: c, radius: r * 1.9, color: ember.mode == .windup ? Palette.hazard : Palette.lava, strength: 1.4)
        // Flame body: a teardrop licking upward.
        var flame = Path()
        flame.move(to: CGPoint(x: c.x, y: c.y - r * 1.6))
        flame.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y + r * 0.2), control: CGPoint(x: c.x + r * 0.9, y: c.y - r * 0.7))
        flame.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y + r * 0.2), control: CGPoint(x: c.x, y: c.y + r * 1.4))
        flame.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r * 1.6), control: CGPoint(x: c.x - r * 0.9, y: c.y - r * 0.7))
        ctx.fill(flame, with: .linearGradient(Gradient(colors: [Palette.lavaGlow, Palette.lava]),
                                              startPoint: CGPoint(x: c.x, y: c.y - r * 1.6),
                                              endPoint: CGPoint(x: c.x, y: c.y + r)))
        Ink.outline(ctx, flame, width: 2.2)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.45, y: c.y - r * 0.45, width: r * 0.9, height: r * 0.9)),
                 with: .color(.white.opacity(0.75)))
        for side in [-1.0, 1.0] {
            ctx.fill(Path(ellipseIn: CGRect(x: c.x + side * r * 0.28 - r * 0.1, y: c.y - r * 0.15,
                                            width: r * 0.2, height: r * 0.24)),
                     with: .color(Palette.lavaCrust))
        }
        if ember.mode == .windup, Int(world.spin * 3) % 2 == 0 {
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 1.9, y: c.y - r * 1.9, width: r * 3.8, height: r * 3.8)),
                       with: .color(Palette.hazard.opacity(0.8)), lineWidth: 2)
        }
    }

    private func drawTitan(_ ctx: GraphicsContext, _ boss: Boss) {
        let c = point(boss.x, boss.y)
        let r = boss.radius * Double(scale)
        let seed: UInt64 = 0x7174
        let body = Blob.stone(center: c, radius: r, sides: 8, jitter: 0.22, angle: 0.3, seed: seed, rounding: 0.2)
        ctx.fill(body, with: .color(Palette.lavaCrust))
        var inner = ctx
        inner.clip(to: body)
        inner.fill(Path(CGRect(x: c.x - r, y: c.y + r * 0.2, width: r * 2, height: r)), with: .color(.black.opacity(0.3)))
        // Glowing magma cracks.
        let glow = boss.mode == .windup ? Palette.lavaGlow : Palette.lava
        inner.stroke(Blob.fissures(center: c, radius: r, count: 5, seed: seed ^ 9),
                     with: .color(glow), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        // Shoulders of crust.
        for side in [-1.0, 1.0] {
            let shoulder = Blob.stone(center: CGPoint(x: c.x + side * r * 0.95, y: c.y - r * 0.35), radius: r * 0.45,
                                      sides: 6, jitter: 0.25, angle: side, seed: seed ^ UInt64(side + 3), rounding: 0.2)
            ctx.fill(shoulder, with: .color(Palette.lavaCrust))
            Ink.outline(ctx, shoulder, width: 2.4)
        }
        // Furnace eyes and mouth.
        for side in [-1.0, 1.0] {
            ctx.fill(Path(ellipseIn: CGRect(x: c.x + side * r * 0.32 - r * 0.13, y: c.y - r * 0.3, width: r * 0.26, height: r * 0.2)),
                     with: .color(Palette.lavaGlow))
        }
        ctx.fill(Path(roundedRect: CGRect(x: c.x - r * 0.35, y: c.y + r * 0.1, width: r * 0.7, height: r * 0.22), cornerRadius: r * 0.1),
                 with: .color(glow))
        Ink.outline(ctx, body, width: 3)
        if boss.hitFlash > 0 { ctx.stroke(body, with: .color(.white.opacity(boss.hitFlash)), lineWidth: 4) }
        drawCrown(ctx, at: CGPoint(x: c.x, y: c.y - r * 0.95), size: r * 0.8)
    }

    /// Warning lanes, then erupting columns, during the Titan's attack.
    private func drawGeysers(_ ctx: GraphicsContext) {
        guard let boss = world.boss, !boss.defeated, !boss.geysers.isEmpty else { return }
        let top = point(0, boss.arenaTop).y
        let bottom = point(0, boss.arenaBottom).y
        for lane in boss.geysers {
            let x = point(lane, 0).x
            let half = 0.75 * Double(scale)
            let column = CGRect(x: x - half, y: top, width: half * 2, height: bottom - top)
            if boss.mode == .windup {
                let blink = world.reduceMotion ? 0.5 : 0.35 + 0.3 * sin(world.spin * 2)
                ctx.fill(Path(column), with: .color(Palette.lava.opacity(0.12 + blink * 0.2)))
                var edge = Path()
                edge.move(to: CGPoint(x: x - half, y: top)); edge.addLine(to: CGPoint(x: x - half, y: bottom))
                edge.move(to: CGPoint(x: x + half, y: top)); edge.addLine(to: CGPoint(x: x + half, y: bottom))
                ctx.stroke(edge, with: .color(Palette.lava.opacity(0.8)), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            } else if boss.mode == .attack {
                ctx.fill(Path(column.insetBy(dx: -7, dy: 0)), with: .color(Palette.lava.opacity(0.3)))
                ctx.fill(Path(roundedRect: column, cornerRadius: half),
                         with: .linearGradient(Gradient(colors: [Palette.lavaGlow, Palette.lava]),
                                               startPoint: CGPoint(x: x, y: top), endPoint: CGPoint(x: x, y: bottom)))
            }
        }
    }

    private func drawFallingBoulder(_ ctx: GraphicsContext, _ shot: Shot, at c: CGPoint) {
        let r = 0.42 * Double(scale)
        var streak = Path()
        streak.move(to: CGPoint(x: c.x, y: c.y - r * 3))
        streak.addLine(to: CGPoint(x: c.x, y: c.y))
        ctx.stroke(streak, with: .color(Palette.rockLight(hardness: 2).opacity(0.35)),
                   style: StrokeStyle(lineWidth: r * 1.2, lineCap: .round))
        let rock = Blob.stone(center: c, radius: r, sides: 6, jitter: 0.3, angle: Double(shot.id),
                              seed: UInt64(shot.id) | 1, rounding: 0.2)
        ctx.fill(rock, with: .color(Palette.rock(hardness: 2)))
        ctx.stroke(rock, with: .color(Palette.ink), lineWidth: 4.4)
        ctx.stroke(rock, with: .color(Palette.hazard), lineWidth: 2)
    }

    /// Lights Out: everything but a pool around the drill (pushed toward the
    /// heading, like a headlight) goes black.
    private func drawDarkness(_ ctx: GraphicsContext) {
        // Lights Out, or the Abyss Angler's blackout. The Abyss Lantern sees
        // through both.
        guard !world.gear.seeInDark else { return }
        var amount = 0.0
        if let event = world.event, event.kind == .darkness { amount = event.intensity }
        if let boss = world.boss, !boss.defeated, boss.blackout > 0 {
            amount = max(amount, min(1, boss.blackout / 0.5, (4.5 - boss.blackout) / 0.4 + 0.2))
        }
        guard amount > 0 else { return }
        let ahead = world.headingVector
        let center = point(world.x + ahead.x * 1.2, world.depth + ahead.y * 1.2)
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
            Gradient(colors: [.black.opacity(0), .black.opacity(0.94 * amount)]),
            center: center, startRadius: 1.4 * Double(scale), endRadius: 3.6 * Double(scale)))
        // Lures still glow through the dark: that is how you track anglers.
        var lit = ctx
        if world.shake > 0.01, world.shakeScale > 0 { lit.opacity = 1 }
        for enemy in world.enemies where enemy.kind == .angler && !enemy.dead && enemy.awake {
            drawLure(lit, enemy.x, enemy.y, heading: enemy.heading, radius: enemy.kind.radius)
        }
        if let boss = world.boss, !boss.defeated, boss.kind == .abyssAngler, boss.engaged {
            drawLure(lit, boss.x, boss.y, heading: boss.heading, radius: boss.radius)
        }
    }

    // MARK: - New critters

    private func drawMole(_ ctx: GraphicsContext, _ mole: Enemy) {
        let r = mole.radius * Double(scale)
        var c = point(mole.x, mole.y)
        let layer = Strata.layer(for: max(0, mole.y))
        guard mole.surfaced else {
            // Underground: a travelling mound of dirt, shaking before it pops.
            if mole.mode == .windup && !world.reduceMotion { c.x += sin(world.spin * 9) * 2.5 }
            var mound = Path()
            mound.move(to: CGPoint(x: c.x - r * 1.2, y: c.y + r * 0.35))
            mound.addQuadCurve(to: CGPoint(x: c.x + r * 1.2, y: c.y + r * 0.35), control: CGPoint(x: c.x, y: c.y - r * 1.3))
            mound.closeSubpath()
            ctx.fill(mound, with: .color(layer.pebble))
            var cracks = Path()
            cracks.move(to: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.2)); cracks.addLine(to: CGPoint(x: c.x, y: c.y + r * 0.1))
            cracks.addLine(to: CGPoint(x: c.x + r * 0.35, y: c.y - r * 0.15))
            ctx.stroke(cracks, with: .color(Palette.ink.opacity(0.6)), lineWidth: 1.6)
            Ink.outline(ctx, mound, width: 2)
            if mole.mode == .windup { Ink.warning(ctx, center: c, radius: r * 1.6) }
            return
        }
        var m = ctx
        m.translateBy(x: c.x, y: c.y)
        m.rotate(by: .radians(mole.heading))
        // Digging claws either side, then the round body, then the nose (+y).
        for side in [-1.0, 1.0] {
            let paw = Blob.chunky([CGPoint(x: side * r * 0.7, y: r * 0.1), CGPoint(x: side * r * 1.25, y: r * 0.35),
                                   CGPoint(x: side * r * 1.1, y: r * 0.75), CGPoint(x: side * r * 0.65, y: r * 0.55)], rounding: 0.2)
            m.fill(paw, with: .color(Palette.moleNose.opacity(0.9)))
            Ink.outline(m, paw, width: 1.8)
        }
        let body = Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2.05))
        m.fill(body, with: .color(Palette.mole))
        var belly = m
        belly.clip(to: body)
        belly.fill(Path(ellipseIn: CGRect(x: -r * 0.6, y: r * 0.05, width: r * 1.2, height: r)), with: .color(Palette.mole.mix(with: .white, by: 0.25)))
        Ink.outline(m, body, width: 2.3)
        let nose = Path(ellipseIn: CGRect(x: -r * 0.22, y: r * 0.78, width: r * 0.44, height: r * 0.34))
        m.fill(nose, with: .color(Palette.moleNose))
        m.stroke(nose, with: .color(Palette.ink), lineWidth: 1.6)
        for side in [-1.0, 1.0] {
            m.fill(Path(ellipseIn: CGRect(x: side * r * 0.32 - r * 0.07, y: r * 0.35, width: r * 0.14, height: r * 0.14)),
                   with: .color(Palette.ink))
        }
        if mole.hitFlash > 0 { m.stroke(body, with: .color(.white.opacity(mole.hitFlash)), lineWidth: 3) }
    }

    private func drawSpider(_ ctx: GraphicsContext, _ spider: Enemy) {
        let r = spider.radius * Double(scale)
        let c = point(spider.x, spider.y)
        // Silk up to its anchor.
        var silk = Path()
        silk.move(to: CGPoint(x: c.x, y: point(spider.x, spider.homeY).y))
        silk.addLine(to: CGPoint(x: c.x, y: c.y - r * 0.6))
        ctx.stroke(silk, with: .color(Palette.shine.opacity(0.7)), lineWidth: 1.4)
        let scuttle = world.reduceMotion ? 0 : sin(world.spin * 1.4 + spider.phase) * r * 0.12
        var legs = Path()
        for side in [-1.0, 1.0] {
            for k in 0..<4 {
                let y0 = c.y - r * 0.2 + Double(k) * r * 0.22
                let knee = CGPoint(x: c.x + side * r * 1.0, y: y0 - r * 0.5 + (k % 2 == 0 ? scuttle : -scuttle))
                legs.move(to: CGPoint(x: c.x + side * r * 0.35, y: y0))
                legs.addLine(to: knee)
                legs.addLine(to: CGPoint(x: c.x + side * r * 1.35, y: y0 + r * 0.45))
            }
        }
        ctx.stroke(legs, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
        let abdomen = Path(ellipseIn: CGRect(x: c.x - r * 0.75, y: c.y - r * 0.55, width: r * 1.5, height: r * 1.4))
        ctx.fill(abdomen, with: .color(Palette.spider))
        Ink.outline(ctx, abdomen, width: 2.2)
        let head = Path(ellipseIn: CGRect(x: c.x - r * 0.42, y: c.y + r * 0.55, width: r * 0.84, height: r * 0.7))
        ctx.fill(head, with: .color(Palette.spider.mix(with: .white, by: 0.12)))
        Ink.outline(ctx, head, width: 2)
        for (dx, dy) in [(-0.18, 0.8), (0.18, 0.8), (-0.08, 0.98), (0.08, 0.98)] {
            ctx.fill(Path(ellipseIn: CGRect(x: c.x + dx * r - r * 0.07, y: c.y + dy * r - r * 0.07, width: r * 0.14, height: r * 0.14)),
                     with: .color(spider.mode == .attack ? Palette.hazard : Palette.hazardShadow))
        }
        Ink.shine(ctx, at: CGPoint(x: c.x - r * 0.28, y: c.y - r * 0.2), size: r * 0.4, opacity: 0.5)
        if spider.hitFlash > 0 { ctx.stroke(abdomen, with: .color(.white.opacity(spider.hitFlash)), lineWidth: 3) }
    }

    private func drawCentipede(_ ctx: GraphicsContext, _ centipede: Enemy) {
        let s = Double(scale)
        let r = centipede.radius * s
        // Armoured plates from the tail forward, each with a pair of legs.
        for (k, segment) in centipede.segments.enumerated().reversed() {
            let c = point(segment.x, segment.y)
            let pr = r * (0.92 - Double(k) * 0.03)
            let wiggle = world.reduceMotion ? 0 : sin(world.spin * 1.6 + Double(k)) * pr * 0.25
            var legs = Path()
            legs.move(to: CGPoint(x: c.x - pr * 1.25, y: c.y + wiggle)); legs.addLine(to: CGPoint(x: c.x + pr * 1.25, y: c.y - wiggle))
            ctx.stroke(legs, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            let plate = Path(ellipseIn: CGRect(x: c.x - pr, y: c.y - pr * 0.8, width: pr * 2, height: pr * 1.6))
            ctx.fill(plate, with: .color(k % 2 == 0 ? Palette.centipede : Palette.centipedeShade))
            Ink.outline(ctx, plate, width: 1.8)
        }
        let c = point(centipede.x, centipede.y)
        var h = ctx
        h.translateBy(x: c.x, y: c.y)
        h.rotate(by: .radians(centipede.heading))
        var feelers = Path()
        for side in [-1.0, 1.0] {
            feelers.move(to: CGPoint(x: side * r * 0.3, y: r * 0.6))
            feelers.addQuadCurve(to: CGPoint(x: side * r * 1.1, y: r * 1.8), control: CGPoint(x: side * r * 1.2, y: r * 0.9))
        }
        h.stroke(feelers, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        let head = Path(ellipseIn: CGRect(x: -r, y: -r * 0.9, width: r * 2, height: r * 1.9))
        h.fill(head, with: .color(Palette.centipede.mix(with: .white, by: 0.12)))
        Ink.outline(h, head, width: 2.2)
        for side in [-1.0, 1.0] {
            h.fill(Path(ellipseIn: CGRect(x: side * r * 0.4 - r * 0.12, y: r * 0.2, width: r * 0.24, height: r * 0.24)), with: .color(Palette.ink))
            let jaw = Blob.chunky([CGPoint(x: side * r * 0.2, y: r * 0.8), CGPoint(x: side * r * 0.55, y: r * 1.2),
                                   CGPoint(x: side * r * 0.1, y: r * 1.1)], rounding: 0.1)
            h.fill(jaw, with: .color(Palette.shine))
            h.stroke(jaw, with: .color(Palette.ink), lineWidth: 1.4)
        }
        if centipede.hitFlash > 0 { h.stroke(head, with: .color(.white.opacity(centipede.hitFlash)), lineWidth: 3) }
    }

    private func drawSlime(_ ctx: GraphicsContext, _ slime: Enemy) {
        let r = slime.radius * Double(scale)
        let c = point(slime.x, slime.y)
        // Squash between hops, stretch mid-hop.
        let hop = world.reduceMotion ? 0.5 : max(0, sin(world.spin * 2 + slime.phase))
        let w = r * (1.12 - 0.22 * hop), h = r * (0.85 + 0.3 * hop)
        var blob = Path()
        blob.move(to: CGPoint(x: c.x - w, y: c.y + h * 0.55))
        blob.addQuadCurve(to: CGPoint(x: c.x + w, y: c.y + h * 0.55), control: CGPoint(x: c.x, y: c.y - h * 2.0))
        blob.addQuadCurve(to: CGPoint(x: c.x - w, y: c.y + h * 0.55), control: CGPoint(x: c.x, y: c.y + h * 0.95))
        blob.closeSubpath()
        ctx.fill(blob, with: .color(Palette.slime.opacity(0.92)))
        var facets = ctx
        facets.clip(to: blob)
        // Prism facets: a couple of lighter and darker wedges.
        facets.fill(Blob.chunky([CGPoint(x: c.x - w, y: c.y - h), CGPoint(x: c.x, y: c.y - h * 1.2), CGPoint(x: c.x - w * 0.3, y: c.y + h)], rounding: 0.02),
                    with: .color(.white.opacity(0.25)))
        facets.fill(Blob.chunky([CGPoint(x: c.x + w * 0.2, y: c.y - h), CGPoint(x: c.x + w, y: c.y), CGPoint(x: c.x + w * 0.4, y: c.y + h)], rounding: 0.02),
                    with: .color(Palette.slimeShade.opacity(0.6)))
        Ink.outline(ctx, blob, width: 2.2)
        for side in [-1.0, 1.0] {
            ctx.fill(Path(ellipseIn: CGRect(x: c.x + side * w * 0.32 - r * 0.1, y: c.y - h * 0.15, width: r * 0.2, height: r * 0.26)),
                     with: .color(Palette.ink))
        }
        Ink.shine(ctx, at: CGPoint(x: c.x - w * 0.4, y: c.y - h * 0.6), size: r * 0.5)
        if slime.hitFlash > 0 { ctx.stroke(blob, with: .color(.white.opacity(slime.hitFlash)), lineWidth: 3) }
    }

    private func drawSlug(_ ctx: GraphicsContext, _ slug: Enemy) {
        let r = slug.radius * Double(scale)
        let c = point(slug.x, slug.y)
        Ink.halo(ctx, center: c, radius: r * 1.7, color: Palette.lava, strength: 0.9)
        var s = ctx
        s.translateBy(x: c.x, y: c.y)
        s.rotate(by: .radians(slug.heading))
        let pulse = world.reduceMotion ? 1 : 1 + 0.05 * sin(world.spin * 1.2 + slug.phase)
        let body = Path(roundedRect: CGRect(x: -r * 0.62, y: -r * 1.25 * pulse, width: r * 1.24, height: r * 2.4 * pulse),
                        cornerRadius: r * 0.62)
        s.fill(body, with: .color(Palette.slug))
        var spots = s
        spots.clip(to: body)
        for (dx, dy) in [(-0.25, -0.6), (0.2, -0.2), (-0.15, 0.25), (0.25, 0.55)] {
            spots.fill(Path(ellipseIn: CGRect(x: dx * r - r * 0.14, y: dy * r - r * 0.14, width: r * 0.28, height: r * 0.28)),
                       with: .color(Palette.slugSpot))
        }
        Ink.outline(s, body, width: 2.2)
        var stalks = Path()
        for side in [-1.0, 1.0] {
            stalks.move(to: CGPoint(x: side * r * 0.2, y: r * 1.05))
            stalks.addLine(to: CGPoint(x: side * r * 0.42, y: r * 1.55))
        }
        s.stroke(stalks, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        for side in [-1.0, 1.0] {
            let eye = Path(ellipseIn: CGRect(x: side * r * 0.42 - r * 0.12, y: r * 1.5, width: r * 0.24, height: r * 0.24))
            s.fill(eye, with: .color(Palette.slugSpot))
            s.stroke(eye, with: .color(Palette.ink), lineWidth: 1.4)
        }
        if slug.hitFlash > 0 { s.stroke(body, with: .color(.white.opacity(slug.hitFlash)), lineWidth: 3) }
    }

    // MARK: - The Abyss

    private func drawJelly(_ ctx: GraphicsContext, _ jelly: Enemy) {
        let c = point(jelly.x, jelly.y)
        let charging = jelly.mode == .windup
        let beat = world.reduceMotion ? 0.5 : 0.5 + 0.5 * sin(world.spin * 0.6 + jelly.phase)
        let r = jelly.kind.radius * Double(scale) * (0.92 + 0.12 * beat)
        if charging {
            Ink.halo(ctx, center: c, radius: GameWorld.jellyShockRadius * Double(scale) * 0.9,
                     color: Palette.jelly, strength: 1.2)
            Ink.warning(ctx, center: c, radius: GameWorld.jellyShockRadius * Double(scale), color: Palette.jelly)
        }
        // Tentacles trail behind the bell.
        var tentacles = Path()
        for k in 0..<4 {
            let x0 = c.x + (Double(k) - 1.5) * r * 0.42
            tentacles.move(to: CGPoint(x: x0, y: c.y + r * 0.2))
            for step in 1...4 {
                let y = c.y + r * 0.2 + Double(step) * r * 0.32
                let sway = sin(world.spin * 0.5 + Double(k) + Double(step)) * r * 0.16
                tentacles.addLine(to: CGPoint(x: x0 + sway, y: y))
            }
        }
        ctx.stroke(tentacles, with: .color(Palette.jellyShadow), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        // Bell.
        var bell = Path()
        bell.move(to: CGPoint(x: c.x - r, y: c.y + r * 0.25))
        bell.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y + r * 0.25), control: CGPoint(x: c.x, y: c.y - r * 1.6))
        bell.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y + r * 0.25), control: CGPoint(x: c.x, y: c.y + r * 0.55))
        bell.closeSubpath()
        ctx.fill(bell, with: .color(Palette.jelly.opacity(0.85)))
        var inner = ctx
        inner.clip(to: bell)
        inner.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.45, y: c.y - r * 0.55, width: r * 0.9, height: r * 0.6)),
                   with: .color(Palette.jellyShadow.opacity(0.6)))
        Ink.outline(ctx, bell, width: 2)
        Ink.shine(ctx, at: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.5), size: r * 0.5, opacity: 0.8)
        if charging, Int(world.spin * 4) % 2 == 0 {
            // Crackle: a few short zig-zags off the bell.
            var bolt = Path()
            for k in 0..<3 {
                let a = Double(k) / 3 * 2 * .pi + world.spin
                bolt.move(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
                bolt.addLine(to: CGPoint(x: c.x + cos(a + 0.2) * r * 1.4, y: c.y + sin(a + 0.2) * r * 1.4))
                bolt.addLine(to: CGPoint(x: c.x + cos(a - 0.1) * r * 1.7, y: c.y + sin(a - 0.1) * r * 1.7))
            }
            ctx.stroke(bolt, with: .color(Palette.shine), lineWidth: 2)
        }
        if jelly.hitFlash > 0 { ctx.stroke(bell, with: .color(.white.opacity(jelly.hitFlash)), lineWidth: 3) }
    }

    private func drawAngler(_ ctx: GraphicsContext, _ angler: Enemy, radius: Double? = nil) {
        let size = radius ?? angler.kind.radius
        let r = size * Double(scale)
        let c = point(angler.x, angler.y)
        var a = ctx
        a.translateBy(x: c.x, y: c.y)
        a.rotate(by: .radians(angler.heading))
        // Tail fin behind, body, then the jaw facing the direction of travel (+y).
        let tail = Blob.chunky([CGPoint(x: 0, y: -r * 0.7), CGPoint(x: -r * 0.6, y: -r * 1.45),
                                CGPoint(x: r * 0.6, y: -r * 1.45)], rounding: 0.15)
        a.fill(tail, with: .color(Palette.angler))
        Ink.outline(a, tail, width: 2)
        let body = Path(ellipseIn: CGRect(x: -r * 0.85, y: -r * 0.95, width: r * 1.7, height: r * 1.9))
        a.fill(body, with: .color(Palette.angler))
        var belly = a
        belly.clip(to: body)
        belly.fill(Path(ellipseIn: CGRect(x: -r * 0.6, y: -r * 0.2, width: r * 1.2, height: r * 1.2)),
                   with: .color(Palette.anglerBelly))
        Ink.outline(a, body, width: 2.4)
        // Gaping mouth with needle teeth.
        let open = angler.mode == .attack || angler.mode == .windup ? 1.0 : 0.55
        let mouth = Path(ellipseIn: CGRect(x: -r * 0.55, y: r * 0.35, width: r * 1.1, height: r * 0.55 * open))
        a.fill(mouth, with: .color(Palette.ink))
        for k in 0..<5 {
            let tx = -r * 0.42 + Double(k) * r * 0.21
            a.fill(Blob.triangle(CGPoint(x: tx - r * 0.05, y: r * 0.37), CGPoint(x: tx + r * 0.05, y: r * 0.37),
                                 CGPoint(x: tx, y: r * 0.37 + r * 0.16)), with: .color(Palette.shine))
        }
        // One big pale eye.
        for side in [-1.0, 1.0] {
            let eye = CGRect(x: side * r * 0.42 - r * 0.15, y: r * 0.02, width: r * 0.3, height: r * 0.3)
            a.fill(Path(ellipseIn: eye), with: .color(Palette.shine))
            a.fill(Path(ellipseIn: eye.insetBy(dx: r * 0.08, dy: r * 0.08)),
                   with: .color(angler.chasing ? Palette.hazard : Palette.ink))
        }
        if angler.hitFlash > 0 { a.stroke(body, with: .color(.white.opacity(angler.hitFlash)), lineWidth: 3) }
        drawLure(ctx, angler.x, angler.y, heading: angler.heading, radius: size)
    }

    /// The angler's lure: a stalk curling forward to a glowing pearl.
    private func drawLure(_ ctx: GraphicsContext, _ x: Double, _ y: Double, heading: Double, radius: Double) {
        let r = radius * Double(scale)
        let c = point(x, y)
        var a = ctx
        a.translateBy(x: c.x, y: c.y)
        a.rotate(by: .radians(heading))
        let bob = world.reduceMotion ? 0 : sin(world.spin * 0.4 + x) * r * 0.08
        let bulb = CGPoint(x: r * 0.25, y: r * 1.55 + bob)
        var stalk = Path()
        stalk.move(to: CGPoint(x: 0, y: -r * 0.6))
        stalk.addQuadCurve(to: bulb, control: CGPoint(x: r * 1.1, y: r * 0.2))
        a.stroke(stalk, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        let pearl = Strata.layer(for: max(0, y)).ore
        Ink.halo(a, center: bulb, radius: r * 0.7, color: Palette.abyssGlow, strength: 1.6)
        let ball = Path(ellipseIn: CGRect(x: bulb.x - r * 0.2, y: bulb.y - r * 0.2, width: r * 0.4, height: r * 0.4))
        a.fill(ball, with: .color(pearl.color))
        a.stroke(ball, with: .color(Palette.ink), lineWidth: 1.6)
    }

    private func drawShieldBubble(_ ctx: GraphicsContext) {
        guard world.shieldReady else { return }
        let c = point(world.x, world.depth + 0.25)
        let r = 1.25 * Double(scale)
        let pulse = world.reduceMotion ? 0.5 : 0.4 + 0.15 * sin(world.spin * 0.4)
        let bubble = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.fill(bubble, with: .color(Palette.window.opacity(pulse * 0.25)))
        ctx.stroke(bubble, with: .color(Palette.window.opacity(pulse + 0.2)), lineWidth: 2)
    }

    /// Worm Queen underground: a rumbling warning ring where she will surface.
    private func drawBurrowMark(_ ctx: GraphicsContext, _ boss: Boss) {
        guard let mark = boss.mark else { return }
        let c = point(mark.x, mark.y)
        let locked = boss.timer <= 0.5
        let pulse = world.reduceMotion ? 1 : 1 + 0.12 * sin(world.spin * 2)
        let r = boss.radius * 1.5 * Double(scale) * pulse
        let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.fill(ring, with: .color(Palette.hazard.opacity(locked ? 0.28 : 0.12)))
        ctx.stroke(ring, with: .color(Palette.hazard.opacity(0.9)),
                   style: StrokeStyle(lineWidth: locked ? 3.5 : 2, dash: locked ? [] : [8, 6]))
        var rng = SeededRandom(seed: UInt64(world.spin * 7) | 1)
        for _ in 0..<6 {
            let a = rng.double(0...(.pi * 2)), d = rng.double(0...(r * 0.8)), s = rng.double(2...5)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x + cos(a) * d - s, y: c.y + sin(a) * d - s, width: s * 2, height: s * 2)),
                     with: .color(Strata.layer(for: max(0, mark.y)).pebble))
        }
    }

    /// Bat Matriarch's shockwave: a ring with one open gap.
    private func drawScreech(_ ctx: GraphicsContext, _ boss: Boss) {
        guard let ring = boss.ring else { return }
        let c = point(boss.x, boss.y)
        let r = ring * Double(scale)
        let gap = GameWorld.screechGap
        var arc = Path()
        arc.addArc(center: c, radius: r, startAngle: .radians(boss.ringGap + gap),
                   endAngle: .radians(boss.ringGap - gap + 2 * .pi), clockwise: false)
        let fade = max(0.25, 1 - ring / 15)
        ctx.stroke(arc, with: .color(Palette.batWing.opacity(0.9 * fade)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        ctx.stroke(arc, with: .color(.white.opacity(0.6 * fade)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    private func drawCrown(_ ctx: GraphicsContext, at center: CGPoint, size: Double) {
        let w = size * 0.9, h = size * 0.45
        var crown = Path()
        crown.move(to: CGPoint(x: center.x - w / 2, y: center.y))
        crown.addLine(to: CGPoint(x: center.x - w / 2, y: center.y - h))
        crown.addLine(to: CGPoint(x: center.x - w / 4, y: center.y - h * 0.5))
        crown.addLine(to: CGPoint(x: center.x, y: center.y - h * 1.15))
        crown.addLine(to: CGPoint(x: center.x + w / 4, y: center.y - h * 0.5))
        crown.addLine(to: CGPoint(x: center.x + w / 2, y: center.y - h))
        crown.addLine(to: CGPoint(x: center.x + w / 2, y: center.y))
        crown.closeSubpath()
        ctx.fill(crown, with: .color(Palette.gold))
        Ink.outline(ctx, crown, width: 2)
    }

    private func drawDazedStars(_ ctx: GraphicsContext, at center: CGPoint) {
        for k in 0..<3 {
            let angle = world.spin * 0.6 + Double(k) / 3 * 2 * .pi
            let p = CGPoint(x: center.x + cos(angle) * 22, y: center.y + sin(angle) * 7)
            ctx.fill(Blob.sparkle(center: p, size: 12), with: .color(Palette.gold))
        }
    }

    private func drawShots(_ ctx: GraphicsContext) {
        for shot in world.shots {
            let c = point(shot.x, shot.y)
            if shot.style == .boulder {
                drawFallingBoulder(ctx, shot, at: c)
                continue
            }
            if shot.style == .homing {
                let r = 0.3 * Double(scale)
                Ink.halo(ctx, center: c, radius: r * 1.9, color: Palette.hazard, strength: 1.4)
                let core = Shapes.spikePath(center: c, radius: r, points: 5, inner: 0.5, angle: world.spin * 0.5)
                ctx.fill(core, with: .color(Palette.spitter))
                Ink.outline(ctx, core, width: 2)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.3, y: c.y - r * 0.3, width: r * 0.6, height: r * 0.6)),
                         with: .color(.white))
                continue
            }
            let r = 0.22 * Double(scale)
            Ink.halo(ctx, center: c, radius: r * 1.8, color: shot.friendly ? Palette.window : Palette.spitter, strength: 1.3)
            var d = ctx
            d.translateBy(x: c.x, y: c.y)
            d.rotate(by: .radians(atan2(shot.vy, shot.vx)))
            let dart = Blob.chunky([CGPoint(x: r * 1.4, y: 0), CGPoint(x: -r * 0.6, y: -r * 0.6),
                                    CGPoint(x: -r * 1.0, y: 0), CGPoint(x: -r * 0.6, y: r * 0.6)], rounding: 0.1)
            d.fill(dart, with: .color(shot.friendly ? Palette.window : Palette.spitter))
            Ink.outline(d, dart, width: 1.8)
        }
    }

    private func drawWorm(_ ctx: GraphicsContext, _ worm: Enemy, radius: Double? = nil) {
        let size = radius ?? worm.kind.radius
        let s = Double(scale)
        let head = point(worm.x, worm.y)
        let wiggle = world.reduceMotion ? 0 : 1.0
        // Tail first so the head sits on top.
        for (k, segment) in worm.segments.enumerated().reversed() {
            let taper = 1 - Double(k + 1) * 0.09
            let r = size * s * taper * (1 + 0.06 * wiggle * sin(world.spin * 0.4 + Double(k)))
            let c = point(segment.x, segment.y)
            let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.fill(disc, with: .color(Palette.wormShadow))
            Ink.outline(ctx, disc, width: 2)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.88, y: c.y - r * 0.95, width: r * 1.6, height: r * 1.55)),
                     with: .color(Palette.worm))
            // Ring groove.
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 0.55, y: c.y - r * 0.55, width: r * 1.1, height: r * 1.1)),
                       with: .color(Palette.wormShadow.opacity(0.5)), lineWidth: 1.4)
        }

        let r = size * s
        if worm.chasing {
            Ink.warning(ctx, center: head, radius: r * 1.5)
        }
        var h = ctx
        h.translateBy(x: head.x, y: head.y)
        h.rotate(by: .radians(worm.heading))
        let skull = Path(ellipseIn: CGRect(x: -r, y: -r * 0.95, width: r * 2, height: r * 2.05))
        h.fill(skull, with: .color(Palette.worm))
        var lit = h
        lit.clip(to: skull)
        lit.fill(Path(CGRect(x: 0, y: -r, width: r, height: r * 2)), with: .color(Palette.wormShadow.opacity(0.55)))
        Ink.outline(h, skull, width: 2.4)
        // Mouth ring with teeth, facing the direction of travel.
        let mouth = CGRect(x: -r * 0.55, y: r * 0.35, width: r * 1.1, height: r * 0.6)
        h.fill(Path(ellipseIn: mouth), with: .color(Palette.background))
        for t in 0..<4 {
            let tx = mouth.minX + mouth.width * (0.2 + 0.2 * Double(t))
            h.fill(Blob.triangle(CGPoint(x: tx - r * 0.07, y: mouth.minY + 1),
                                 CGPoint(x: tx + r * 0.07, y: mouth.minY + 1),
                                 CGPoint(x: tx, y: mouth.minY + r * 0.2)),
                   with: .color(Palette.wormBelly))
        }
        for side in [-1.0, 1.0] {
            let eye = CGRect(x: side * r * 0.42 - r * 0.2, y: -r * 0.05, width: r * 0.4, height: r * 0.4)
            h.fill(Path(ellipseIn: eye), with: .color(.white))
            h.fill(Path(ellipseIn: eye.insetBy(dx: r * 0.1, dy: r * 0.1).offsetBy(dx: 0, dy: r * 0.05)),
                   with: .color(worm.chasing ? Palette.hazardShadow : Palette.background))
            if worm.chasing {
                // Angry brow.
                var brow = Path()
                brow.move(to: CGPoint(x: side * r * 0.7, y: -r * 0.12))
                brow.addLine(to: CGPoint(x: side * r * 0.18, y: r * 0.02))
                h.stroke(brow, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            }
        }
        if worm.hitFlash > 0 {
            h.stroke(skull, with: .color(.white.opacity(worm.hitFlash)), lineWidth: 3)
        }
    }

    private func drawBeetle(_ ctx: GraphicsContext, _ beetle: Enemy, radius: Double? = nil) {
        let s = Double(scale)
        let c = point(beetle.x, beetle.y)
        let r = (radius ?? beetle.kind.radius) * s
        let dangerous = !beetle.isKillable(power: world.loadout.power)
        var b = ctx
        b.translateBy(x: c.x, y: c.y)
        b.rotate(by: .radians(beetle.heading))
        // Six scuttling legs.
        let step = world.reduceMotion ? 0 : sin(world.spin * 0.9 + beetle.phase) * 0.25
        for side in [-1.0, 1.0] {
            for k in 0..<3 {
                let y = r * (-0.45 + 0.45 * Double(k))
                let swing = (k % 2 == 0 ? step : -step) * r
                var leg = Path()
                leg.move(to: CGPoint(x: side * r * 0.6, y: y))
                leg.addLine(to: CGPoint(x: side * r * 1.05, y: y + swing - r * 0.1))
                leg.addLine(to: CGPoint(x: side * r * 1.2, y: y + swing + r * 0.15))
                b.stroke(leg, with: .color(Palette.ink),
                         style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        // Head and mandibles lead.
        let head = Path(ellipseIn: CGRect(x: -r * 0.45, y: r * 0.55, width: r * 0.9, height: r * 0.6))
        b.fill(head, with: .color(Palette.beetle))
        for side in [-1.0, 1.0] {
            var jaw = Path()
            jaw.move(to: CGPoint(x: side * r * 0.25, y: r * 1.05))
            jaw.addQuadCurve(to: CGPoint(x: side * r * 0.05, y: r * 1.4),
                             control: CGPoint(x: side * r * 0.45, y: r * 1.35))
            b.stroke(jaw, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            b.fill(Path(ellipseIn: CGRect(x: side * r * 0.22 - r * 0.1, y: r * 0.72, width: r * 0.2, height: r * 0.2)),
                   with: .color(Palette.beetleEye))
        }
        // Domed shell split down the middle.
        let shell = Path(ellipseIn: CGRect(x: -r * 0.78, y: -r * 0.9, width: r * 1.56, height: r * 1.6))
        b.fill(shell, with: .color(Palette.beetle))
        var sheen = b
        sheen.clip(to: shell)
        sheen.fill(Path(ellipseIn: CGRect(x: -r * 0.6, y: -r * 0.8, width: r * 0.6, height: r * 1.1)),
                   with: .color(Palette.beetleSheen.opacity(0.55)))
        sheen.fill(Path(ellipseIn: CGRect(x: r * 0.08, y: -r * 0.75, width: r * 0.42, height: r * 0.9)),
                   with: .color(Palette.beetleSheen.opacity(0.25)))
        var seam = Path()
        seam.move(to: CGPoint(x: 0, y: -r * 0.9))
        seam.addLine(to: CGPoint(x: 0, y: r * 0.7))
        b.stroke(seam, with: .color(.black.opacity(0.45)), lineWidth: 2)
        strokeRim(b, shell, dangerous: dangerous, flash: beetle.hitFlash)
    }

    private func layerFor(_ rock: Obstacle) -> StrataLayer { Strata.layer(for: max(0, rock.y)) }

    /// A handful of mineral flecks, so stone does not read as a flat shape.
    private func drawSpeckle(_ ctx: GraphicsContext, center: CGPoint, radius: Double,
                             seed: UInt64, layer: StrataLayer) {
        var rng = SeededRandom(seed: seed ^ 0x5EED)
        for _ in 0..<4 {
            let angle = rng.double(0...(.pi * 2))
            let distance = rng.double(0...(radius * 0.75))
            let dot = rng.double(1.4...3.0)
            ctx.fill(Path(ellipseIn: CGRect(x: center.x + cos(angle) * distance - dot / 2,
                                            y: center.y + sin(angle) * distance - dot / 2,
                                            width: dot, height: dot)),
                     with: .color(layer.vein.opacity(rng.double(0.3...0.6))))
        }
    }

    /// Coral rim means    /// Coral rim means "this will hurt you". It turns neutral the moment a
    /// Power upgrade makes the rock drillable — the clearest signal we have.
    private func strokeRim(_ ctx: GraphicsContext, _ path: Path, dangerous: Bool, flash: Double) {
        if dangerous {
            // Ink border with the coral line riding inside it.
            ctx.stroke(path, with: .color(Palette.ink), lineWidth: 5)
            ctx.stroke(path, with: .color(Palette.hazard), lineWidth: 2.3)
        } else {
            Ink.outline(ctx, path, width: 2.8)
        }
        if flash > 0 {
            ctx.stroke(path, with: .color(.white.opacity(flash)), lineWidth: 3)
        }
    }

    // MARK: - Particles and the machine

    private func drawParticles(_ ctx: GraphicsContext) {
        for particle in world.particles {
            guard particle.y > cameraTop - 1, particle.y < cameraBottom + 1 else { continue }
            let center = point(particle.x, particle.y)
            let fade = max(0, min(1, particle.life / particle.maxLife))
            let radius = particle.size * Double(scale)
            switch particle.kind {
            case .dust, .spark:
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - radius / 2, y: center.y - radius / 2,
                                                width: radius, height: radius)),
                         with: .color(particle.color.opacity(fade * 0.9)))
            case .smoke:
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - radius / 2, y: center.y - radius / 2,
                                                width: radius, height: radius)),
                         with: .color(particle.color.opacity(fade * 0.3)))
            case .chunk:
                var chunk = ctx
                chunk.translateBy(x: center.x, y: center.y)
                chunk.rotate(by: .radians(particle.angle))
                chunk.fill(Path(roundedRect: CGRect(x: -radius / 2, y: -radius / 2,
                                                    width: radius, height: radius),
                                cornerRadius: radius * 0.25),
                           with: .color(particle.color.opacity(fade)))
            }
        }
    }

    private func drawOverdriveAura(_ ctx: GraphicsContext) {
        guard world.inOverdrive else { return }
        let center = point(world.x, world.depth + 0.3)
        let fade = min(1, world.overdrive / 0.6)
        let pulse = world.reduceMotion ? 1 : 0.85 + 0.15 * sin(world.spin * 0.7)
        let radius = 1.5 * Double(scale) * pulse
        Ink.halo(ctx, center: center, radius: radius, color: Palette.drillBody, strength: 1.5 * fade, aspect: 1.2)
    }

    private func drawDrill(_ ctx: GraphicsContext) {
        DrillArt.draw(in: ctx,
                      center: point(world.x, world.depth),
                      scale: scale,
                      spin: world.spin,
                      tilt: world.tilt,
                      heading: world.heading,
                      levels: world.levels,
                      skin: world.skin,
                      build: world.build,
                      damageFlash: world.damageFlash,
                      working: world.isEngaged,
                      reduceMotion: world.reduceMotion)
    }

    /// Radiating cracks around the drill the instant armour is lost.
    private func drawCracks(_ ctx: GraphicsContext) {
        guard world.damageFlash > 0.05 else { return }
        var rng = SeededRandom(seed: world.crackSeed)
        let center = point(world.x, world.depth)
        let opacity = world.damageFlash
        // A tight burst hugging the hull reads as impact; long spokes read as legs.
        let hull = Double(scale) * 0.74
        for _ in 0..<10 {
            let angle = rng.double(0...(.pi * 2))
            let length = rng.double(0.1...0.26) * Double(scale)
            func at(_ distance: Double) -> CGPoint {
                CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
            }
            var spoke = Path()
            spoke.move(to: at(hull))
            spoke.addLine(to: at(hull + length))
            ctx.stroke(spoke, with: .color(Palette.hazard.opacity(0.9 * opacity)),
                       style: StrokeStyle(lineWidth: 4 * opacity + 1, lineCap: .round))
        }
    }

    // MARK: - Screen space

    private func drawFlying(_ ctx: GraphicsContext) {
        for item in world.flying {
            let t = min(1, max(0, item.t))
            let eased = t * t * (3 - 2 * t)
            let inv = 1 - eased
            // Quadratic bezier so coins arc up and over to the counter.
            let x = inv * inv * item.from.x + 2 * inv * eased * item.control.x + eased * eased * item.to.x
            let y = inv * inv * item.from.y + 2 * inv * eased * item.control.y + eased * eased * item.to.y
            let radius = (1 - eased * 0.55) * (item.big ? 9.0 : 7.0)
            let color = item.color
            ctx.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                            width: radius * 2, height: radius * 2)),
                     with: .color(color.opacity(1 - eased * 0.3)))
        }
    }

    /// Streaks racing up the screen while Overdrive runs.
    private func drawSpeedLines(_ ctx: GraphicsContext) {
        guard world.inOverdrive, !world.reduceMotion else { return }
        let fade = min(1, world.overdrive / 0.6)
        var rng = SeededRandom(seed: 0x5BEED)
        let height = Double(size.height)
        for _ in 0..<14 {
            let x = rng.double(0...Double(size.width))
            let length = rng.double(60...160)
            let speed = rng.double(1.4...2.4)
            let travel = height + length
            let y = travel - (world.depth * Double(scale) * speed * 0.12)
                .truncatingRemainder(dividingBy: travel) - length
            var line = Path()
            line.move(to: CGPoint(x: x, y: y))
            line.addLine(to: CGPoint(x: x, y: y + length))
            ctx.stroke(line, with: .color(Palette.drillBody.opacity(0.22 * fade)),
                       style: StrokeStyle(lineWidth: rng.double(1.5...3.5), lineCap: .round))
        }
    }

    private func drawPopups(_ ctx: GraphicsContext) {
        for item in world.popups {
            let t = item.t
            let rise = t * (item.big ? 40 : 30)
            let opacity = t < 0.1 ? t / 0.1 : min(1, (1 - t) / 0.45)
            let pop = t < 0.12 ? 0.7 + t / 0.12 * 0.3 : 1.0
            var p = point(item.x, item.y)
            p.y -= rise
            comicText(ctx, item.text, size: (item.big ? 20 : 14) * pop, tint: item.tint, opacity: opacity, at: p)
        }
    }

    private func drawShouts(_ ctx: GraphicsContext) {
        // Newest at the anchor; older banners step up so two never overlap.
        let count = world.shouts.count
        for (index, shout) in world.shouts.enumerated() {
            let t = shout.t
            let rise = (1 - t) * 26
            let opacity = t < 0.15 ? t / 0.15 : min(1, (1 - t) / 0.4)
            let stack = Double(count - 1 - index) * 38
            let y = Double(size.height) * 0.46 - rise - stack
            // Long banners shrink to fit the column instead of running off it.
            let fit = min(28, Double(size.width) * 1.55 / Double(max(8, shout.text.count)))
            comicText(ctx, shout.text, size: fit, tint: shout.tint, opacity: opacity,
                      at: CGPoint(x: Double(size.width) / 2, y: y))
        }
    }

    /// Boss entrance: letterbox bars, a flash, a spotlight on the boss and a
    /// paper banner with its name sweeping across.
    private func drawBossIntro(_ ctx: GraphicsContext) {
        guard world.bossIntro > 0, let boss = world.boss else { return }
        let e = world.bossIntroIntensity
        let t = 1 - world.bossIntro / max(0.01, world.bossIntroLength)
        let w = Double(size.width), h = Double(size.height)
        let full = Path(CGRect(origin: .zero, size: size))
        // Spotlight: everything but the boss falls into shadow.
        let c = point(boss.x, boss.y)
        // At least ~2.4 m of light, so small (mini) and wide-winged bosses
        // are fully in the beam.
        let lit = max(boss.radius * 2.2, 2.4) * Double(scale)
        ctx.fill(full, with: .radialGradient(Gradient(colors: [.clear, Palette.ink.opacity(0.62 * e)]),
                                             center: c, startRadius: lit, endRadius: lit * 2.4))
        // Opening flash.
        if t < 0.1 { ctx.fill(full, with: .color(Palette.shine.opacity((1 - t / 0.1) * 0.45))) }
        // Letterbox bars.
        let bar = h * 0.11 * e
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: bar)), with: .color(Palette.ink))
        ctx.fill(Path(CGRect(x: 0, y: h - bar, width: w, height: bar)), with: .color(Palette.ink))
        // Banner: slides in from the left, holds, slides out to the right.
        let bannerW = w * 1.25, bannerH = 112.0
        var slide = 0.0
        if !world.reduceMotion {
            if t < 0.18 { let k = 1 - t / 0.18; slide = -k * k * w * 1.3 }
            else if t > 0.82 { let k = (t - 0.82) / 0.18; slide = k * k * w * 1.3 }
        }
        var banner = ctx
        banner.opacity = world.reduceMotion ? e : 1
        // Along the bottom, just above the letterbox bar; the intro camera
        // frames the boss in the upper half so it stays clear.
        let bannerY = h * (1 - 0.11 * e) - bannerH / 2 - w * 0.07
        banner.translateBy(x: w / 2 + slide, y: bannerY)
        banner.rotate(by: .degrees(-5))
        let strip = Path(CGRect(x: -bannerW / 2, y: -bannerH / 2, width: bannerW, height: bannerH))
        banner.fill(strip, with: .color(Palette.paper))
        banner.fill(Path(CGRect(x: -bannerW / 2, y: bannerH / 2 - 10, width: bannerW, height: 10)), with: .color(Palette.paperShade))
        var edges = Path()
        edges.move(to: CGPoint(x: -bannerW / 2, y: -bannerH / 2)); edges.addLine(to: CGPoint(x: bannerW / 2, y: -bannerH / 2))
        edges.move(to: CGPoint(x: -bannerW / 2, y: bannerH / 2)); edges.addLine(to: CGPoint(x: bannerW / 2, y: bannerH / 2))
        banner.stroke(edges, with: .color(Palette.ink), lineWidth: 4)
        // "BOSS" tag, name, and which biome it guards.
        let tag = Path(roundedRect: CGRect(x: -34, y: -bannerH / 2 + 10, width: 68, height: 20), cornerRadius: 10)
        banner.fill(tag, with: .color(Palette.hazard))
        banner.stroke(tag, with: .color(Palette.ink), lineWidth: 2)
        banner.draw(Text(boss.mini ? "MINI BOSS" : "BOSS").font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(Palette.shine), at: CGPoint(x: 0, y: -bannerH / 2 + 20))
        let fit = min(34, w * 1.5 / Double(max(8, boss.title.count)))
        comicText(banner, boss.title, size: fit, tint: boss.kind.tint, opacity: 1, at: CGPoint(x: 0, y: 4))
        let guarded = Strata.layer(for: max(0, boss.arenaTop)).name.capitalized
        banner.draw(Text(boss.mini ? "Back for more" : "Guardian of the \(guarded)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.ink.opacity(0.7)), at: CGPoint(x: 0, y: bannerH / 2 - 22))
    }

    /// Comic lettering: the word drawn in ink around itself, then in colour.
    private func comicText(_ ctx: GraphicsContext, _ text: String, size: Double, tint: Color,
                           opacity: Double, at p: CGPoint) {
        let font = Font.system(size: size, weight: .black, design: .rounded)
        let outline = max(1.5, size * 0.09)
        // Fade the lettering as one piece; fading each ink copy separately
        // stacks them into a dark smudge.
        ctx.drawLayer { layer in
            layer.opacity = opacity
            let ink = layer.resolve(Text(text).font(font).foregroundStyle(Palette.ink))
            for k in 0..<8 {
                let a = Double(k) / 8 * 2 * .pi
                layer.draw(ink, at: CGPoint(x: p.x + cos(a) * outline, y: p.y + sin(a) * outline + 1))
            }
            layer.draw(ink, at: CGPoint(x: p.x + 1, y: p.y + outline + 1.5))
            layer.draw(Text(text).font(font).foregroundStyle(tint), at: p)
        }
    }

    private func drawVignettes(_ ctx: GraphicsContext) {
        let full = Path(CGRect(origin: .zero, size: size))
        if world.damageFlash > 0.01 {
            ctx.fill(full, with: .radialGradient(
                Gradient(colors: [Palette.hazard.opacity(0),
                                  Palette.hazard.opacity(0.26 * world.damageFlash)]),
                center: CGPoint(x: size.width / 2, y: size.height / 2),
                startRadius: size.width * 0.5,
                endRadius: size.width * 1.05))
        }
        if world.treasureFlash > 0.01 {
            ctx.fill(full, with: .radialGradient(
                Gradient(colors: [Palette.gold.opacity(0),
                                  Palette.gold.opacity(0.3 * world.treasureFlash)]),
                center: CGPoint(x: size.width / 2, y: size.height / 2),
                startRadius: size.width * 0.15,
                endRadius: size.width * 0.9))
        }
        if let event = world.event, event.kind == .goldRush {
            ctx.fill(full, with: .radialGradient(
                Gradient(colors: [Palette.gold.opacity(0), Palette.gold.opacity(0.25 * event.intensity)]),
                center: CGPoint(x: size.width / 2, y: size.height / 2),
                startRadius: size.width * 0.4, endRadius: size.width * 1.05))
        }
        if world.inOverdrive {
            let fade = min(1, world.overdrive / 0.6)
            ctx.fill(full, with: .radialGradient(
                Gradient(colors: [Palette.drillBody.opacity(0),
                                  Palette.exhaust.opacity(0.28 * fade)]),
                center: CGPoint(x: size.width / 2, y: size.height / 2),
                startRadius: size.width * 0.45,
                endRadius: size.width * 1.05))
        }
        if world.recordPulse > 0.01 {
            ctx.stroke(full, with: .color(Palette.gold.opacity(0.5 * world.recordPulse)),
                       lineWidth: 14)
        }
        // Permanent soft darkening at the edges keeps the drill the focus.
        ctx.fill(full, with: .radialGradient(
            Gradient(colors: [.black.opacity(0), .black.opacity(0.3)]),
            center: CGPoint(x: size.width / 2, y: size.height * 0.4),
            startRadius: size.width * 0.35,
            endRadius: size.width * 1.1))
    }
}

/// Small path helpers that need a name at the call site.
enum Shapes {
    static func diamondPath(center: CGPoint, width: Double, height: Double) -> Path {
        Blob.chunky([CGPoint(x: center.x, y: center.y - height / 2),
                     CGPoint(x: center.x + width / 2, y: center.y - height * 0.08),
                     CGPoint(x: center.x + width * 0.3, y: center.y + height / 2),
                     CGPoint(x: center.x - width * 0.3, y: center.y + height / 2),
                     CGPoint(x: center.x - width / 2, y: center.y - height * 0.08)],
                    rounding: 0.08)
    }

    static func gemGlow(center: CGPoint, size: Double) -> Path {
        Path(ellipseIn: CGRect(x: center.x - size / 2, y: center.y - size / 2,
                               width: size, height: size))
    }

    static func spikePath(center: CGPoint, radius: Double, points: Int,
                          inner: Double, angle: Double) -> Path {
        Blob.spikes(center: center, radius: radius, points: points, inner: inner, angle: angle)
    }
}
