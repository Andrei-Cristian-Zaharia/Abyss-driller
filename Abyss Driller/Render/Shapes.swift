import SwiftUI

enum Blob {
    /// Smooth rounded polygon through `points` — the chunky-rock silhouette.
    /// Each vertex becomes a quadratic control point, so corners round off
    /// without any per-corner arc maths.
    static func path(_ points: [CGPoint]) -> Path {
        guard points.count > 2 else { return Path() }
        var path = Path()
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        path.move(to: mid(points[points.count - 1], points[0]))
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            path.addQuadCurve(to: mid(current, next), control: current)
        }
        path.closeSubpath()
        return path
    }

    /// Rounded polygon that keeps its facets. `rounding` 0 is a sharp polygon,
    /// 0.5 is fully smooth — chunky rock wants about 0.3.
    static func chunky(_ points: [CGPoint], rounding: Double = 0.3) -> Path {
        let count = points.count
        guard count > 2 else { return Path() }
        let amount = min(max(rounding, 0.01), 0.49)
        func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        var path = Path()
        path.move(to: lerp(points[0], points[1], amount))
        for index in 1...count {
            let vertex = points[index % count]
            let previous = points[(index - 1 + count) % count]
            let next = points[(index + 1) % count]
            path.addLine(to: lerp(vertex, previous, amount))
            path.addQuadCurve(to: lerp(vertex, next, amount), control: vertex)
        }
        path.closeSubpath()
        return path
    }

    /// Deterministic lumpy ring of points. Same seed, same rock, every frame.
    static func rock(center: CGPoint, radius: Double, sides: Int, jitter: Double,
                     angle: Double, seed: UInt64) -> Path {
        var rng = SeededRandom(seed: seed)
        var points: [CGPoint] = []
        for index in 0..<sides {
            let theta = angle + Double(index) / Double(sides) * .pi * 2
            let distance = radius * (1 - jitter / 2 + rng.double(0...jitter))
            points.append(CGPoint(x: center.x + cos(theta) * distance,
                                  y: center.y + sin(theta) * distance))
        }
        return path(points)
    }

    /// Chunky faceted version of `rock` — the default look for stone.
    static func stone(center: CGPoint, radius: Double, sides: Int, jitter: Double,
                      angle: Double, seed: UInt64, rounding: Double = 0.28) -> Path {
        var rng = SeededRandom(seed: seed)
        var points: [CGPoint] = []
        for index in 0..<sides {
            let theta = angle + Double(index) / Double(sides) * .pi * 2
            let distance = radius * (1 - jitter / 2 + rng.double(0...jitter))
            points.append(CGPoint(x: center.x + cos(theta) * distance,
                                  y: center.y + sin(theta) * distance))
        }
        return chunky(points, rounding: rounding)
    }

    /// Spiked star used for the geode hazard — distinct shape, not just colour.
    static func spikes(center: CGPoint, radius: Double, points count: Int,
                       inner: Double, angle: Double) -> Path {
        var path = Path()
        for index in 0..<(count * 2) {
            let theta = angle + Double(index) / Double(count * 2) * .pi * 2
            let distance = index.isMultiple(of: 2) ? radius : radius * inner
            let point = CGPoint(x: center.x + cos(theta) * distance,
                                y: center.y + sin(theta) * distance)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    static func diamond(center: CGPoint, width: Double, height: Double) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - height / 2))
        path.addLine(to: CGPoint(x: center.x + width / 2, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + height / 2))
        path.addLine(to: CGPoint(x: center.x - width / 2, y: center.y))
        path.closeSubpath()
        return path
    }

    static func triangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Path {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        path.addLine(to: c)
        path.closeSubpath()
        return path
    }
}

// MARK: - Detail helpers

