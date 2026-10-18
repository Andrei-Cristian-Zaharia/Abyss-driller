import SwiftUI

/// Build the machine: one part per slot. Starter parts are free, shop parts
/// cost gold, boss parts unlock the first time that boss falls.
struct GarageView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stageSafeArea) private var safeArea
    @State private var slot: PartSlot = .bit

    var body: some View {
        ZStack(alignment: .top) {
            MenuBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    header
                    preview
                    statLine
                    slotTabs
                    slotSection(slot)
                    Spacer(minLength: 10)
                }
                .padding(.horizontal, 18)
                .padding(.top, safeArea.top + 6)
                .padding(.bottom, safeArea.bottom + 24)
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
    }

    private var header: some View {
        ScreenHeader(title: "GARAGE", onBack: { app.screen = .home }) {
            GoldPill(amount: app.profile.gold, compact: true)
        }
    }

    /// The machine as it will drill, drawn by the same `DrillArt` as the run.
    private var preview: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                DrillArt.draw(in: ctx,
                              center: CGPoint(x: size.width / 2, y: size.height * 0.48),
                              scale: 62,
                              spin: reduceMotion ? 0 : time * 3,
                              tilt: 0,
                              levels: app.profile.levels,
                              skin: app.selectedSkin,
                              build: app.profile.build,
                              working: true,
                              headlight: false,
                              reduceMotion: reduceMotion)
            }
        }
        .frame(height: 210)
        .background(
            // A lit floor pad under the machine, like a garage bay.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(RadialGradient(colors: [Palette.panelRaised, Palette.panelSunken],
                                     center: .center, startRadius: 10, endRadius: 190))
        )
        .card(22, fill: .clear)
        .accessibilityLabel("Your drill: " + app.profile.build.parts.map(\.title).joined(separator: ", "))
    }

    /// The resolved rig, so trade-offs are visible before a run.
    private var statLine: some View {
        let rig = app.profile.runLoadout
        let build = app.profile.gear
        return HStack(spacing: 0) {
            stat("bolt.fill", "\(rig.power)", "POWER", Palette.drillBody)
            stat("fuelpump.fill", "\(Int(rig.fuelCapacity))", "FUEL", Palette.mint)
            stat("shield.lefthalf.filled", "\(rig.armor)", "ARMOR", Palette.window)
            stat("shippingbox.fill", "\(rig.cargoSlots)", "HOLD", Palette.gem)
            stat("speedometer", "\(Int((build.speedFactor * 100).rounded()))%", "SPEED", Palette.textPrimary)
        }
        .padding(.vertical, 10)
        .card(16)
    }

    private func stat(_ icon: String, _ value: String, _ caption: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()
            Text(caption)
                .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.textSecondary)
                .kerning(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// One slot at a time instead of a 19-card scroll. Each tab shows the
    /// fitted part's icon, plus a dot when a spare part is owned there.
    private var slotTabs: some View {
        HStack(spacing: 6) {
            ForEach(PartSlot.allCases) { tab in
                let fitted = app.profile.build[tab]
                let spare = ShipPart.parts(for: tab).contains { !$0.isStarter && app.profile.owns($0) && $0 != fitted }
                let selected = tab == slot
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { slot = tab }
                    Haptics.tap()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: fitted.icon)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(selected ? Palette.background : fitted.tint == Palette.textSecondary ? Palette.textPrimary : fitted.tint)
                        Text(tab.title)
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(selected ? Palette.background : Palette.textSecondary)
                            .kerning(0.6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(selected ? Palette.mint : .clear)
                    )
                    .overlay(alignment: .topTrailing) {
                        if spare && !selected {
                            Circle().fill(Palette.hazard).frame(width: 7, height: 7).padding(7)
                        }
                    }
                }
                .buttonStyle(SquishButtonStyle())
                .accessibilityLabel("\(tab.title.capitalized): \(fitted.title)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(5)
        .card(17, fill: Palette.panelSunken)
    }

    private func slotSection(_ slot: PartSlot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ShipPart.parts(for: slot)) { part in
                PartCard(part: part)
            }
        }
        .id(slot)
        .transition(.opacity)
    }
}

private struct PartCard: View {
    @Environment(AppModel.self) private var app
    let part: ShipPart

