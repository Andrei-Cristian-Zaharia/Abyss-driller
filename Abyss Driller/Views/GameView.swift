import SwiftUI

struct GameView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stageSafeArea) private var safeArea

    let world: GameWorld

    /// Floating joystick: where the thumb landed, dragged along if it strays
    /// past `stickRadius`, and where the thumb is now.
    @State private var stickOrigin: CGPoint?
    @State private var stickKnob: CGPoint = .zero
    private let stickRadius: CGFloat = 64
    /// From Settings; the default is big enough that a resting thumb's wobble
    /// never turns the drill.
    private var stickDeadZone: CGFloat { CGFloat(min(app.settings.deadZone, Double(stickRadius) - 10)) }
    @State private var promptPulse = false

    var body: some View {
        ZStack(alignment: .top) {
            TimelineView(.animation(paused: app.isPaused || app.result != nil)) { context in
                ZStack(alignment: .top) {
                    canvas
                    hud
                }
                .onChange(of: context.date) { _, _ in
                    world.reduceMotion = reduceMotion
                    world.tick(context.date.timeIntervalSinceReferenceDate)
                    Audio.shared.updateRun(world, paused: app.isPaused)
                }
            }

            if app.runPhase == .ready { readyPrompt }
            if app.runPhase == .choosing, !world.perkOffer.isEmpty { PerkOverlay(world: world) }
            if app.isPaused { PauseOverlay() }
            if let toast = app.toast {
                ToastBanner(text: toast)
                    .padding(.top, safeArea.top + 70)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast) {
                        try? await Task.sleep(for: .seconds(1.8))
                        app.toast = nil
                    }
                    .zIndex(10)
            }
            if let result = app.result { ResultsOverlay(result: result) }
            else if app.runOffersRefill { RefuelOverlay(world: world) }
        }
        .background(Palette.background)
        .onAppear {
            world.reduceMotion = reduceMotion
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-autoDrill") {
                world.beginIfNeeded()
                world.isHolding = true
            }
            #endif
        }
    }

    // MARK: - Play area

    private var canvas: some View {
        Canvas(opaque: true, rendersAsynchronously: false) { context, size in
            GameRenderer(world: world, size: size).render(into: context)
        }
        .ignoresSafeArea()
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            world.setCanvasFrame(frame)
        }
        .overlay { joystick }
        .gesture(steerGesture)
        .accessibilityLabel("Drill shaft. Touch and hold to drill, drag in any direction to steer.")
    }

    /// Hold to drill, drag in any direction to turn the drill that way. The
    /// stick is relative to where the thumb landed, so it works anywhere.
    private var steerGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard !app.isPaused, app.result == nil, !app.runOffersRefill,
                      world.phase != .choosing else { return }
                world.beginIfNeeded()
                var origin = stickOrigin ?? value.startLocation
                var dx = value.location.x - origin.x
                var dy = value.location.y - origin.y
                var length = hypot(dx, dy)
                if length > stickRadius {
                    // Drag the base along so reversing never needs a long swipe.
                    origin.x += dx / length * (length - stickRadius)
                    origin.y += dy / length * (length - stickRadius)
                    dx = value.location.x - origin.x
                    dy = value.location.y - origin.y
                    length = stickRadius
                }
                stickOrigin = origin
                stickKnob = value.location
                world.isHolding = true
                if length > stickDeadZone {
                    // Deflection past the dead zone, eased so small pushes stay small.
                    let raw = (length - stickDeadZone) / (stickRadius - stickDeadZone)
                    let push = raw * raw
                    world.steerVector = CGVector(dx: dx / length * push, dy: dy / length * push)
                }
            }
            .onEnded { _ in
                stickOrigin = nil
                world.isHolding = false
                world.steerVector = nil
            }
    }

    @ViewBuilder
    private var joystick: some View {
        if let origin = stickOrigin, app.settings.showJoystick {
            ZStack {
                Circle()
                    .stroke(Palette.textPrimary.opacity(0.22), lineWidth: 2)
                    .background(Circle().fill(Palette.background.opacity(0.18)))
                    .frame(width: stickRadius * 2, height: stickRadius * 2)
                    .position(origin)
                Circle()
                    .fill(Palette.textPrimary.opacity(0.32))
                    .frame(width: 34, height: 34)
                    .position(stickKnob)
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - HUD

    private var hud: some View {
        VStack(spacing: 9) {
            ZStack {
                VStack(spacing: 0) {
                    Text("\(max(0, Int(world.depth))) m")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    // Which biome you are in, in its own ore colour.
                    Text(world.currentLayer.name)
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(world.currentLayer.ore.color)
                        .kerning(1.4)
                }
                .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                .accessibilityElement(children: .combine)

                HStack {
                    GoldPill(amount: world.coins, compact: true)
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .global)
                        } action: { frame in
                            world.setGoldAnchor(globalFrame: frame)
                        }
                    Spacer()
                    Button {
                        app.isPaused = true
                        world.isHolding = false
                        Haptics.tap()
                    } label: {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(Palette.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Palette.panel.opacity(0.92)))
                    }
                    .buttonStyle(SquishButtonStyle())
                    .accessibilityLabel("Pause")
                }
            }

            HStack(spacing: 10) {
                StatMeter(icon: "fuelpump.fill",
                          fraction: world.fuelFraction,
                          tint: world.fuelFraction < 0.2 ? Palette.hazard : Palette.mint,
                          label: "\(Int(world.fuel))")
                StatMeter(icon: "shield.lefthalf.filled",
                          fraction: world.armorFraction,
                          tint: world.armorFraction < 0.4 ? Palette.hazard : Palette.window,
                          label: "\(max(0, world.armor))")
                cargoCounter
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.panel.opacity(0.85))
            )

            if let boss = world.boss, boss.engaged, !boss.defeated {
                bossBar(boss)
            }

            if let event = world.event {
                Label("\(event.kind.title)  \(Int(event.timeLeft.rounded(.up)))s", systemImage: event.kind.icon)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(event.kind.tint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Palette.panel.opacity(0.92)))
            }

            if world.combo >= 2 || world.inOverdrive {
                comboBadge
            }

            if !world.perkStacks.isEmpty {
                perkRow
            }

            if world.isDaily {
                Text("DAILY CHALLENGE · STANDARD RIG")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.gem)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Palette.panel.opacity(0.9)))
            }

            if world.cargoFullNotice > 0.05 {
                Text("HOLD FULL · RICHER ORE SWAPS IN")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.hazard)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Palette.panel.opacity(0.9)))
                    .opacity(world.cargoFullNotice)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, safeArea.top + 4)
        // Step the HUD back while a boss makes its entrance.
        .opacity(1 - 0.8 * world.bossIntroIntensity)
    }

    /// Multiplier, combo count and a bar that fills toward Overdrive (or
    /// drains while it runs). Fades as the combo window runs out.
    private var comboBadge: some View {
        let overdrive = world.inOverdrive
        let tint = overdrive ? Palette.drillBody : (world.comboMultiplier > 1 ? Palette.gold : Palette.textPrimary)
        return HStack(spacing: 8) {
            Text(overdrive ? "OVERDRIVE" : "x\(world.comboMultiplier)")
                .font(.system(size: overdrive ? 14 : 18, weight: .black, design: .rounded))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text("COMBO \(world.combo)")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.panelSunken)
                        Capsule().fill(overdrive ? Palette.exhaust : Palette.drillBody)
                            .frame(width: proxy.size.width * world.overdriveCharge)
                    }
                }
                .frame(width: 74, height: 5)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Palette.panel.opacity(0.9))
                .overlay(Capsule().stroke(tint.opacity(overdrive ? 0.9 : 0.35), lineWidth: 1.5))
        )
        .opacity(0.35 + 0.65 * min(1, world.comboFraction * 2))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(overdrive ? "Overdrive" : "Combo \(world.combo), times \(world.comboMultiplier) gold")
    }

    private func bossBar(_ boss: Boss) -> some View {
        VStack(spacing: 4) {
            Text(boss.title)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(boss.kind.tint)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.panelSunken)
                    Capsule().fill(Palette.hazard)
                        .frame(width: proxy.size.width * Double(boss.hp) / Double(boss.maxHP))
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.panel.opacity(0.9)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(boss.title), \(boss.hp) of \(boss.maxHP) health")
    }

    /// Icons of the perks taken this run, with a count when stacked.
    private var perkRow: some View {
        HStack(spacing: 6) {
            ForEach(Perk.allCases.filter { world.stacks($0) > 0 }) { perk in
                HStack(spacing: 2) {
                    Image(systemName: perk.icon)
                        .font(.system(size: 10, weight: .bold))
                    if world.stacks(perk) > 1 {
                        Text("\(world.stacks(perk))")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                    }
                }
                .foregroundStyle(perk.tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Capsule().fill(Palette.panel.opacity(0.85)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Perks: " + Perk.allCases.filter { world.stacks($0) > 0 }.map(\.title).joined(separator: ", "))
    }

    /// The ore hold: slots used, and what it would sell for at the surface.
    private var cargoCounter: some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: 5) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(world.cargoFull ? Palette.hazard : world.currentLayer.ore.color)
                Text("\(world.slotsUsed)/\(world.loadout.cargoSlots)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(world.cargoFull ? Palette.hazard : Palette.textSecondary)
                    .monospacedDigit()
            }
            Text("ore ≈\(world.cargoValue)")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.textSecondary)
                .monospacedDigit()
        }
        .fixedSize()
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            world.setCargoAnchor(globalFrame: frame)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ore hold \(world.slotsUsed) of \(world.loadout.cargoSlots), worth about \(world.cargoValue) gold")
    }

    private var readyPrompt: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Palette.textPrimary)
            Text("HOLD TO DRILL")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
            Text("Drag in any direction to steer")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            Spacer()
        }
        .shadow(color: .black.opacity(0.6), radius: 8)
        .opacity(promptPulse && !reduceMotion ? 0.55 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                   value: promptPulse)
        .allowsHitTesting(false)
        .onAppear { promptPulse = true }
    }
}

