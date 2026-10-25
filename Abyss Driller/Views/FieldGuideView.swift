import SwiftUI

/// The Field Guide: a page for every critter and boss. Pages unlock the first
/// time you meet the creature; until then they are inked silhouettes.
struct FieldGuideView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stageSafeArea) private var safeArea
    enum Tab: CaseIterable { case critters, bosses, perks }
    @State private var tab: Tab
    init(initialPage: BestiaryEntry? = nil, initialTab: Tab = .critters, initialPerk: Perk? = nil) {
        self.initialPage = initialPage
        self.initialPerk = initialPerk
        _tab = State(initialValue: initialPerk == nil ? initialTab : .perks)
        _openPerk = State(initialValue: initialPerk)
    }
    private var showBosses: Bool { tab == .bosses }
    @State private var open: BestiaryEntry?
    @State private var openPerk: Perk?
    var initialPerk: Perk?
    /// Opens straight onto a page (used for previews and screenshots).
    var initialPage: BestiaryEntry?

    private var entries: [BestiaryEntry] { showBosses ? BestiaryEntry.bosses : BestiaryEntry.critters }
    private var found: Int { BestiaryEntry.all.filter { app.profile.bestiarySeen.contains($0.id) }.count }
    private var perksFound: Int { Perk.allCases.filter { app.profile.perksSeen.contains($0.rawValue) }.count }
    /// The header counter follows the open tab: creatures, or perks.
    private var counter: (have: Int, total: Int) {
        tab == .perks ? (perksFound, Perk.allCases.count) : (found, BestiaryEntry.all.count)
    }

    var body: some View {
        ZStack(alignment: .top) {
            MenuBackground()
                .onAppear {
                    if let initialPage {
                        open = initialPage
                        tab = initialPage.isBoss ? .bosses : .critters
                    }
                }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    ScreenHeader(title: String(localized: "FIELD GUIDE", bundle: .app), onBack: { app.screen = .home }) {
                        Text("\(counter.have)/\(counter.total)")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Palette.paper))
                            .accessibilityLabel("\(counter.have) of \(counter.total) found")
                    }
                    tabs
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                              spacing: 12) {
                        if tab == .perks {
                            ForEach(Perk.allCases) { perk in
                                PerkTile(perk: perk, found: app.profile.perksSeen.contains(perk.rawValue)) {
                                    withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85)) { openPerk = perk }
                                }
                            }
                        } else {
                            ForEach(entries) { entry in
                                tile(entry)
                            }
                        }
                    }
                    Spacer(minLength: 10)
                }
                .padding(.horizontal, 18)
                .padding(.top, safeArea.top + 6)
                .padding(.bottom, safeArea.bottom + 24)
            }
            if let openPerk {
                PerkPage(perk: openPerk, onClose: { withAnimation(.easeOut(duration: 0.2)) { self.openPerk = nil } })
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(5)
            }
            if let open {
                PageOverlay(entry: open, onClose: { withAnimation(.easeOut(duration: 0.2)) { self.open = nil } })
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(5)
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases, id: \.self) { item in
                let selected = item == tab
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { tab = item }
                    Haptics.tap()
                } label: {
                    Label(item == .bosses ? String(localized: "BOSSES", bundle: .app) : item == .perks ? String(localized: "PERKS", bundle: .app) : String(localized: "CRITTERS", bundle: .app),
                          systemImage: item == .bosses ? "crown.fill" : item == .perks ? "star.circle.fill" : "ant.fill")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(selected ? Palette.ink : Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(selected ? Palette.paper : .clear))
                }
                .buttonStyle(SquishButtonStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(5)
        .card(17, fill: Palette.panelSunken)
    }

    private func tile(_ entry: BestiaryEntry) -> some View {
        let seen = app.profile.bestiarySeen.contains(entry.id)
        let layer = Strata.layers[entry.biome]
        return Button {
            guard seen else { Haptics.bump(); return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85)) { open = entry }
            Haptics.tap()
        } label: {
            VStack(spacing: 6) {
                Portrait(entry: entry, silhouette: !seen)
                    .frame(height: 118)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(layer.soil.opacity(seen ? 0.9 : 0.35)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.ink, lineWidth: 2))
                Text(seen ? entry.name.localizedUppercase : "???")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.ink)
                Text(layer.name)
                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.ink.opacity(0.55))
                    .kerning(0.8)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.paper))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.ink, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .buttonStyle(SquishButtonStyle())
        .accessibilityLabel(seen ? String(localized: "\(entry.name), \(layer.name)", bundle: .app, comment: "Creature name, biome name")
                            : String(localized: "Undiscovered, \(layer.name)", bundle: .app, comment: "Biome name"))
        .accessibilityHint(seen ? Text("Opens its page") : Text("Meet it in a run to unlock"))
    }
}

/// A full Field Guide page, over the grid.
private struct PageOverlay: View {
    @Environment(AppModel.self) private var app
    let entry: BestiaryEntry
    let onClose: () -> Void

