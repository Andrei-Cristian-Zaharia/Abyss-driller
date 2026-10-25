import SwiftUI

/// The four places a part can go. One part per slot.
enum PartSlot: String, Codable, CaseIterable, Identifiable {
    case bit, hull, tracks, module

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bit: return String(localized: "BIT", bundle: .app, comment: "Garage slot name (drill part type)")
        case .hull: return String(localized: "HULL", bundle: .app, comment: "Garage slot name (drill part type)")
        case .tracks: return String(localized: "TRACKS", bundle: .app, comment: "Garage slot name (drill part type)")
        case .module: return String(localized: "MODULE", bundle: .app, comment: "Garage slot name (drill part type)")
        }
    }
}

/// Everything a part can change. Neutral by default; a part sets only what it
/// touches. Card text is generated from this, so numbers and copy never drift.
struct PartStats {
    var power = 0
    var armor = 0
    var cargo = 0
    var fuel = 0.0
    var speed = 1.0
    var turn = 1.0
    var burn = 1.0
    var bit = 1.0
    var magnet = 0.0
    var killFuel = 0.0
    var smashFuel = 0.0
    /// Seconds between Crystal Core shards; 0 means no core.
    var coreCooldown = 0.0
    /// Seconds for the shield to recharge; 0 means no shield.
    var shieldRecharge = 0.0
    var killGold = 1.0
    /// Extra armour lost on every hit (Glass Cannon).
    var extraDamage = 0
    var lavaImmune = false
    var noStun = false
    /// Drilling through rock does not slow the drill down.
    var noBore = false
    /// Multiplies the value of every piece of ore and every gem picked up.
    var oreBonus = 1.0
    /// Darkness (Lights Out, the Angler's blackout) never hides anything.
    var seeInDark = false
    /// Frost never slows the drill (Frozen Depths).
    var chillImmune = false
    /// Poison never makes the drill leak fuel (Spore Hollow).
    var poisonImmune = false
    /// No pull moves the drill: black holes, singularities, the sandstorm.
    var gravityImmune = false