extension Blob {
    /// Four-point sparkle star, for treasure glints.
    static func sparkle(center: CGPoint, size: Double, thin: Double = 0.15) -> Path {
        let long = size / 2
        let short = size * thin
        return chunky([CGPoint(x: center.x, y: center.y - long),
                       CGPoint(x: center.x + short, y: center.y - short),
                       CGPoint(x: center.x + long, y: center.y),
                       CGPoint(x: center.x + short, y: center.y + short),
                       CGPoint(x: center.x, y: center.y + long),
                       CGPoint(x: center.x - short, y: center.y + short),
                       CGPoint(x: center.x - long, y: center.y),
                       CGPoint(x: center.x - short, y: center.y - short)],
                      rounding: 0.12)
    }

    /// Jagged fissures across a rock face. Deterministic for a given seed.
    static func fissures(center: CGPoint, radius: Double, count: Int, seed: UInt64) -> Path {
        var rng = SeededRandom(seed: seed)
        var path = Path()
        for _ in 0..<count {
            let angle = rng.double(0...(.pi * 2))
            let start = CGPoint(x: center.x + cos(angle) * radius * rng.double(0.1...0.5),
                                y: center.y + sin(angle) * radius * rng.double(0.1...0.5))
            path.move(to: start)
            var cursor = start
            var heading = rng.double(0...(.pi * 2))
            for _ in 0..<rng.int(2...3) {
                heading += rng.double(-0.8...0.8)
                let step = radius * rng.double(0.22...0.45)
                cursor = CGPoint(x: cursor.x + cos(heading) * step,
                                 y: cursor.y + sin(heading) * step)
                path.addLine(to: cursor)
            }
        }
        return path
    }

    /// A branching mineral vein running through the rock.
    static func vein(start: CGPoint, length: Double, angle: Double, seed: UInt64) -> Path {
        var rng = SeededRandom(seed: seed)
        var path = Path()
        func walk(from origin: CGPoint, heading: Double, remaining: Double, depth: Int) {
            guard remaining > 0.5, depth < 3 else { return }
            var cursor = origin
            var direction = heading
            path.move(to: cursor)
            let steps = max(2, Int(remaining / 14))
            for _ in 0..<steps {
                direction += rng.double(-0.55...0.55)
                let step = remaining / Double(steps)
                let next = CGPoint(x: cursor.x + cos(direction) * step,
                                   y: cursor.y + sin(direction) * step)
                path.addQuadCurve(to: next,
                                  control: CGPoint(x: (cursor.x + next.x) / 2 + rng.double(-4...4),
                                                   y: (cursor.y + next.y) / 2 + rng.double(-4...4)))
                cursor = next
                if rng.chance(0.3) {
                    walk(from: cursor, heading: direction + rng.double(-1.3...1.3),
                         remaining: remaining * 0.45, depth: depth + 1)
                    path.move(to: cursor)
                }
            }
        }
        walk(from: start, heading: angle, remaining: length, depth: 0)
        return path
    }

    /// Several shards sharing a base, for crystal clusters.
    static func crystalCluster(base: CGPoint, size: Double, count: Int, seed: UInt64) -> [(Path, Double)] {
        var rng = SeededRandom(seed: seed)
        var shards: [(Path, Double)] = []
        for index in 0..<count {
            let lean = Double(index - count / 2) * 0.34 + rng.double(-0.14...0.14)
            let height = size * rng.double(0.55...1.0)
            let halfWidth = size * rng.double(0.1...0.17)
            let tip = CGPoint(x: base.x + sin(lean) * height, y: base.y - cos(lean) * height)
            let left = CGPoint(x: base.x - halfWidth + sin(lean) * height * 0.12,
                               y: base.y - cos(lean) * height * 0.12)
            let right = CGPoint(x: base.x + halfWidth + sin(lean) * height * 0.12,
                                y: base.y - cos(lean) * height * 0.12)
            shards.append((chunky([tip, right,
                                   CGPoint(x: base.x + halfWidth * 0.7, y: base.y),
                                   CGPoint(x: base.x - halfWidth * 0.7, y: base.y),
                                   left], rounding: 0.07), lean))
        }
        return shards
    }
}


