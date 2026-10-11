import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stageSafeArea) private var safeArea

    var body: some View {
        ZStack(alignment: .top) {
            MenuBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    topBar
                    MineYard(levels: app.profile.levels,
                             skin: app.selectedSkin,
                             build: app.profile.build,
                             bestDepth: app.profile.bestDepth,
                             reduceMotion: reduceMotion)
                        .frame(height: 250)

                    PrimaryButton(title: "DRILL!", icon: "arrow.down.circle.fill") {
                        app.startRun()
                    }

                    HStack(spacing: 10) {
                        dailyRow
                        garageRow
                    }
                    upgradeSection
                    Spacer(minLength: 10)
                }
                .padding(.horizontal, 18)
                .padding(.top, safeArea.top + 6)
                .padding(.bottom, safeArea.bottom + 24)
            }

            if let track = app.upgradeOffer {
                AdUpgradeOffer(track: track)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .zIndex(4)
            }

            if let toast = app.toast {
                ToastBanner(text: toast)
                    .padding(.top, safeArea.top + 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast) {
                        try? await Task.sleep(for: .seconds(1.6))
                        app.toast = nil
                    }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: app.toast)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: app.upgradeOffer)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            GoldPill(amount: app.profile.gold)
            if app.profile.doubleGold {
                Text("×2")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.background)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Palette.mint))
            }
            Spacer()
            CircleIconButton(icon: "book.closed.fill", label: "Field Guide",
                             badge: app.profile.bestiarySeen.isEmpty == false && app.unreadGuide) { app.openFieldGuide() }
            CircleIconButton(icon: "gearshape.fill", label: "Settings") { app.screen = .settings }
            CircleIconButton(icon: "cart.fill", label: "Shop") { app.screen = .shop }
        }
    }

    private var dailyRow: some View {
        Button {
            app.startRun(daily: true)
        } label: {
            tile(icon: "calendar.badge.clock", tint: Palette.gem,
                 title: "DAILY", subtitle: DailyChallenge.label,
                 detail: app.todayDailyScore.map { "Best \($0)" } ?? "Same shaft for all")
        }
        .buttonStyle(SquishButtonStyle())
        .accessibilityLabel("Daily challenge, \(DailyChallenge.label). " + (app.todayDailyScore.map { "Your score \($0)" } ?? "Not played yet"))
    }

    /// The Garage used to hide behind a wrench icon; it gets a proper tile,
    /// with a hint when a new part is waiting to be fitted.
    private var garageRow: some View {
        let unequipped = ShipPart.allCases.filter { !$0.isStarter && app.profile.owns($0) && !app.profile.build.has($0) }.count
        return Button {
            app.screen = .garage
            Haptics.tap()
        } label: {
            tile(icon: "wrench.and.screwdriver.fill", tint: Palette.drillBody,
                 title: "GARAGE", subtitle: app.profile.build.bit.title,
                 detail: unequipped > 0 ? "\(unequipped) spare part\(unequipped == 1 ? "" : "s")" : "Build your rig",
                 badge: unequipped > 0)
        }
        .buttonStyle(SquishButtonStyle())
        .accessibilityLabel("Garage. " + (unequipped > 0 ? "\(unequipped) parts not fitted" : "Build your rig"))
    }

    private func tile(icon: String, tint: Color, title: String, subtitle: String, detail: String,
                      badge: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.background)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(tint))
                Spacer()
                if badge {
                    Circle().fill(Palette.hazard).frame(width: 9, height: 9)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.textSecondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(18)
    }

    private var upgradeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "WORKSHOP", icon: "hammer.fill", caption: "Permanent upgrades · no cap")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                ForEach(UpgradeTrack.allCases) { track in
                    UpgradeCard(track: track)
                }
            }
        }
    }
}

// MARK: - Upgrade card

struct UpgradeCard: View {
    @Environment(AppModel.self) private var app
    let track: UpgradeTrack