    /// Short "+1 Power · 8% slower" style summary.
    var summary: String {
        var parts: [String] = []
        func pct(_ factor: Double) -> Int { Int(((factor - 1) * 100).rounded()) }
        func num(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
        let sign = { (value: Int) in value > 0 ? "+" : "−" }
        if power != 0 { parts.append(String(localized: "\(sign(power))\(abs(power)) Power", bundle: .app, comment: "Part stat: drill Power change, e.g. +1 Power")) }
        if armor != 0 { parts.append(String(localized: "\(sign(armor))\(abs(armor)) armour", bundle: .app, comment: "Part stat: armour plates change")) }
        if cargo != 0 { parts.append(String(localized: "+\(cargo) cargo", bundle: .app, comment: "Part stat: extra cargo slots")) }
        if fuel != 0 { parts.append(String(localized: "\(fuel > 0 ? "+" : "−")\(Int(abs(fuel))) fuel", bundle: .app, comment: "Part stat: fuel tank change")) }
        let bite = pct(bit)
        if bite > 0 { parts.append(String(localized: "\(bite)% bigger bite", bundle: .app, comment: "Part stat: the drill bit clears a wider area")) }
        else if bite < 0 { parts.append(String(localized: "\(-bite)% smaller bite", bundle: .app, comment: "Part stat: the drill bit clears a narrower area")) }
        if killGold != 1 { parts.append(String(localized: "kills pay ×\(num(killGold))", bundle: .app, comment: "Part stat: gold multiplier for killing creatures")) }
        let fast = pct(speed)
        if fast > 0 { parts.append(String(localized: "\(fast)% faster", bundle: .app, comment: "Part stat: drill speed")) }
        else if fast < 0 { parts.append(String(localized: "\(-fast)% slower", bundle: .app, comment: "Part stat: drill speed")) }
        let sharp = pct(turn)
        if sharp > 0 { parts.append(String(localized: "\(sharp)% sharper turns", bundle: .app, comment: "Part stat: turning rate")) }
        else if sharp < 0 { parts.append(String(localized: "\(-sharp)% wider turns", bundle: .app, comment: "Part stat: turning rate")) }
        let burnDelta = pct(burn)
        if burnDelta > 0 { parts.append(String(localized: "\(burnDelta)% more fuel burn", bundle: .app, comment: "Part stat: fuel consumption")) }
        else if burnDelta < 0 { parts.append(String(localized: "\(-burnDelta)% less fuel burn", bundle: .app, comment: "Part stat: fuel consumption")) }
        if magnet > 0 { parts.append(String(localized: "pulls treasure \(num(magnet)) m", bundle: .app, comment: "Part stat: magnet range in metres")) }
        if killFuel > 0 { parts.append(String(localized: "kills refuel \(num(killFuel))", bundle: .app, comment: "Part stat: fuel gained per kill")) }
        if smashFuel > 0 { parts.append(String(localized: "smashes refuel \(num(smashFuel))", bundle: .app, comment: "Part stat: fuel gained per smashed rock")) }
        if coreCooldown > 0 { parts.append(String(localized: "shard every \(num(coreCooldown)) s", bundle: .app, comment: "Part stat: fires a crystal shard every N seconds")) }
        if shieldRecharge > 0 { parts.append(String(localized: "blocks a hit every \(Int(shieldRecharge)) s", bundle: .app, comment: "Part stat: shield recharge time in seconds")) }
        if extraDamage > 0 { parts.append(String(localized: "hits cost +\(extraDamage) armour", bundle: .app, comment: "Part stat: each hit removes extra armour")) }
        if lavaImmune { parts.append(String(localized: "lava-proof", bundle: .app, comment: "Part stat: immune to lava")) }
        if noBore { parts.append(String(localized: "rock doesn't slow you", bundle: .app, comment: "Part stat")) }
        if seeInDark { parts.append(String(localized: "sees in the dark", bundle: .app, comment: "Part stat")) }
        if chillImmune { parts.append(String(localized: "frost-proof", bundle: .app, comment: "Part stat: immune to frost slow")) }
        if poisonImmune { parts.append(String(localized: "poison-proof", bundle: .app, comment: "Part stat: immune to poison")) }
        if gravityImmune { parts.append(String(localized: "pull-proof", bundle: .app, comment: "Part stat: immune to gravity pulls")) }
        if oreBonus != 1 { parts.append(String(localized: "ore worth +\(Int(((oreBonus - 1) * 100).rounded()))%", bundle: .app, comment: "Part stat: ore value bonus")) }
        if noStun { parts.append(String(localized: "rock hits don't stun", bundle: .app, comment: "Part stat")) }
        return parts.isEmpty ? String(localized: "No changes.", bundle: .app, comment: "Part stat summary when a part changes nothing") : parts.joined(separator: " · ")
    }
}

/// Swappable machine parts. Unlike the four `UpgradeTrack`s, parts are
/// trade-offs, and each can be improved to Mk II and Mk III in the Garage.
/// Boss parts drop the first time that boss is beaten and are never for sale;
/// upgrading them also costs that boss's cores (one per kill).
enum ShipPart: String, Codable, CaseIterable, Identifiable {
    case standardBit, heavyBit, needleBit, glassCannon, twinAuger, queenFang, voidDrill
    case standardHull, lightFrame, cargoHull, bulwarkHull, carapace, heatShield, pharaohShroud
    case standardTracks, sportTracks, overclockTreads, hoverSkids, echoWings, frostRunners
    case noModule, magnetCoil, fuelRecycler, shieldModule, oreScanner, crystalCore, abyssLantern, sporeFilter

    var id: String { rawValue }

    var slot: PartSlot {
        switch self {
        case .standardBit, .heavyBit, .needleBit, .glassCannon, .twinAuger, .queenFang, .voidDrill: return .bit
        case .standardHull, .lightFrame, .cargoHull, .bulwarkHull, .carapace, .heatShield, .pharaohShroud: return .hull
        case .standardTracks, .sportTracks, .overclockTreads, .hoverSkids, .echoWings, .frostRunners: return .tracks
        case .noModule, .magnetCoil, .fuelRecycler, .shieldModule, .oreScanner, .crystalCore, .abyssLantern, .sporeFilter: return .module
        }
    }