// MARK: - Perk choice

/// Pick one of three run perks. The cards stay inert for a moment so the
/// thumb that was steering cannot pick one by accident.
private struct PerkOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let world: GameWorld
    @State private var armed = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            Palette.background.opacity(0.8).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("CHOOSE A PERK")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                Text("Lasts until the end of this run")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.bottom, 4)
                ForEach(Array(world.perkOffer.enumerated()), id: \.element) { index, perk in
                    card(perk)
                        .offset(y: appeared ? 0 : 40)
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8)
                                    .delay(Double(index) * 0.07), value: appeared)
                }
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: 380)
        }
        .onAppear {
            appeared = true
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                armed = true
            }
        }
    }

    private func card(_ perk: Perk) -> some View {
        let level = world.stacks(perk)
        return Button {
            guard armed else { return }
            world.choosePerk(perk)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: perk.icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(perk.tint)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Palette.panelSunken))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(perk.title)
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(Palette.textPrimary)
                        if perk.maxStacks > 1 {
                            Text("LV \(level + 1)")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundStyle(perk.tint)
                        }
                    }
                    Text(perk.detail)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .card(18, accent: perk.tint.opacity(0.55))
        }
        .buttonStyle(SquishButtonStyle())
        .accessibilityLabel("\(perk.title). \(perk.detail)")
    }
}