    var body: some View {
        let layer = Strata.layers[entry.biome]
        let kills = app.profile.bestiaryKills[entry.id] ?? 0
        ZStack {
            Palette.background.opacity(0.75).ignoresSafeArea()
                .onTapGesture(perform: onClose)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name.localizedUppercase)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(Palette.ink)
                        Text(entry.isBoss ? String(localized: "BOSS · \(layer.name)", bundle: .app, comment: "Biome name") : layer.name)
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(Palette.ink.opacity(0.6))
                            .kerning(1)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Palette.paperShade))
                    }
                    .buttonStyle(SquishButtonStyle())
                    .accessibilityLabel("Close")
                }
                Portrait(entry: entry, silhouette: false, zoom: entry.isBoss ? 1.0 : 1.25)
                    .frame(height: 190)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(layer.soil))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.ink, lineWidth: 2.5))
                Text(entry.lore)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                if !entry.powers.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("POWERS")
                            .font(.system(size: 10.5, weight: .black, design: .rounded))
                            .foregroundStyle(Palette.ink.opacity(0.55))
                            .kerning(1)
                        HStack(spacing: 6) {
                            ForEach(Array(entry.powers.enumerated()), id: \.offset) { index, power in
                                Text(index == 2 ? "\(power) ★" as String : power)
                                    .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Palette.ink)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(index == 2 ? Palette.hazard.opacity(0.35) : Palette.paperShade))
                            }
                        }
                        Text("★ joins when enraged at half health")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.ink.opacity(0.5))
                    }
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.drillShadow)
                    Text(entry.tip)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.paperShade.opacity(0.7)))
                HStack {
                    Label("\(kills) defeated", systemImage: entry.isBoss ? "crown.fill" : "scope")
                    Spacer()
                    if let drop = entry.bossDrop {
                        // Boss kills are the cores collected towards its part.
                        Label(app.profile.owns(drop) ? String(localized: "\(drop.title) owned", bundle: .app, comment: "Boss part name")
                              : kills >= ShipPart.coresToUnlock ? String(localized: "\(drop.title): for sale in the Garage", bundle: .app, comment: "Boss part name")
                              : String(localized: "\(drop.title): \(kills)/\(ShipPart.coresToUnlock) cores", bundle: .app, comment: "Boss part name, cores collected / needed"),
                              systemImage: drop.icon)
                    }
                }
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.ink.opacity(0.75))
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.paper))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.ink, lineWidth: 3))
            .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
            .padding(.horizontal, 20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// The creature, drawn by the game's own renderer into a small private world.
struct Portrait: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let entry: BestiaryEntry
    var silhouette = false
    var zoom = 1.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || silhouette)) { context in
            let world = PortraitWorlds.world(for: entry)
            let _ = { world.spin = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * 2 }()
            Canvas { ctx, size in
                // The portrait world is 9 m wide; frame the creature in the middle.
                let virtual = 360.0
                let boss = entry.isBoss
                let k = Double(size.height) / virtual * (boss ? 1.3 : 2.7) * zoom
                var c = ctx
                c.translateBy(x: size.width / 2 - 180 * k, y: size.height / 2 - 180 * k)
                c.scaleBy(x: k, y: k)
                let renderer = GameRenderer(world: world, size: CGSize(width: virtual, height: virtual))
                if silhouette {
                    c.drawLayer { layer in
                        layer.addFilter(.colorMultiply(Palette.ink))
                        renderer.drawPortrait(into: layer)
                    }
                } else {
                    renderer.drawPortrait(into: c)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// One tiny world per page, holding just that creature, posed.
@MainActor
enum PortraitWorlds {
    private static var cache: [String: GameWorld] = [:]

    static func world(for entry: BestiaryEntry) -> GameWorld {
        if let world = cache[entry.id] { return world }
        let levels = UpgradeLevels()
        let world = GameWorld(loadout: Loadout.resolve(levels), levels: levels, skin: .classic,
                              previousBest: 0, doubleGold: false, isDaily: false, seed: 1)
        let depth = Strata.layers[entry.biome].startDepth + 10
        world.camera = depth - 4.5
        let center = CGPoint(x: GameWorld.shaftWidth / 2, y: depth)
        switch entry.subject {
        case .critter(let kind):
            let heading: Double = (kind == .angler || kind == .jelly || kind == .ember || kind == .wraith || kind == .frostWisp) ? 0.4 : .pi / 2
            // The worm's tail trails to the right, so shift it left to centre the whole body.
            let x = kind == .worm ? center.x - 0.8 : center.x
            var enemy = Enemy(id: 1, kind: kind, x: x, y: center.y, heading: heading, homeY: center.y,
                              hardness: kind == .beetle ? 2 + entry.biome : 0, speed: 0, phase: 0.5)
            enemy.awake = true
            if kind == .worm { enemy.segments = (1...6).map { CGPoint(x: x + 0.3 * Double($0), y: center.y + sin(Double($0)) * 0.12) } }
            if kind == .centipede {
                enemy.x = center.x - 1.0
                enemy.segments = (1...7).map { CGPoint(x: enemy.x + 0.3 * Double($0), y: center.y + sin(Double($0) * 0.9) * 0.18) }
            }
            if kind == .mole { enemy.mode = .recover; enemy.heading = 0 }
            if kind == .spider { enemy.homeY = center.y - 1.6; enemy.heading = 0 }
            if kind == .slug { enemy.heading = .pi / 2 }
            if kind == .toad { enemy.heading = 0 }
            world.enemies = [enemy]
        case .boss(let kind):
            var boss = Boss(kind: kind, lap: 0, arenaTop: depth - 7, arenaBottom: depth + 8,
                            x: center.x, y: center.y, heading: .pi / 2, hp: 1, maxHP: 1)
            boss.engaged = true
            if kind == .wormQueen {
                boss.x -= 1.6
                boss.segments = (1...8).map { CGPoint(x: boss.x + 0.6 * Double($0), y: center.y + sin(Double($0) * 0.8) * 0.4) }
            }
            if kind == .abyssAngler { boss.heading = 0.4 }
            if kind == .frostWyrm {
                boss.x -= 1.6
                boss.segments = (1...9).map { CGPoint(x: boss.x + 0.62 * Double($0), y: center.y + sin(Double($0) * 0.8) * 0.45) }
            }
            world.boss = boss
        }
        cache[entry.id] = world
        return world
    }
}


/// A perk's card, built like a creature card: a framed window with the perk
/// inked inside, its name, and a grey caption. Undiscovered perks show their
/// silhouette in a faded window, the way unmet creatures do.
private struct PerkTile: View {
    let perk: Perk
    let found: Bool
    let onOpen: () -> Void

    var body: some View {
        Button {
            guard found else { Haptics.bump(); return }
            onOpen()
            Haptics.tap()
        } label: {
            VStack(spacing: 6) {
                PerkWindow(perk: perk, found: found, iconSize: 46)
                    .frame(height: 118)
                Text(found ? perk.title : "???")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(found ? (perk.maxStacks == 1 ? String(localized: "ONCE ONLY", bundle: .app) : String(localized: "STACKS", bundle: .app, comment: "Perk can be taken more than once"))
                     : String(localized: "PERK", bundle: .app))
                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.ink.opacity(0.55))
                    .kerning(0.8)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.paper))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.ink, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .buttonStyle(SquishButtonStyle())
        .accessibilityLabel(found ? (perk.maxStacks == 1 ? String(localized: "\(perk.title.localizedCapitalized), once only", bundle: .app, comment: "Perk name")
                                                  : String(localized: "\(perk.title.localizedCapitalized), stacks", bundle: .app, comment: "Perk name; the perk can be taken more than once"))
                            : String(localized: "Undiscovered perk", bundle: .app))
        .accessibilityHint(found ? Text("Opens its page") : Text("Shows up the first time a run offers it"))
    }
}

/// The framed picture of a perk: its colour as the backdrop, the icon inked
/// on top. Found perks glow; unfound ones are a dark silhouette, faded.
private struct PerkWindow: View {
    let perk: Perk
    let found: Bool
    let iconSize: CGFloat

    var body: some View {
        let backdrop = Palette.panel.mix(with: perk.tint, by: 0.32)
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(found ? backdrop : backdrop.opacity(0.35))
            if found {
                Circle()
                    .fill(RadialGradient(colors: [perk.tint.opacity(0.35), .clear], center: .center,
                                         startRadius: 0, endRadius: iconSize))
                    .frame(width: iconSize * 2, height: iconSize * 2)
            }
            Image(systemName: perk.icon)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(found ? perk.tint : Palette.ink.opacity(0.85))
                .shadow(color: Palette.ink, radius: 0, x: 0, y: found ? 3 : 0)
        }
        .frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.ink, lineWidth: 2))
    }
}

/// A perk's full page, matching the creature pages.
private struct PerkPage: View {
    let perk: Perk
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Palette.background.opacity(0.75).ignoresSafeArea()
                .onTapGesture(perform: onClose)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(perk.title)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(Palette.ink)
                        Text(perk.maxStacks == 1 ? "PERK · ONCE ONLY" : "PERK · STACKS" as LocalizedStringKey)
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(Palette.ink.opacity(0.6))
                            .kerning(1)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Palette.paperShade))
                    }
                    .buttonStyle(SquishButtonStyle())
                    .accessibilityLabel("Close")
                }
                PerkWindow(perk: perk, found: true, iconSize: 72)
                    .frame(height: 170)
                Text(String(localized: "\(perk.detail).", bundle: .app, comment: "A perk's effect, as a sentence"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.ink.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Text(perk.maxStacks == 1
                     ? String(localized: "You can only take this once per run. After that it stops being offered.", bundle: .app)
                     : String(localized: "Take it again in the same run and its effect grows.", bundle: .app))
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.paperShade.opacity(0.7)))
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.paper))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.ink, lineWidth: 3))
            .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
            .padding(.horizontal, 20)
        }
    }
}