    var title: String {
        switch self {
        case .standardBit: return String(localized: "Standard Bit", bundle: .app, comment: "Drill part name")
        case .heavyBit: return String(localized: "Heavy Bit", bundle: .app, comment: "Drill part name")
        case .needleBit: return String(localized: "Needle Bit", bundle: .app, comment: "Drill part name")
        case .glassCannon: return String(localized: "Glass Cannon", bundle: .app, comment: "Drill part name")
        case .twinAuger: return String(localized: "Twin Auger", bundle: .app, comment: "Drill part name")
        case .bulwarkHull: return String(localized: "Bulwark Hull", bundle: .app, comment: "Drill part name")
        case .hoverSkids: return String(localized: "Hover Skids", bundle: .app, comment: "Drill part name")
        case .oreScanner: return String(localized: "Ore Scanner", bundle: .app, comment: "Drill part name")
        case .queenFang: return String(localized: "Queen's Fang", bundle: .app, comment: "Drill part name")
        case .voidDrill: return String(localized: "Void Drill", bundle: .app, comment: "Drill part name")
        case .standardHull: return String(localized: "Standard Hull", bundle: .app, comment: "Drill part name")
        case .lightFrame: return String(localized: "Light Frame", bundle: .app, comment: "Drill part name")
        case .cargoHull: return String(localized: "Cargo Hull", bundle: .app, comment: "Drill part name")
        case .carapace: return String(localized: "Carapace", bundle: .app, comment: "Drill part name")
        case .heatShield: return String(localized: "Heat Shield", bundle: .app, comment: "Drill part name")
        case .pharaohShroud: return String(localized: "Pharaoh's Shroud", bundle: .app, comment: "Drill part name")
        case .standardTracks: return String(localized: "Standard Tracks", bundle: .app, comment: "Drill part name")
        case .sportTracks: return String(localized: "Sport Tracks", bundle: .app, comment: "Drill part name")
        case .overclockTreads: return String(localized: "Overclock Treads", bundle: .app, comment: "Drill part name")
        case .echoWings: return String(localized: "Echo Wings", bundle: .app, comment: "Drill part name")
        case .frostRunners: return String(localized: "Frost Runners", bundle: .app, comment: "Drill part name")
        case .noModule: return String(localized: "Empty", bundle: .app, comment: "Drill part name")
        case .magnetCoil: return String(localized: "Magnet Coil", bundle: .app, comment: "Drill part name")
        case .fuelRecycler: return String(localized: "Fuel Recycler", bundle: .app, comment: "Drill part name")
        case .shieldModule: return String(localized: "Shield Module", bundle: .app, comment: "Drill part name")
        case .crystalCore: return String(localized: "Crystal Core", bundle: .app, comment: "Drill part name")
        case .abyssLantern: return String(localized: "Abyss Lantern", bundle: .app, comment: "Drill part name")
        case .sporeFilter: return String(localized: "Spore Filter", bundle: .app, comment: "Drill part name")
        }
    }

    var icon: String {
        switch self {
        case .standardBit: return "arrowtriangle.down.fill"
        case .heavyBit: return "hammer.fill"
        case .needleBit: return "line.diagonal"
        case .glassCannon: return "exclamationmark.triangle.fill"
        case .twinAuger: return "tornado"
        case .bulwarkHull: return "shield.checkered"
        case .hoverSkids: return "hare.fill"
        case .oreScanner: return "antenna.radiowaves.left.and.right"
        case .queenFang: return "crown.fill"
        case .voidDrill: return "sparkles"
        case .standardHull: return "square.fill"
        case .lightFrame: return "wind"
        case .cargoHull: return "shippingbox.fill"
        case .carapace: return "shield.fill"
        case .heatShield: return "flame.fill"
        case .pharaohShroud: return "scroll.fill"
        case .standardTracks: return "circle.grid.2x1.fill"
        case .sportTracks: return "speedometer"
        case .overclockTreads: return "gauge.with.dots.needle.100percent"
        case .echoWings: return "bird.fill"
        case .frostRunners: return "snowflake"
        case .noModule: return "circle.dashed"
        case .magnetCoil: return "dot.radiowaves.left.and.right"
        case .fuelRecycler: return "arrow.3.trianglepath"
        case .shieldModule: return "circle.hexagongrid.fill"
        case .crystalCore: return "rhombus.fill"
        case .abyssLantern: return "lightbulb.max.fill"
        case .sporeFilter: return "aqi.medium"
        }
    }

