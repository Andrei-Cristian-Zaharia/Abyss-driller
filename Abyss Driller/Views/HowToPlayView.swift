import SwiftUI

/// "How to Play": a reference for every rule a player might wonder about.
/// Topics are collapsible cards. Perks, biomes and their ores are generated
/// from the game's own data, and numbers come from the tuning constants, so
/// the guide stays true when balance changes.
struct HowToPlayView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.stageSafeArea) private var safeArea
    @State private var open: Set<String>
    init(open: Set<String> = ["basics"]) { _open = State(initialValue: open) }

    var body: some View {
        ZStack(alignment: .top) {
            MenuBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ScreenHeader(title: String(localized: "HOW TO PLAY", bundle: .app), onBack: { app.screen = .home }) { EmptyView() }
                    ForEach(topics) { topic in
                        TopicCard(topic: topic, isOpen: open.contains(topic.id)) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                if open.contains(topic.id) { open.remove(topic.id) } else { open.insert(topic.id) }
                            }
                        }
                    }
                    Spacer(minLength: 10)
                }
                .padding(.horizontal, 18)
                .padding(.top, safeArea.top + 6)
                .padding(.bottom, safeArea.bottom + 24)
            }
        }
    }

    // MARK: Content

    struct Entry: Identifiable {
        let icon: String
        let tint: Color
        let title: String
        let text: String
        var tag: String? = nil
        var tagTint: Color = Palette.mint
        var id: String { title }
    }

    struct Topic: Identifiable {
        let id: String
        let icon: String
        let tint: Color
        let title: String
        let entries: [Entry]
    }

    private var topics: [Topic] { Self.topics(perksSeen: app.profile.perksSeen) }

    static func topics(perksSeen: Set<String>) -> [Topic] {
        let found = Perk.allCases.filter { perksSeen.contains($0.rawValue) }.count
        return [
            Topic(id: "basics", icon: "hand.tap.fill", tint: Palette.mint, title: String(localized: "THE BASICS", bundle: .app), entries: [
                Entry(icon: "hand.point.down.fill", tint: Palette.mint, title: String(localized: "Hold to drill", bundle: .app),
                      text: String(localized: "Hold anywhere to dig. Let go to stop and keep your fuel.", bundle: .app)),
                Entry(icon: "arrow.up.and.down.and.arrow.left.and.right", tint: Palette.mint, title: String(localized: "Drag to steer", bundle: .app),
                      text: String(localized: "Drag your thumb to turn the drill in any direction, even back up. You can change the sensitivity in Settings.", bundle: .app)),
                Entry(icon: "flag.checkered", tint: Palette.gold, title: String(localized: "A run", bundle: .app, comment: "One play session, from start until fuel or armour runs out"),
                      text: String(localized: "Dig as deep as you can. The run ends when you run out of fuel or armour. Everything you carry is sold at the end.", bundle: .app)),
                Entry(icon: "wrench.and.screwdriver.fill", tint: Palette.drillBody, title: String(localized: "Get stronger", bundle: .app),
                      text: String(localized: "Spend gold in the Workshop on permanent upgrades, and fit parts in the Garage.", bundle: .app)),
            ]),
            Topic(id: "gauges", icon: "gauge.with.dots.needle.67percent", tint: Palette.window, title: String(localized: "FUEL & ARMOUR", bundle: .app), entries: [
                Entry(icon: "fuelpump.fill", tint: Palette.mint, title: String(localized: "Fuel", bundle: .app),
                      text: String(localized: "Burns while you drill, and faster when cutting through rock. Fuel cans give +\(Int(GameWorld.fuelCanAmount)). Close calls and boss kills refuel too. A double beep warns you when you're low.", bundle: .app)),
                Entry(icon: "shield.lefthalf.filled", tint: Palette.window, title: String(localized: "Armour", bundle: .app),
                      text: String(localized: "Every hit costs armour. Spiky geodes cost 2. At zero the drill is wrecked. Each hit also costs a little fuel and resets your combo.", bundle: .app)),
                Entry(icon: "play.rectangle.fill", tint: Palette.gold, title: String(localized: "Free refill", bundle: .app),
                      text: String(localized: "Out of fuel once per run? You can get one free refill (with a short ad, or instantly with Remove Ads). Not in the Daily Challenge.", bundle: .app)),
            ]),
            Topic(id: "rock", icon: "mountain.2.fill", tint: Palette.rock(hardness: 3), title: String(localized: "ROCK & HAZARDS", bundle: .app), entries: [
                Entry(icon: "bolt.fill", tint: Palette.drillBody, title: String(localized: "Power vs hardness", bundle: .app),
                      text: String(localized: "Rock gets harder the deeper you go. If your Power is high enough you drill straight through; if not, it has a coral-red rim and hurts. Upgrade Power and the rim disappears.", bundle: .app)),
                Entry(icon: "staroflife.fill", tint: Palette.hazard, title: String(localized: "Spiky geodes", bundle: .app),
                      text: String(localized: "Never drillable and cost 2 armour. Only Overdrive or the Diamond Bit perk breaks them (they look cracked when you can).", bundle: .app)),
                Entry(icon: "arrow.triangle.branch", tint: Palette.window, title: String(localized: "Close calls", bundle: .app),
                      text: String(localized: "Skim past a rock you can't break without touching it: \"CLOSE!\" gives fuel and combo.", bundle: .app)),
                Entry(icon: "flame.fill", tint: Palette.lava, title: String(localized: "Lava", bundle: .app),
                      text: String(localized: "In the Magma Core, pools burn on contact. A dashed ring warns before new lava appears.", bundle: .app)),
                Entry(icon: "exclamationmark.circle.fill", tint: Palette.hazard, title: String(localized: "Warnings", bundle: .app),
                      text: String(localized: "A dashed ring or line always shows where something is about to hit. Get out of it.", bundle: .app)),
            ]),
            Topic(id: "money", icon: "dollarsign.circle.fill", tint: Palette.gold, title: String(localized: "ORE, CARGO & GOLD", bundle: .app), entries: [
                Entry(icon: "shippingbox.fill", tint: Palette.gem, title: String(localized: "The hold", bundle: .app),
                      text: String(localized: "Ore takes 1 slot and gems 2. It's sold when the run ends. Deeper ore is worth more per slot, so when the hold is full, better ore swaps out the worst.", bundle: .app)),
                Entry(icon: "circle.fill", tint: Palette.gold, title: String(localized: "Coins", bundle: .app),
                      text: String(localized: "Kills, chests and boss rewards are coins: they never take space in the hold.", bundle: .app)),
                Entry(icon: "sparkles", tint: Palette.gold, title: String(localized: "Ores", bundle: .app),
                      text: String(localized: "\(Strata.layers.map { $0.ore.name.localizedCapitalized }.joined(separator: " · ")). Each one is worth more than the last.", bundle: .app, comment: "Starts with the list of ore names")),
                Entry(icon: "cube.box.fill", tint: Palette.gold, title: String(localized: "Treasure chests", bundle: .app),
                      text: String(localized: "Hidden in caves just past your best depth. Drill into one for a big payout.", bundle: .app)),
            ]),
            Topic(id: "combo", icon: "flame.fill", tint: Palette.drillBody, title: String(localized: "COMBO & OVERDRIVE", bundle: .app), entries: [
                Entry(icon: "multiply.circle.fill", tint: Palette.drillBody, title: String(localized: "Combo", bundle: .app),
                      text: String(localized: "Ore, smashed rock, fuel cans, kills and close calls add to your combo. Every \(GameWorld.comboStep) raises the gold multiplier, up to ×4. It drops if you go \(Int(GameWorld.comboWindow)) s without scoring, or get hit.", bundle: .app)),
                Entry(icon: "bolt.circle.fill", tint: Palette.drillBody, title: String(localized: "Overdrive", bundle: .app),
                      text: String(localized: "Reach a combo of \(GameWorld.overdriveCombo) and Overdrive fires for a few seconds: faster, no fuel burn, and you smash through everything, even spiky geodes.", bundle: .app)),
            ]),
            Topic(id: "status", icon: "snowflake", tint: Palette.frost, title: String(localized: "STATUS EFFECTS", bundle: .app), entries: [
                Entry(icon: "snowflake", tint: Palette.frost, title: String(localized: "Chill", bundle: .app),
                      text: String(localized: "Frozen Depths. Slows the drill and its turning for a moment. Frost Runners make you immune.", bundle: .app)),
                Entry(icon: "aqi.medium", tint: Palette.spore, title: String(localized: "Poison", bundle: .app),
                      text: String(localized: "Spore Hollow. Your fuel leaks out \(GameWorld.poisonBurn.formatted())× faster for a few seconds. The Spore Filter makes you immune.", bundle: .app)),
                Entry(icon: "tornado", tint: Palette.voidGlow, title: String(localized: "Gravity", bundle: .app),
                      text: String(localized: "The Void (and the Pharaoh's sandstorm). Pulls the drill in: steer against it. The Void Drill ignores every pull.", bundle: .app)),
            ]),
            Topic(id: "events", icon: "exclamationmark.triangle.fill", tint: Palette.hazard, title: String(localized: "EVENTS", bundle: .app), entries: [
                Entry(icon: "exclamationmark.triangle.fill", tint: Palette.hazard, title: String(localized: "Cave-in", bundle: .app),
                      text: String(localized: "Boulders fall from above. Smash them with your bit, or dodge.", bundle: .app)),
                Entry(icon: "sparkles", tint: Palette.gold, title: String(localized: "Mother Lode", bundle: .app),
                      text: String(localized: "A burst of ore appears and every piece pays double for a few seconds.", bundle: .app)),
                Entry(icon: "moon.fill", tint: Palette.gem, title: String(localized: "Lights Out", bundle: .app),
                      text: String(localized: "Only your headlight shows. Gems still glint. The Abyss Lantern keeps the lights on.", bundle: .app)),
            ]),
            Topic(id: "bosses", icon: "crown.fill", tint: Palette.hazard, title: String(localized: "BOSSES", bundle: .app), entries: [
                Entry(icon: "crown.fill", tint: Palette.hazard, title: String(localized: "Guardians", bundle: .app),
                      text: String(localized: "A boss guards the end of every biome. Ram it with your bit, then back off: after each hit it can't hurt you for a moment.", bundle: .app)),
                Entry(icon: "bolt.fill", tint: Palette.hazard, title: String(localized: "Three powers", bundle: .app),
                      text: String(localized: "Each boss has 3 powers. The third joins when it's enraged at half health. Every power is warned first.", bundle: .app)),
                Entry(icon: "arrow.uturn.down", tint: Palette.textSecondary, title: String(localized: "Minis", bundle: .app, comment: "Smaller repeat versions of bosses"),
                      text: String(localized: "Beat a boss once and it comes back as a mini: smaller, half the health, a bit faster.", bundle: .app)),
                Entry(icon: "hexagon.fill", tint: Palette.gold, title: String(localized: "Cores & boss parts", bundle: .app),
                      text: String(localized: "Every boss win (mini or full) gives 1 core. Collect \(ShipPart.coresToUnlock) from a boss and its Legendary part goes on sale in the Garage. Cores also pay for boss part upgrades.", bundle: .app)),
                Entry(icon: "book.closed.fill", tint: Palette.paper, title: String(localized: "Field Guide", bundle: .app),
                      text: String(localized: "Every creature and boss you meet gets a page with tips for beating it.", bundle: .app)),
            ]),
            Topic(id: "perks", icon: "star.circle.fill", tint: Palette.gem, title: String(localized: "PERKS  \(found)/\(Perk.allCases.count)", bundle: .app), entries: [
                Entry(icon: "rectangle.stack.fill", tint: Palette.gem, title: String(localized: "Pick 1 of 3", bundle: .app),
                      text: String(localized: "At \(Int(GameWorld.firstPerkDepth)) m, then every \(Int(GameWorld.perkInterval)) m and after every boss. Perks last until the run ends. Most can be taken again to stack.", bundle: .app)),
                Entry(icon: "book.closed.fill", tint: Palette.paper, title: String(localized: "Your perk collection", bundle: .app),
                      text: String(localized: "Every perk you've been offered is in the Field Guide, under Perks: what it does and whether it stacks. You've found \(found) of \(Perk.allCases.count).", bundle: .app)),
            ]),
            Topic(id: "biomes", icon: "globe.europe.africa.fill", tint: Palette.mint, title: String(localized: "BIOMES", bundle: .app), entries:
                Strata.layers.enumerated().map { index, layer in
                    Entry(icon: "\(index + 1).circle.fill", tint: layer.ore.color, title: layer.name.localizedCapitalized,
                          text: String(localized: "From \(Int(layer.startDepth)) m · \(layer.ore.name.localizedCapitalized) ore · boss: \(GameWorld.bossKind(index).title.localizedCapitalized)", bundle: .app, comment: "Biome summary: start depth, ore name, boss name"))
                }),
            Topic(id: "progress", icon: "wrench.and.screwdriver.fill", tint: Palette.drillBody, title: String(localized: "WORKSHOP & GARAGE", bundle: .app), entries: [
                Entry(icon: "arrow.up.circle.fill", tint: Palette.mint, title: String(localized: "Workshop", bundle: .app),
                      text: String(localized: "Permanent upgrades: Power, Fuel, Armour and Cargo. No level cap.", bundle: .app)),
                Entry(icon: "gearshape.2.fill", tint: Palette.drillBody, title: String(localized: "Garage parts", bundle: .app),
                      text: String(localized: "One bit, hull, tracks and module at a time. Parts are trade-offs: pick a build that suits you.", bundle: .app)),
                Entry(icon: "diamond.fill", tint: PartRarity.epic.color, title: String(localized: "Rarity", bundle: .app),
                      text: String(localized: "\(PartRarity.allCases.map { $0.title.localizedCapitalized }.joined(separator: " → ")). Shop parts get rarer as they get pricier; every boss part is Legendary.", bundle: .app, comment: "Starts with the rarity names, lowest to highest")),
                Entry(icon: "chevron.up.2", tint: Palette.gold, title: String(localized: "Mk I–III", bundle: .app, comment: "Part levels Mark 1 to 3"),
                      text: String(localized: "Upgrade a part twice to sharpen its strengths or soften its drawback.", bundle: .app)),
                Entry(icon: "calendar", tint: Palette.gem, title: String(localized: "Daily Challenge", bundle: .app),
                      text: String(localized: "The same shaft and the same standard rig for everyone, every day. Beat your best score.", bundle: .app)),
            ]),
        ]
    }
}

private struct TopicCard: View {
    let topic: HowToPlayView.Topic
    let isOpen: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    Image(systemName: topic.icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(topic.tint)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Palette.panelSunken))
                    Text(topic.title)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                        .kerning(0.4)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(Palette.textSecondary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint(isOpen ? Text("Collapse") : Text("Expand"))

            if isOpen {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(topic.entries) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: entry.icon)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(entry.tint)
                                .frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(entry.title)
                                        .font(.system(size: 13, weight: .black, design: .rounded))
                                        .foregroundStyle(Palette.textPrimary)
                                    if let tag = entry.tag {
                                        Text(tag)
                                            .font(.system(size: 8, weight: .black, design: .rounded))
                                            .foregroundStyle(Palette.background)
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(Capsule().fill(entry.tagTint))
                                    }
                                }
                                Text(entry.text)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity)
            }
        }
        .card(18)
    }
}