// MARK: - Pause

private struct PauseOverlay: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            Palette.background.opacity(0.82).ignoresSafeArea()
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Palette.mint)
                    Text("PAUSED")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                }
                if let world = app.world {
                    // How the run is going, so ending it is an informed choice.
                    HStack(spacing: 0) {
                        summary("\(Int(world.maxDepth)) m", "DEPTH", Palette.textPrimary)
                        summary("\(world.cargoValue)", "ORE", world.currentLayer.ore.color)
                        summary("\(world.coins)", "COINS", Palette.gold)
                    }
                    .padding(.vertical, 10)
                    .card(16, fill: Palette.panelSunken)
                    if !world.perkStacks.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Perk.allCases.filter { world.stacks($0) > 0 }) { perk in
                                Image(systemName: perk.icon)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(perk.tint)
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(Palette.panelSunken))
                            }
                        }
                        .accessibilityLabel("Perks: " + Perk.allCases.filter { world.stacks($0) > 0 }.map(\.title).joined(separator: ", "))
                    }
                }
                PrimaryButton(title: "RESUME", icon: "play.fill") {
                    app.isPaused = false
                }
                SecondaryButton(title: "END RUN", icon: "stop.fill") {
                    app.abandonRun()
                }
            }
            .padding(24)
            .frame(maxWidth: 330)
            .card(26)
            .padding(.horizontal, 24)
        }
    }

    private func summary(_ value: String, _ caption: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(caption)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.textSecondary)
                .kerning(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Rewarded refill

private struct RefuelOverlay: View {
    @Environment(AppModel.self) private var app
    let world: GameWorld

    var body: some View {
        ZStack {
            Palette.background.opacity(0.78).ignoresSafeArea()
            VStack(spacing: 8) {
                Image(systemName: "fuelpump.slash.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Palette.hazard)
                Text("OUT OF FUEL")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                Text("at \(max(0, Int(world.maxDepth))) m")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.textSecondary)

                PrimaryButton(title: app.watchingAd ? "LOADING AD…" : "FREE REFILL",
                              icon: app.watchingAd ? "hourglass" : (app.adsRemoved ? "fuelpump.fill" : "play.rectangle.fill")) {
                    app.watchAdForRefill()
                }
                .disabled(app.watchingAd)
                .opacity(app.watchingAd ? 0.75 : 1)
                .padding(.top, 12)
                Text(app.adsRemoved ? "No ads needed · once per run" : "Watch a short ad · once per run")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.textSecondary)

                SecondaryButton(title: "BANK MY TREASURE") {
                    world.confirmEnd()
                }
                .disabled(app.watchingAd)
                .padding(.top, 6)
            }
            .padding(24)
            .frame(maxWidth: 330)
            .card(26)
            .padding(.horizontal, 24)
        }
    }
}