    private var owned: Bool { app.profile.owns(part) }
    private var equipped: Bool { app.profile.build.has(part) }
    private var level: Int { app.profile.level(part) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                if owned { app.equip(part) } else if app.isForSale(part) { app.buy(part) } else { Haptics.bump() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: owned ? part.icon : "lock.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(owned ? part.tint : Palette.textSecondary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Palette.panelSunken))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(part.title.uppercased())
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundStyle(owned ? Palette.textPrimary : Palette.textSecondary)
                            RarityTag(rarity: part.rarity)
                            if part.isRisky {
                                Text("RISKY")
                                    .font(.system(size: 8, weight: .black, design: .rounded))
                                    .foregroundStyle(Palette.background)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Palette.hazard))
                            }
                        }
                        if !part.isStarter { MarkPips(level: owned ? level : 0, tint: part.tint) }
                        Text(part.detail(level: owned ? level : 1))
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    trailing
                }
            }
            .buttonStyle(SquishButtonStyle())
            .accessibilityLabel(accessibilityText)

            if owned, let cost = app.upgradeCost(part) {
                upgradeRow(cost)
            }
        }
        .padding(12)
        // Rarity colours the card's edge; the equipped part keeps its bright rim.
        .card(16, accent: equipped ? (part.tint == Palette.textSecondary ? Palette.mint : part.tint)
                                   : (part.rarity == .common ? nil : part.rarity.color.opacity(owned ? 0.55 : 0.3)))
    }

    /// Next Mk: what it does, and the gold (plus boss cores) it costs.
    private func upgradeRow(_ cost: (gold: Int, cores: Int)) -> some View {
        let affordable = app.canUpgrade(part)
        return Button {
            app.upgrade(part)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(affordable ? Palette.mint : Palette.textSecondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MK \(String(repeating: "I", count: level + 1))")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                    Text(part.detail(level: level + 1))
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    GoldPill(amount: cost.gold, compact: true)
                    if cost.cores > 0, let boss = part.droppedBy {
                        HStack(spacing: 3) {
                            Image(systemName: "seal.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(boss.tint)
                            Text("\(app.profile.cores(boss))/\(cost.cores) cores")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundStyle(app.profile.cores(boss) >= cost.cores ? Palette.textPrimary : Palette.hazard)
                        }
                    }
                }
                .opacity(affordable ? 1 : 0.55)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.panelSunken))
        }
        .buttonStyle(SquishButtonStyle())
        .accessibilityLabel("Upgrade \(part.title) to Mark \(level + 1): \(part.detail(level: level + 1)). Costs \(cost.gold) gold" + (cost.cores > 0 ? " and \(cost.cores) boss cores." : "."))
    }

    @ViewBuilder
    private var trailing: some View {
        if equipped {
            Text("EQUIPPED")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(Palette.background)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(part.tint == Palette.textSecondary ? Palette.mint : part.tint))
        } else if owned {
            Text("EQUIP")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(Palette.panelRaised))
        } else if app.isForSale(part), let price = part.buyPrice {
            GoldPill(amount: price, compact: true)
                .opacity(app.canBuy(part) ? 1 : 0.45)
        } else if let boss = part.droppedBy {
            // Locked boss part: cores collected towards the unlock.
            let have = min(app.profile.coresCollected(boss), ShipPart.coresToUnlock)
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(have)/\(ShipPart.coresToUnlock) CORES")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(boss.tint)
                CoreBar(value: have, tint: boss.tint)
                    .frame(width: 70)
                Text("BEAT \(boss.title)")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 78, alignment: .trailing)
        }
    }

    private var accessibilityText: String {
        var text = "\(part.title), \(part.rarity.title.lowercased()). \(part.detail(level: owned ? level : 1))."
        if !part.isStarter, owned { text += " Mark \(level)." }
        if equipped { text += " Equipped." }
        else if owned { text += " Tap to equip." }
        else if app.isForSale(part), let price = part.buyPrice { text += " Costs \(price) gold." }
        else if let boss = part.droppedBy {
            text += " \(app.profile.coresCollected(boss)) of \(ShipPart.coresToUnlock) \(boss.title) cores collected. Beat it to collect more."
        }
        return text
    }
}

/// Mk I–III as three small bars.
private struct MarkPips: View {
    let level: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...ShipPart.maxLevel, id: \.self) { mark in
                Capsule()
                    .fill(mark <= level ? tint : Palette.panelSunken)
                    .frame(width: 14, height: 4)
            }
        }
        .accessibilityHidden(true)
    }
}


/// Small coloured "RARE" / "LEGENDARY" label.
struct RarityTag: View {
    let rarity: PartRarity

    var body: some View {
        Text(rarity.title)
            .font(.system(size: 7.5, weight: .black, design: .rounded))
            .kerning(0.4)
            .foregroundStyle(rarity == .common ? Palette.background : Palette.background)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(rarity.color))
            .accessibilityHidden(true)
    }
}