    private var level: Int { app.profile.levels[track] }
    private var price: Int? { track.price(atLevel: level) }
    private var affordable: Bool { app.canBuy(track) }

    var body: some View {
        Button {
            app.tapUpgrade(track)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: track.icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.background)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(track.tint))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(Palette.textPrimary)
                        if level > track.maxLevel {
                            Text("LV \(level)")
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(track.tint)
                        } else {
                            LevelPips(level: level, maxLevel: track.maxLevel, tint: track.tint)
                        }
                    }
                    Spacer(minLength: 0)
                }

                Text(track.nextBenefitText(level: level))
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: 30, alignment: .top)

                priceTag
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(18)
        }
        .buttonStyle(SquishButtonStyle())
        .disabled(price == nil)
        .accessibilityLabel("\(track.title), level \(level). \(track.nextBenefitText(level: level)). \(price.map { "Costs \($0) gold" } ?? "Fully upgraded")")
    }

    private var priceTag: some View {
        Group {
            if let price {
                HStack(spacing: 5) {
                    Circle()
                        .fill(affordable ? Palette.gold : Palette.textSecondary)
                        .frame(width: 11)
                    Text("\(price)")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(affordable ? Palette.background : Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(affordable ? Palette.mint : Palette.panelRaised)
                )
                // Can't afford it? A small badge says an ad will do instead.
                .overlay(alignment: .trailing) {
                    if !affordable && app.canOfferAdUpgrade(track) {
                        Image(systemName: app.adsRemoved ? "gift.fill" : "play.rectangle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.background)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Palette.gold))
                            .padding(.trailing, 6)
                            .accessibilityLabel(app.adsRemoved ? "Free upgrade available" : "Free with an ad")
                    }
                }
            } else {
                Text("MAX")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(track.tint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Palette.panelRaised))
            }
        }
    }
}

// MARK: - Free upgrade for an ad

/// "Out of gold? Watch an ad for this upgrade." Shown when a Workshop card is
/// tapped without enough gold, or right after a purchase that left the next
/// level out of reach.
private struct AdUpgradeOffer: View {
    @Environment(AppModel.self) private var app
    let track: UpgradeTrack