    var tint: Color {
        switch self {
        case .queenFang: return Palette.worm
        case .carapace: return Palette.beetleSheen
        case .echoWings: return Palette.batWing
        case .crystalCore: return Palette.spitter
        case .heatShield: return Palette.lava
        case .abyssLantern: return Palette.abyssGlow
        case .pharaohShroud: return Palette.pharaoh
        case .frostRunners: return Palette.frost
        case .sporeFilter: return Palette.spore
        case .voidDrill: return Palette.voidGlow
        case .heavyBit, .needleBit: return Palette.drillBody
        case .glassCannon, .overclockTreads: return Palette.hazard
        case .twinAuger: return Palette.drillBit
        case .bulwarkHull: return Palette.beetleSheen
        case .hoverSkids: return Palette.window
        case .oreScanner: return Palette.gold
        case .lightFrame, .sportTracks, .shieldModule: return Palette.window
        case .cargoHull: return Palette.gem
        case .magnetCoil: return Palette.gold
        case .fuelRecycler: return Palette.mint
        default: return Palette.textSecondary
        }
    }

    /// Risky parts get a warning badge in the Garage.
    var isRisky: Bool { self == .glassCannon || self == .overclockTreads }

    /// Gold price in the Garage; nil for free starters and boss drops.
    var price: Int? {
        switch self {
        case .heavyBit: return 1500
        case .needleBit: return 1200
        case .glassCannon: return 2100
        case .twinAuger: return 2700
        case .lightFrame: return 1400
        case .cargoHull: return 1200
        case .bulwarkHull: return 2600
        case .sportTracks: return 1100
        case .overclockTreads: return 2000
        case .hoverSkids: return 2900
        case .magnetCoil: return 1700
        case .fuelRecycler: return 1500
        case .shieldModule: return 2400
        case .oreScanner: return 3300
        default: return nil
        }
    }

    /// The boss that drops this part.
    var droppedBy: BossKind? {
        switch self {
        case .queenFang: return .wormQueen
        case .echoWings: return .batMatriarch
        case .carapace: return .beetleTank
        case .crystalCore: return .crystalGolem
        case .heatShield: return .magmaTitan
        case .abyssLantern: return .abyssAngler
        case .pharaohShroud: return .stonePharaoh
        case .frostRunners: return .frostWyrm
        case .sporeFilter: return .sporemother
        case .voidDrill: return .starEater
        default: return nil
        }
    }

    /// Boss parts unlock once this many of that boss's cores have been
    /// collected in total (one per kill, minis included). Spending cores on
    /// upgrades never sets this back: it counts lifetime kills.
    static let coresToUnlock = 10

    /// Gold to buy a boss part once its 10 cores are collected: deeper
    /// bosses' parts cost more, always above the priciest shop part.
    var legendaryPrice: Int? {
        guard let boss = droppedBy, let index = BossKind.allCases.firstIndex(of: boss) else { return nil }
        return 4000 + 1000 * index
    }

    /// What the Garage charges: the shop price, or a boss part's legendary price.
    var buyPrice: Int? { price ?? legendaryPrice }

    static func drop(for boss: BossKind) -> ShipPart {
        allCases.first { $0.droppedBy == boss }!
    }

    /// A slot's parts, common to legendary (cheapest first within a rarity).
    static func parts(for slot: PartSlot) -> [ShipPart] {
        allCases.filter { $0.slot == slot }.sorted {
            ($0.rarity, $0.buyPrice ?? 0) < ($1.rarity, $1.buyPrice ?? 0)
        }
    }

    var isStarter: Bool { price == nil && droppedBy == nil }

    // MARK: Levels

    static let maxLevel = 3

    /// Cost to reach `level` (2 or 3). Nil for starters.
    func upgradeCost(to level: Int) -> (gold: Int, cores: Int)? {
        guard !isStarter, level >= 2, level <= Self.maxLevel else { return nil }
        if let price { return (price * (level - 1), 0) }
        return (level == 2 ? 1800 : 4200, level - 1)
    }

