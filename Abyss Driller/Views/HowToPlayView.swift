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
                    ScreenHeader(title: "HOW TO PLAY", onBack: { app.screen = .home }) { EmptyView() }
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
            Topic(id: "basics", icon: "hand.tap.fill", tint: Palette.mint, title: "THE BASICS", entries: [
                Entry(icon: "hand.point.down.fill", tint: Palette.mint, title: "Hold to drill",
                      text: "Hold anywhere to dig. Let go to stop and keep your fuel."),
                Entry(icon: "arrow.up.and.down.and.arrow.left.and.right", tint: Palette.mint, title: "Drag to steer",
                      text: "Drag your thumb to turn the drill in any direction, even back up. You can change the sensitivity in Settings."),
                Entry(icon: "flag.checkered", tint: Palette.gold, title: "A run",
                      text: "Dig as deep as you can. The run ends when you run out of fuel or armour. Everything you carry is sold at the end."),
                Entry(icon: "wrench.and.screwdriver.fill", tint: Palette.drillBody, title: "Get stronger",
                      text: "Spend gold in the Workshop on permanent upgrades, and fit parts in the Garage."),
            ]),
            Topic(id: "gauges", icon: "gauge.with.dots.needle.67percent", tint: Palette.window, title: "FUEL & ARMOUR", entries: [
                Entry(icon: "fuelpump.fill", tint: Palette.mint, title: "Fuel",
                      text: "Burns while you drill, and faster when cutting through rock. Fuel cans give +\(Int(GameWorld.fuelCanAmount)). Close calls and boss kills refuel too. A double beep warns you when you're low."),
                Entry(icon: "shield.lefthalf.filled", tint: Palette.window, title: "Armour",
                      text: "Every hit costs armour. Spiky geodes cost 2. At zero the drill is wrecked. Each hit also costs a little fuel and resets your combo."),
                Entry(icon: "play.rectangle.fill", tint: Palette.gold, title: "Free refill",
                      text: "Out of fuel once per run? You can get one free refill (with a short ad, or instantly with Remove Ads). Not in the Daily Challenge."),
            ]),
            Topic(id: "rock", icon: "mountain.2.fill", tint: Palette.rock(hardness: 3), title: "ROCK & HAZARDS", entries: [
                Entry(icon: "bolt.fill", tint: Palette.drillBody, title: "Power vs hardness",
                      text: "Rock gets harder the deeper you go. If your Power is high enough you drill straight through; if not, it has a coral-red rim and hurts. Upgrade Power and the rim disappears."),
                Entry(icon: "staroflife.fill", tint: Palette.hazard, title: "Spiky geodes",
                      text: "Never drillable and cost 2 armour. Only Overdrive or the Diamond Bit perk breaks them (they look cracked when you can)."),
                Entry(icon: "arrow.triangle.branch", tint: Palette.window, title: "Close calls",
                      text: "Skim past a rock you can't break without touching it: \"CLOSE!\" gives fuel and combo."),
                Entry(icon: "flame.fill", tint: Palette.lava, title: "Lava",
                      text: "In the Magma Core, pools burn on contact. A dashed ring warns before new lava appears."),
                Entry(icon: "exclamationmark.circle.fill", tint: Palette.hazard, title: "Warnings",
                      text: "A dashed ring or line always shows where something is about to hit. Get out of it."),
            ]),
            Topic(id: "money", icon: "dollarsign.circle.fill", tint: Palette.gold, title: "ORE, CARGO & GOLD", entries: [
                Entry(icon: "shippingbox.fill", tint: Palette.gem, title: "The hold",
                      text: "Ore takes 1 slot and gems 2. It's sold when the run ends. Deeper ore is worth more per slot, so when the hold is full, better ore swaps out the worst."),
                Entry(icon: "circle.fill", tint: Palette.gold, title: "Coins",
                      text: "Kills, chests and boss rewards are coins: they never take space in the hold."),
                Entry(icon: "sparkles", tint: Palette.gold, title: "Ores",
                      text: Strata.layers.map { $0.ore.name.capitalized }.joined(separator: " · ") + ". Each one is worth more than the last."),
                Entry(icon: "cube.box.fill", tint: Palette.gold, title: "Treasure chests",
                      text: "Hidden in caves just past your best depth. Drill into one for a big payout."),
            ]),
            Topic(id: "combo", icon: "flame.fill", tint: Palette.drillBody, title: "COMBO & OVERDRIVE", entries: [
                Entry(icon: "multiply.circle.fill", tint: Palette.drillBody, title: "Combo",
                      text: "Ore, smashed rock, fuel cans, kills and close calls add to your combo. Every \(GameWorld.comboStep) raises the gold multiplier, up to ×4. It drops if you go \(Int(GameWorld.comboWindow)) s without scoring, or get hit."),
                Entry(icon: "bolt.circle.fill", tint: Palette.drillBody, title: "Overdrive",
                      text: "Reach a combo of \(GameWorld.overdriveCombo) and Overdrive fires for a few seconds: faster, no fuel burn, and you smash through everything, even spiky geodes."),
            ]),
            Topic(id: "status", icon: "snowflake", tint: Palette.frost, title: "STATUS EFFECTS", entries: [
                Entry(icon: "snowflake", tint: Palette.frost, title: "Chill",
                      text: "Frozen Depths. Slows the drill and its turning for a moment. Frost Runners make you immune."),
                Entry(icon: "aqi.medium", tint: Palette.spore, title: "Poison",
                      text: "Spore Hollow. Your fuel leaks out \(String(format: "%g", GameWorld.poisonBurn))× faster for a few seconds. The Spore Filter makes you immune."),
                Entry(icon: "tornado", tint: Palette.voidGlow, title: "Gravity",
                      text: "The Void (and the Pharaoh's sandstorm). Pulls the drill in: steer against it. The Void Drill ignores every pull."),
            ]),
            Topic(id: "events", icon: "exclamationmark.triangle.fill", tint: Palette.hazard, title: "EVENTS", entries: [
                Entry(icon: "exclamationmark.triangle.fill", tint: Palette.hazard, title: "Cave-in",
                      text: "Boulders fall from above. Smash them with your bit, or dodge."),
                Entry(icon: "sparkles", tint: Palette.gold, title: "Mother Lode",
                      text: "A burst of ore appears and every piece pays double for a few seconds."),
                Entry(icon: "moon.fill", tint: Palette.gem, title: "Lights Out",
                      text: "Only your headlight shows. Gems still glint. The Abyss Lantern keeps the lights on."),
            ]),
            Topic(id: "bosses", icon: "crown.fill", tint: Palette.hazard, title: "BOSSES", entries: [
                Entry(icon: "crown.fill", tint: Palette.hazard, title: "Guardians",
                      text: "A boss guards the end of every biome. Ram it with your bit, then back off: after each hit it can't hurt you for a moment."),
                Entry(icon: "bolt.fill", tint: Palette.hazard, title: "Three powers",
                      text: "Each boss has 3 powers. The third joins when it's enraged at half health. Every power is warned first."),
                Entry(icon: "arrow.uturn.down", tint: Palette.textSecondary, title: "Minis",
                      text: "Beat a boss once and it comes back as a mini: smaller, half the health, a bit faster."),
                Entry(icon: "hexagon.fill", tint: Palette.gold, title: "Cores & boss parts",
                      text: "Every boss win (mini or full) gives 1 core. Collect \(ShipPart.coresToUnlock) from a boss and its Legendary part goes on sale in the Garage. Cores also pay for boss part upgrades."),
                Entry(icon: "book.closed.fill", tint: Palette.paper, title: "Field Guide",
                      text: "Every creature and boss you meet gets a page with tips for beating it."),
            ]),
            Topic(id: "perks", icon: "star.circle.fill", tint: Palette.gem, title: "PERKS  \(found)/\(Perk.allCases.count)", entries: [
                Entry(icon: "rectangle.stack.fill", tint: Palette.gem, title: "Pick 1 of 3",
                      text: "At \(Int(GameWorld.firstPerkDepth)) m, then every \(Int(GameWorld.perkInterval)) m and after every boss. Perks last until the run ends. Most can be taken again to stack."),
                Entry(icon: "book.closed.fill", tint: Palette.paper, title: "Your perk collection",
                      text: "Every perk you've been offered is in the Field Guide, under Perks: what it does and whether it stacks. You've found \(found) of \(Perk.allCases.count)."),
            ]),
            Topic(id: "biomes", icon: "globe.europe.africa.fill", tint: Palette.mint, title: "BIOMES", entries:
                Strata.layers.enumerated().map { index, layer in
                    Entry(icon: "\(index + 1).circle.fill", tint: layer.ore.color, title: layer.name.capitalized,
                          text: "From \(Int(layer.startDepth)) m · \(layer.ore.name.capitalized) ore · boss: \(GameWorld.bossKind(index).title.capitalized)")
                }),
            Topic(id: "progress", icon: "wrench.and.screwdriver.fill", tint: Palette.drillBody, title: "WORKSHOP & GARAGE", entries: [
                Entry(icon: "arrow.up.circle.fill", tint: Palette.mint, title: "Workshop",
                      text: "Permanent upgrades: Power, Fuel, Armour and Cargo. No level cap."),
                Entry(icon: "gearshape.2.fill", tint: Palette.drillBody, title: "Garage parts",
                      text: "One bit, hull, tracks and module at a time. Parts are trade-offs: pick a build that suits you."),
                Entry(icon: "diamond.fill", tint: PartRarity.epic.color, title: "Rarity",
                      text: PartRarity.allCases.map { $0.title.capitalized }.joined(separator: " → ") + ". Shop parts get rarer as they get pricier; every boss part is Legendary."),
                Entry(icon: "chevron.up.2", tint: Palette.gold, title: "Mk I–III",
                      text: "Upgrade a part twice to sharpen its strengths or soften its drawback."),
                Entry(icon: "calendar", tint: Palette.gem, title: "Daily Challenge",
                      text: "The same shaft and the same standard rig for everyone, every day. Beat your best score."),
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
            .accessibilityHint(isOpen ? "Collapse" : "Expand")

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
                                            .background(Capsule().fill(tag == "ONCE" ? Palette.hazard : Palette.mint))
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