    var body: some View {
        let next = app.profile.levels[track] + 1
        ZStack {
            Palette.background.opacity(0.78).ignoresSafeArea()
                .onTapGesture { if !app.watchingAd { app.upgradeOffer = nil } }
            VStack(spacing: 14) {
                Image(systemName: track.icon)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Palette.background)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(track.tint))
                    .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 2.5))
                VStack(spacing: 4) {
                    Text(app.offerAfterPurchase ? "OUT OF GOLD!" : "NOT ENOUGH GOLD")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(Palette.gold)
                        .kerning(1)
                    Text("\(track.title) → LV \(next)")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                    Text(app.adsRemoved ? "Claim one more upgrade, free. \(app.adUpgradesLeft) left today."
                         : app.offerAfterPurchase ? "Watch a short ad for one more upgrade, free."
                                                  : "Watch a short ad to get this upgrade free.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                    Text(track.nextBenefitText(level: next - 1))
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(track.tint)
                        .padding(.top, 2)
                }
                PrimaryButton(title: app.watchingAd ? "LOADING AD…" : (app.adsRemoved ? "CLAIM FREE" : "WATCH AD"),
                              icon: app.watchingAd ? "hourglass" : (app.adsRemoved ? "gift.fill" : "play.rectangle.fill"), compact: true) {
                    app.watchAdForUpgrade()
                }
                .disabled(app.watchingAd)
                .opacity(app.watchingAd ? 0.75 : 1)
                SecondaryButton(title: "NOT NOW") { app.upgradeOffer = nil }
                    .disabled(app.watchingAd)
                Text("\(app.adUpgradesLeft) of \(AppModel.adUpgradesPerDay) free upgrades left today")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(22)
            .frame(maxWidth: 330)
            .card(24)
            .padding(.horizontal, 24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: - Parked drill above the mine entrance

struct MineYard: View {
    let levels: UpgradeLevels
    let skin: DrillSkin
    var build: ShipBuild = .standard
    let bestDepth: Int
    let reduceMotion: Bool
    /// False draws only the scene, edge to edge (no frame, no best-depth
    /// badge), for marketing art rendered from the same code.
    var framed = true

    var body: some View {
        if framed {
            framedScene
        } else {
            scene
        }
    }

    private var scene: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                draw(ctx, size: size, time: time)
            }
        }
    }

    private var framedScene: some View {
        scene
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Palette.ink, lineWidth: 2.5))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 0) {
                Text("BEST DEPTH")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.textSecondary)
                Text("\(bestDepth) m")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.gold)
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.background.opacity(0.7)))
            .padding(10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your drill at the mine. Best depth \(bestDepth) metres.")
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize, time: TimeInterval) {
        let width = Double(size.width)
        let height = Double(size.height)
        let groundY = height * 0.5
        let shaftX = width * 0.5
        let t = reduceMotion ? 0 : time

        drawSky(ctx, width: width, groundY: groundY, time: t)
        drawCutaway(ctx, width: width, height: height, groundY: groundY, shaftX: shaftX)
        drawHeadframe(ctx, groundY: groundY, shaftX: shaftX, time: t)
        drawBestMarker(ctx, width: width, height: height, groundY: groundY, shaftX: shaftX)

        // The machine, parked over the shaft mouth with its bit idling.
        let scale = 38.0
        let bob = reduceMotion ? 0 : sin(time * 1.6) * 1.5
        let center = CGPoint(x: shaftX, y: groundY - 0.32 * scale + bob)
        drawExhaust(ctx, from: CGPoint(x: center.x - 0.27 * scale, y: center.y - 1.15 * scale), time: t)
        DrillArt.draw(in: ctx, center: center, scale: scale,
                      spin: reduceMotion ? 0 : time * 1.2, tilt: 0,
                      levels: levels, skin: skin, build: build,
                      working: false, headlight: false, reduceMotion: reduceMotion)
        PaperGrain.draw(ctx, size: size)
    }

    /// Stepped night sky, stars, a moon and two layers of hills.
    private func drawSky(_ ctx: GraphicsContext, width: Double, groundY: Double, time: Double) {
        let bands: [Color] = [Palette.background, Palette.panelSunken, Palette.panel]
        for (index, color) in bands.enumerated() {
            let top = groundY * Double(index) / Double(bands.count)
            ctx.fill(Path(CGRect(x: 0, y: top, width: width, height: groundY - top)), with: .color(color))
        }
        var rng = SeededRandom(seed: 0x57A25)
        for k in 0..<22 {
            let p = CGPoint(x: rng.double(0...width), y: rng.double(4...(groundY * 0.7)))
            let twinkle = 0.45 + 0.4 * sin(time * 1.3 + Double(k))
            let r = rng.double(0.7...1.6)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                     with: .color(Palette.shine.opacity(twinkle)))
        }
        // Moon with a couple of craters.
        let moon = CGRect(x: width * 0.1, y: groundY * 0.16, width: 30, height: 30)
        ctx.fill(Path(ellipseIn: moon), with: .color(Palette.shine))
        ctx.fill(Path(ellipseIn: moon.offsetBy(dx: 7, dy: -4)), with: .color(Palette.panelSunken))
        ctx.fill(Path(ellipseIn: CGRect(x: moon.minX + 6, y: moon.midY + 2, width: 5, height: 5)),
                 with: .color(Palette.textSecondary.opacity(0.5)))
        Ink.outline(ctx, Path(ellipseIn: moon), width: 1.6, color: Palette.ink.opacity(0.6))
        // Far and near hills, inked along their tops.
        for (index, tint) in [Palette.panelRaised.opacity(0.7), Palette.panelRaised].enumerated() {
            var hills = Path()
            let base = groundY - (index == 0 ? 26 : 10)
            hills.move(to: CGPoint(x: -10, y: groundY))
            hills.addLine(to: CGPoint(x: -10, y: base))
            var x = -10.0
            var hr = SeededRandom(seed: UInt64(77 + index))
            while x < width + 10 {
                let next = x + hr.double(50...90)
                hills.addQuadCurve(to: CGPoint(x: next, y: base + hr.double(-4...6)),
                                   control: CGPoint(x: (x + next) / 2, y: base - hr.double(10...24)))
                x = next
            }
            hills.addLine(to: CGPoint(x: width + 10, y: groundY))
            hills.closeSubpath()
            ctx.fill(hills, with: .color(tint))
            ctx.stroke(hills, with: .color(Palette.ink.opacity(0.45)), lineWidth: 1.4)
        }
    }

    /// A slice through the ground: every biome in order, with its ore, and
    /// the shaft running down through all of them.
    private func drawCutaway(_ ctx: GraphicsContext, width: Double, height: Double, groundY: Double,
                             shaftX: Double) {
        let layers = Strata.layers
        let bandHeight = (height - groundY) / Double(layers.count)
        var rng = SeededRandom(seed: 0xC07A)
        for (index, layer) in layers.enumerated() {
            let top = groundY + Double(index) * bandHeight
            var band = Path()
            band.move(to: CGPoint(x: -10, y: top))
            var x = -10.0
            while x < width + 10 {
                let next = x + rng.double(30...55)
                band.addQuadCurve(to: CGPoint(x: next, y: top + (index == 0 ? 0 : rng.double(-3...3))),
                                  control: CGPoint(x: (x + next) / 2, y: top + (index == 0 ? 0 : rng.double(-6...6))))
                x = next
            }
            var fill = band
            fill.addLine(to: CGPoint(x: width + 10, y: height + 10))
            fill.addLine(to: CGPoint(x: -10, y: height + 10))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(layer.soil))
            ctx.stroke(band, with: .color(Palette.ink.opacity(index == 0 ? 0.8 : 0.5)), lineWidth: index == 0 ? 2.2 : 1.4)
            // Hatching, then the layer's ore and its special feature.
            for _ in 0..<4 {
                let o = CGPoint(x: rng.double(0...width), y: top + rng.double(3...(bandHeight - 6)))
                var hatch = Path()
                for k in 0..<3 {
                    hatch.move(to: CGPoint(x: o.x + Double(k) * 3.5, y: o.y))
                    hatch.addLine(to: CGPoint(x: o.x + Double(k) * 3.5 - 3, y: o.y + 6))
                }
                ctx.stroke(hatch, with: .color(layer.soilDeep), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
            for _ in 0..<3 {
                var px = rng.double(10...(width - 10))
                if abs(px - shaftX) < 34 { px += 70 }
                let p = CGPoint(x: px.truncatingRemainder(dividingBy: width - 10), y: top + rng.double(5...(bandHeight - 5)))
                let nugget = Blob.stone(center: p, radius: 3.6, sides: 6, jitter: 0.3, angle: rng.double(0...6),
                                        seed: rng.next(), rounding: 0.15)
                ctx.fill(nugget, with: .color(layer.ore.color))
                ctx.stroke(nugget, with: .color(Palette.ink), lineWidth: 1.1)
            }
            let feature = CGPoint(x: index.isMultiple(of: 2) ? width * 0.18 : width * 0.82, y: top + bandHeight * 0.5)
            switch index {
            case 3:
                for k in 0..<3 {
                    let shard = Blob.chunky([CGPoint(x: feature.x - 4 + Double(k) * 5, y: feature.y + 4),
                                             CGPoint(x: feature.x - 1 + Double(k) * 5, y: feature.y - 7 - Double(k % 2) * 3),
                                             CGPoint(x: feature.x + 2 + Double(k) * 5, y: feature.y + 4)], rounding: 0.05)
                    ctx.fill(shard, with: .color(layer.crystal ?? Palette.window))
                    ctx.stroke(shard, with: .color(Palette.ink), lineWidth: 1)
                }
            case 4:
                let pool = Path(ellipseIn: CGRect(x: feature.x - 12, y: feature.y - 4, width: 24, height: 9))
                Ink.halo(ctx, center: feature, radius: 16, color: Palette.lava, strength: 1.2, aspect: 0.5)
                ctx.fill(pool, with: .color(Palette.lava))
                ctx.stroke(pool, with: .color(Palette.ink), lineWidth: 1.2)
            case 5:
                // Glowing abyss fungus.
                Ink.halo(ctx, center: feature, radius: 14, color: Palette.abyssGlow, strength: 1.2, aspect: 0.6)
                for k in 0..<3 {
                    let stem = CGPoint(x: feature.x - 6 + Double(k) * 6, y: feature.y + 4)
                    let cap = Path(ellipseIn: CGRect(x: stem.x - 3.5, y: stem.y - 8 - Double(k % 2) * 2, width: 7, height: 4.5))
                    ctx.fill(Path(CGRect(x: stem.x - 0.8, y: stem.y - 5 - Double(k % 2) * 2, width: 1.6, height: 6)),
                             with: .color(Palette.abyssGlow.opacity(0.7)))
                    ctx.fill(cap, with: .color(Palette.abyssGlow))
                    ctx.stroke(cap, with: .color(Palette.ink), lineWidth: 1)
                }
            case 2:
                let geode = Shapes.spikePath(center: feature, radius: 6, points: 7, inner: 0.55, angle: 0.3)
                ctx.fill(geode, with: .color(Palette.hazard))
                ctx.stroke(geode, with: .color(Palette.ink), lineWidth: 1.1)
            default:
                break
            }
        }
        // The shaft, shored with timber rungs.
        let shaft = CGRect(x: shaftX - 17, y: groundY - 1, width: 34, height: height - groundY + 2)
        ctx.fill(Path(shaft), with: .color(Palette.background))
        var rung = groundY + 12
        while rung < height {
            ctx.fill(Path(CGRect(x: shaft.minX, y: rung, width: shaft.width, height: 3)),
                     with: .color(Palette.crate.opacity(0.75)))
            rung += 20
        }
        var edges = Path()
        edges.move(to: CGPoint(x: shaft.minX, y: groundY)); edges.addLine(to: CGPoint(x: shaft.minX, y: height))
        edges.move(to: CGPoint(x: shaft.maxX, y: groundY)); edges.addLine(to: CGPoint(x: shaft.maxX, y: height))
        ctx.stroke(edges, with: .color(Palette.ink), lineWidth: 2)
        // Surface lip.
        ctx.fill(Path(CGRect(x: 0, y: groundY - 1, width: width, height: 4)), with: .color(layers[0].pebble))
    }

    /// Timber headframe beside the shaft, its pulley turning.
    private func drawHeadframe(_ ctx: GraphicsContext, groundY: Double, shaftX: Double, time: Double) {
        let foot = shaftX + 54
        let top = CGPoint(x: foot + 6, y: groundY - 66)
        var frame = Path()
        frame.move(to: CGPoint(x: foot - 18, y: groundY)); frame.addLine(to: CGPoint(x: top.x - 4, y: top.y))
        frame.move(to: CGPoint(x: foot + 24, y: groundY)); frame.addLine(to: CGPoint(x: top.x + 4, y: top.y))
        for k in 1...3 {
            let y = groundY - Double(k) * 16
            let spread = 21 - Double(k) * 4.5
            frame.move(to: CGPoint(x: foot + 3 - spread, y: y)); frame.addLine(to: CGPoint(x: foot + 3 + spread, y: y - 8))
        }
        ctx.stroke(frame, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        ctx.stroke(frame, with: .color(Palette.crate), style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
        // Cable from the wheel down into the shaft.
        var cable = Path()
        cable.move(to: CGPoint(x: top.x - 9, y: top.y))
        cable.addLine(to: CGPoint(x: shaftX + 6, y: groundY + 30))
        ctx.stroke(cable, with: .color(Palette.ink.opacity(0.8)), lineWidth: 1.2)
        // Pulley wheel.
        let r = 10.0
        let wheel = Path(ellipseIn: CGRect(x: top.x - r, y: top.y - r, width: r * 2, height: r * 2))
        ctx.fill(wheel, with: .color(Palette.drillBitShadow))
        var spokes = Path()
        for k in 0..<4 {
            let a = time * 0.8 + Double(k) * .pi / 4
            spokes.move(to: CGPoint(x: top.x - cos(a) * r, y: top.y - sin(a) * r))
            spokes.addLine(to: CGPoint(x: top.x + cos(a) * r, y: top.y + sin(a) * r))
        }
        ctx.stroke(spokes, with: .color(Palette.ink.opacity(0.7)), lineWidth: 1.4)
        Ink.outline(ctx, wheel, width: 2)
        // A lantern hanging off the frame.
        let lamp = CGPoint(x: foot - 12, y: groundY - 30)
        Ink.halo(ctx, center: lamp, radius: 15, color: Palette.gold, strength: 1.3)
        let body = Path(roundedRect: CGRect(x: lamp.x - 3.5, y: lamp.y - 5, width: 7, height: 10), cornerRadius: 2)
        ctx.fill(body, with: .color(Palette.gold))
        ctx.stroke(body, with: .color(Palette.ink), lineWidth: 1.2)
    }

    /// Your record, flagged in the shaft at its depth.
    private func drawBestMarker(_ ctx: GraphicsContext, width: Double, height: Double, groundY: Double, shaftX: Double) {
        guard bestDepth > 0 else { return }
        let deepest = Strata.layers.last!.startDepth + 170
        let y = groundY + min(1, Double(bestDepth) / deepest) * (height - groundY - 10) + 4
        var line = Path()
        line.move(to: CGPoint(x: shaftX - 17, y: y))
        line.addLine(to: CGPoint(x: shaftX + 17, y: y))
        ctx.stroke(line, with: .color(Palette.gold), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
        var pole = Path()
        pole.move(to: CGPoint(x: shaftX + 17, y: y))
        pole.addLine(to: CGPoint(x: shaftX + 17, y: y - 14))
        ctx.stroke(pole, with: .color(Palette.ink), lineWidth: 1.6)
        let flag = Blob.chunky([CGPoint(x: shaftX + 17, y: y - 14), CGPoint(x: shaftX + 30, y: y - 10.5),
                                CGPoint(x: shaftX + 17, y: y - 7)], rounding: 0.05)
        ctx.fill(flag, with: .color(Palette.gold))
        ctx.stroke(flag, with: .color(Palette.ink), lineWidth: 1.1)
    }

    /// Puffs of exhaust drifting up from the parked machine.
    private func drawExhaust(_ ctx: GraphicsContext, from origin: CGPoint, time: Double) {
        guard !reduceMotion else { return }
        for k in 0..<3 {
            let phase = (time * 0.6 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
            let r = 3 + phase * 6
            let p = CGPoint(x: origin.x - phase * 8 + sin(phase * 5) * 2, y: origin.y - phase * 26)
            let puff = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            ctx.fill(puff, with: .color(Palette.textSecondary.opacity(0.35 * (1 - phase))))
            ctx.stroke(puff, with: .color(Palette.ink.opacity(0.3 * (1 - phase))), lineWidth: 1)
        }
    }
}

struct ToastBanner: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(Palette.background)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Palette.mint))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
    }
}