    /// Numbers per Mk level (1...3). Upgrades soften drawbacks or sharpen strengths.
    func stats(level: Int) -> PartStats {
        let l = max(1, min(Self.maxLevel, level))
        let i = Double(l - 1)
        var s = PartStats()
        switch self {
        case .heavyBit:
            s.power = l == 3 ? 2 : 1
            s.speed = 0.92 + 0.03 * i
        case .needleBit:
            s.speed = 1.12 + 0.04 * i
            s.power = l == 3 ? 0 : -1
        case .glassCannon:
            s.killGold = 2 + 0.5 * i
            s.bit = 1.15
            s.extraDamage = 1
        case .twinAuger:
            s.noBore = true
            s.bit = 1.1 + 0.05 * i
            s.turn = 0.9 + 0.05 * i
        case .bulwarkHull:
            s.armor = 3 + l - 1
            s.speed = 0.88 + 0.03 * i
        case .hoverSkids:
            s.speed = 1.15 + 0.03 * i
            s.turn = 1.15 + 0.05 * i
            s.fuel = -15 + 5 * i
        case .oreScanner:
            s.oreBonus = 1.2 + 0.1 * i
        case .queenFang:
            s.bit = 1.3 + 0.1 * i
            s.killFuel = 2 + 0.5 * i
        case .lightFrame:
            s.speed = 1.10 + 0.03 * i
            s.burn = 0.85 - 0.05 * i
            s.armor = l == 3 ? 0 : -1
        case .cargoHull:
            s.cargo = 8 + 3 * l - 3
            s.speed = 0.94 + 0.02 * i
        case .carapace:
            s.armor = 2 + l - 1
            s.noStun = true
        case .heatShield:
            s.lavaImmune = true
            s.armor = l
        case .sportTracks:
            s.turn = 1.35 + 0.1 * i
            s.fuel = -10 + 5 * i
        case .overclockTreads:
            s.speed = 1.25 + 0.05 * i
            s.burn = 1.4 - 0.1 * i
        case .echoWings:
            s.turn = 1.4 + 0.1 * i
            s.speed = 1.08 + 0.02 * i
        case .magnetCoil:
            s.magnet = 2.2 + 0.6 * i
        case .fuelRecycler:
            s.killFuel = 1 + 0.25 * i
            s.smashFuel = 1 + 0.25 * i
        case .shieldModule:
            s.shieldRecharge = [20, 15, 11][l - 1]
        case .crystalCore:
            s.coreCooldown = [2.0, 1.6, 1.25][l - 1]
        case .abyssLantern:
            s.seeInDark = true
            s.magnet = 2.4 + 0.6 * i
        case .voidDrill:
            s.gravityImmune = true
            s.bit = 1.15 + 0.05 * i
            s.power = l == 3 ? 1 : 0
        case .sporeFilter:
            s.poisonImmune = true
            s.burn = 0.92 - 0.04 * i
        case .frostRunners:
            s.chillImmune = true
            s.speed = 1.08 + 0.03 * i
            s.turn = 1.15 + 0.05 * i
        case .pharaohShroud:
            s.armor = l == 3 ? 2 : 1
            s.killGold = 1.3 + 0.1 * i
            s.oreBonus = 1.1 + 0.05 * i
        case .standardBit, .standardHull, .standardTracks, .noModule:
            break
        }
        return s
    }

    var starterBlurb: String {
        switch self {
        case .standardBit: return String(localized: "Reliable. No surprises.", bundle: .app, comment: "Starter part description")
        case .standardHull: return String(localized: "Balanced plating.", bundle: .app, comment: "Starter part description")
        case .standardTracks: return String(localized: "Steady steering.", bundle: .app, comment: "Starter part description")
        default: return String(localized: "Nothing fitted.", bundle: .app, comment: "Starter part description")
        }
    }

    func detail(level: Int) -> String {
        isStarter ? starterBlurb : stats(level: level).summary
    }
}

/// How rare a part is. Starters are common, boss parts legendary, and
/// shop parts are graded by price, so a new part gets a rarity for free.
enum PartRarity: Int, Comparable, CaseIterable {
    case common, uncommon, rare, epic, legendary