/// The hand-made look. Outlines in one ink colour with a faint second pass,
/// stepped halos instead of airbrushed blur, and small shine chips instead
/// of sparkle stars.
enum Ink {
    /// Confident outline plus a fainter, slightly offset pass, like a pen
    /// going over the line twice. `width` is in the context's units.
    static func outline(_ ctx: GraphicsContext, _ path: Path, width: CGFloat = 2.4,
                        color: Color = Palette.ink) {
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        ctx.stroke(path.offsetBy(dx: width * 0.3, dy: width * 0.22), with: .color(color.opacity(0.3)),
                   style: StrokeStyle(lineWidth: width * 0.45, lineCap: .round, lineJoin: .round))
    }

    /// Light given off by something hot or magic: three hard-edged rings that
    /// stack into a posterised glow. Only for things that actually emit light.
    static func halo(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat, color: Color,
                     strength: Double = 1, aspect: CGFloat = 1) {
        for (scale, opacity) in [(1.0, 0.14), (0.74, 0.14), (0.5, 0.16)] {
            let rx = radius * scale, ry = radius * scale * aspect
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2)),
                     with: .color(color.opacity(opacity * strength)))
        }
    }

    /// A small tilted highlight chip, the way an illustrator flicks in shine.
    static func shine(_ ctx: GraphicsContext, at center: CGPoint, size: CGFloat, opacity: Double = 0.9) {
        var chip = ctx
        chip.translateBy(x: center.x, y: center.y)
        chip.rotate(by: .degrees(-35))
        chip.fill(Path(roundedRect: CGRect(x: -size * 0.5, y: -size * 0.16, width: size, height: size * 0.32),
                       cornerRadius: size * 0.16),
                  with: .color(Palette.shine.opacity(opacity)))
        chip.fill(Path(ellipseIn: CGRect(x: size * 0.62, y: -size * 0.12, width: size * 0.24, height: size * 0.24)),
                  with: .color(Palette.shine.opacity(opacity * 0.8)))
    }

    /// Dashed warning ring for telegraphs (replaces red glow blobs).
    static func warning(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat, color: Color = Palette.hazard) {
        let ring = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        ctx.stroke(ring, with: .color(color.opacity(0.85)), style: StrokeStyle(lineWidth: 2.5, dash: [7, 5]))
    }
}


/// A static paper-grain tile laid over the whole frame at low opacity. It is
/// what stops flat vector fills from looking machine-made. Built once.
enum PaperGrain {
    static let tileSize = 160

    static let image: Image? = {
        let size = tileSize
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var rng = SeededRandom(seed: 0x9A9E5)
        for _ in 0..<(size * size / 3) {
            let light = rng.chance(0.45)
            let a = rng.double(0.01...0.045)
            let v: CGFloat = light ? 1 : 0
            context.setFillColor(CGColor(red: v, green: v * 0.96, blue: v * 0.88, alpha: a))
            let w = rng.chance(0.85) ? 1.0 : 2.0
            context.fill(CGRect(x: rng.double(0...Double(size)), y: rng.double(0...Double(size)), width: w, height: w))
        }
        // A few longer fibres.
        for _ in 0..<14 {
            context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.035))
            context.setLineWidth(0.8)
            let x = rng.double(0...Double(size)), y = rng.double(0...Double(size))
            context.move(to: CGPoint(x: x, y: y))
            context.addLine(to: CGPoint(x: x + rng.double(-10...10), y: y + rng.double(-4...4)))
            context.strokePath()
        }
        guard let cg = context.makeImage() else { return nil }
        return Image(decorative: cg, scale: 1)
    }()

    static func draw(_ ctx: GraphicsContext, size: CGSize) {
        guard let image else { return }
        let tile = ctx.resolve(image)
        let step = Double(tileSize)
        var y = 0.0
        while y < Double(size.height) {
            var x = 0.0
            while x < Double(size.width) {
                ctx.draw(tile, in: CGRect(x: x, y: y, width: step, height: step))
                x += step
            }
            y += step
        }
    }
}