    static func < (a: PartRarity, b: PartRarity) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .common: return String(localized: "COMMON", bundle: .app, comment: "Part rarity tier")
        case .uncommon: return String(localized: "UNCOMMON", bundle: .app, comment: "Part rarity tier")
        case .rare: return String(localized: "RARE", bundle: .app, comment: "Part rarity tier")
        case .epic: return String(localized: "EPIC", bundle: .app, comment: "Part rarity tier")
        case .legendary: return String(localized: "LEGENDARY", bundle: .app, comment: "Part rarity tier")
        }
    }

    var color: Color {
        switch self {
        case .common: return Color(hex: 0x9AA3B5)
        case .uncommon: return Color(hex: 0x5ED68A)
        case .rare: return Color(hex: 0x5AA8FF)
        case .epic: return Color(hex: 0xB77CFF)
        case .legendary: return Palette.gold
        }
    }
}

extension ShipPart {
    var rarity: PartRarity {
        if droppedBy != nil { return .legendary }
        guard let price else { return .common }
        if price < 1600 { return .uncommon }
        if price < 2500 { return .rare }
        return .epic
    }
}

/// What is bolted on right now, one part per slot.
struct ShipBuild: Codable, Hashable {
    var bit: ShipPart = .standardBit
    var hull: ShipPart = .standardHull
    var tracks: ShipPart = .standardTracks
    var module: ShipPart = .noModule

    static let standard = ShipBuild()

    subscript(slot: PartSlot) -> ShipPart {
        get {
            switch slot {
            case .bit: return bit
            case .hull: return hull
            case .tracks: return tracks
            case .module: return module
            }
        }
        set {
            precondition(newValue.slot == slot)
            switch slot {
            case .bit: bit = newValue
            case .hull: hull = newValue
            case .tracks: tracks = newValue
            case .module: module = newValue
            }
        }
    }

    var parts: [ShipPart] { [bit, hull, tracks, module] }

    func has(_ part: ShipPart) -> Bool { self[part.slot] == part }
}

/// A build plus the Mk level of each part: everything a run needs to know
/// about the machine. `GameWorld` reads part effects only through this.
struct Gear {
    var build: ShipBuild
    var levels: [ShipPart: Int] = [:]

    static let standard = Gear(build: .standard)

    func level(_ part: ShipPart) -> Int { max(1, levels[part] ?? 1) }
    func has(_ part: ShipPart) -> Bool { build.has(part) }

    private var all: [PartStats] { build.parts.map { $0.stats(level: level($0)) } }

    var speedFactor: Double { all.reduce(1) { $0 * $1.speed } }
    var turnFactor: Double { all.reduce(1) { $0 * $1.turn } }
    var burnFactor: Double { all.reduce(1) { $0 * $1.burn } }
    var bitFactor: Double { all.reduce(1) { $0 * $1.bit } }
    var killGold: Double { all.reduce(1) { $0 * $1.killGold } }
    var magnet: Double { all.map(\.magnet).max() ?? 0 }
    var killFuel: Double { all.map(\.killFuel).reduce(0, +) }
    var smashFuel: Double { all.map(\.smashFuel).reduce(0, +) }
    var coreCooldown: Double { all.map(\.coreCooldown).max() ?? 0 }
    var shieldRecharge: Double { all.map(\.shieldRecharge).max() ?? 0 }
    var extraDamage: Int { all.map(\.extraDamage).reduce(0, +) }
    var lavaImmune: Bool { all.contains(where: \.lavaImmune) }
    var noStun: Bool { all.contains(where: \.noStun) }
    var noBore: Bool { all.contains(where: \.noBore) }
    var oreBonus: Double { all.reduce(1) { $0 * $1.oreBonus } }
    var seeInDark: Bool { all.contains(where: \.seeInDark) }
    var chillImmune: Bool { all.contains(where: \.chillImmune) }
    var poisonImmune: Bool { all.contains(where: \.poisonImmune) }
    var gravityImmune: Bool { all.contains(where: \.gravityImmune) }

    /// The permanent rig with this build's flat bonuses applied.
    func apply(to loadout: Loadout) -> Loadout {
        var result = loadout
        result.power = max(1, result.power + all.map(\.power).reduce(0, +))
        result.armor = max(1, result.armor + all.map(\.armor).reduce(0, +))
        result.cargoSlots += all.map(\.cargo).reduce(0, +)
        result.fuelCapacity = max(40, result.fuelCapacity + all.map(\.fuel).reduce(0, +))
        return result
    }
}
