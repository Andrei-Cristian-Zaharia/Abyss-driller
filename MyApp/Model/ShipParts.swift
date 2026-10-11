import SwiftUI

/// The four places a part can go. One part per slot.
enum PartSlot: String, Codable, CaseIterable, Identifiable {
    case bit, hull, tracks, module

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bit: return "BIT"
        case .hull: return "HULL"
        case .tracks: return "TRACKS"
        case .module: return "MODULE"
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

    /// Short "+1 Power · 8% slower" style summary.
    var summary: String {
        var parts: [String] = []
        func pct(_ factor: Double, up: String, down: String) {
            let delta = Int(((factor - 1) * 100).rounded())
            if delta > 0 { parts.append("\(delta)% \(up)") } else if delta < 0 { parts.append("\(-delta)% \(down)") }
        }
        if power != 0 { parts.append("\(power > 0 ? "+" : "−")\(abs(power)) Power") }
        if armor != 0 { parts.append("\(armor > 0 ? "+" : "−")\(abs(armor)) armour") }
        if cargo != 0 { parts.append("+\(cargo) cargo") }
        if fuel != 0 { parts.append("\(fuel > 0 ? "+" : "−")\(Int(abs(fuel))) fuel") }
        if bit != 1 { pct(bit, up: "bigger bite", down: "smaller bite") }
        if killGold != 1 { parts.append("kills pay ×\(String(format: "%g", killGold))") }
        pct(speed, up: "faster", down: "slower")
        pct(turn, up: "sharper turns", down: "wider turns")
        pct(burn, up: "more fuel burn", down: "less fuel burn")
        if magnet > 0 { parts.append("pulls treasure \(String(format: "%g", magnet)) m") }
        if killFuel > 0 { parts.append("kills refuel \(String(format: "%g", killFuel))") }
        if smashFuel > 0 { parts.append("smashes refuel \(String(format: "%g", smashFuel))") }
        if coreCooldown > 0 { parts.append("shard every \(String(format: "%g", coreCooldown)) s") }
        if shieldRecharge > 0 { parts.append("blocks a hit every \(Int(shieldRecharge)) s") }
        if extraDamage > 0 { parts.append("hits cost +\(extraDamage) armour") }
        if lavaImmune { parts.append("lava-proof") }
        if noBore { parts.append("rock doesn't slow you") }
        if seeInDark { parts.append("sees in the dark") }
        if oreBonus != 1 { parts.append("ore worth +\(Int(((oreBonus - 1) * 100).rounded()))%") }
        if noStun { parts.append("rock hits don't stun") }
        return parts.isEmpty ? "No changes." : parts.joined(separator: " · ")
    }
}

/// Swappable machine parts. Unlike the four `UpgradeTrack`s, parts are
/// trade-offs, and each can be improved to Mk II and Mk III in the Garage.
/// Boss parts drop the first time that boss is beaten and are never for sale;
/// upgrading them also costs that boss's cores (one per kill).
enum ShipPart: String, Codable, CaseIterable, Identifiable {
    case standardBit, heavyBit, needleBit, glassCannon, twinAuger, queenFang
    case standardHull, lightFrame, cargoHull, bulwarkHull, carapace, heatShield
    case standardTracks, sportTracks, overclockTreads, hoverSkids, echoWings
    case noModule, magnetCoil, fuelRecycler, shieldModule, oreScanner, crystalCore, abyssLantern

    var id: String { rawValue }

    var slot: PartSlot {
        switch self {
        case .standardBit, .heavyBit, .needleBit, .glassCannon, .twinAuger, .queenFang: return .bit
        case .standardHull, .lightFrame, .cargoHull, .bulwarkHull, .carapace, .heatShield: return .hull
        case .standardTracks, .sportTracks, .overclockTreads, .hoverSkids, .echoWings: return .tracks
        case .noModule, .magnetCoil, .fuelRecycler, .shieldModule, .oreScanner, .crystalCore, .abyssLantern: return .module
        }
    }

    var title: String {
        switch self {
        case .standardBit: return "Standard Bit"
        case .heavyBit: return "Heavy Bit"
        case .needleBit: return "Needle Bit"
        case .glassCannon: return "Glass Cannon"
        case .twinAuger: return "Twin Auger"
        case .bulwarkHull: return "Bulwark Hull"
        case .hoverSkids: return "Hover Skids"
        case .oreScanner: return "Ore Scanner"
        case .queenFang: return "Queen's Fang"
        case .standardHull: return "Standard Hull"
        case .lightFrame: return "Light Frame"
        case .cargoHull: return "Cargo Hull"
        case .carapace: return "Carapace"
        case .heatShield: return "Heat Shield"
        case .standardTracks: return "Standard Tracks"
        case .sportTracks: return "Sport Tracks"
        case .overclockTreads: return "Overclock Treads"
        case .echoWings: return "Echo Wings"
        case .noModule: return "Empty"
        case .magnetCoil: return "Magnet Coil"
        case .fuelRecycler: return "Fuel Recycler"
        case .shieldModule: return "Shield Module"
        case .crystalCore: return "Crystal Core"
        case .abyssLantern: return "Abyss Lantern"
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
        case .standardHull: return "square.fill"
        case .lightFrame: return "wind"
        case .cargoHull: return "shippingbox.fill"
        case .carapace: return "shield.fill"
        case .heatShield: return "flame.fill"
        case .standardTracks: return "circle.grid.2x1.fill"
        case .sportTracks: return "speedometer"
        case .overclockTreads: return "gauge.with.dots.needle.100percent"
        case .echoWings: return "bird.fill"
        case .noModule: return "circle.dashed"
        case .magnetCoil: return "dot.radiowaves.left.and.right"
        case .fuelRecycler: return "arrow.3.trianglepath"
        case .shieldModule: return "circle.hexagongrid.fill"
        case .crystalCore: return "rhombus.fill"
        case .abyssLantern: return "lightbulb.max.fill"
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
        case .heavyBit: return 1000
        case .needleBit: return 800
        case .glassCannon: return 1400
        case .twinAuger: return 1800
        case .lightFrame: return 900
        case .cargoHull: return 800
        case .bulwarkHull: return 1700
        case .sportTracks: return 700
        case .overclockTreads: return 1300
        case .hoverSkids: return 1900
        case .magnetCoil: return 1100
        case .fuelRecycler: return 1000
        case .shieldModule: return 1600
        case .oreScanner: return 2200
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
        default: return nil
        }
    }

    static func drop(for boss: BossKind) -> ShipPart {
        allCases.first { $0.droppedBy == boss }!
    }

    static func parts(for slot: PartSlot) -> [ShipPart] { allCases.filter { $0.slot == slot } }

    var isStarter: Bool { price == nil && droppedBy == nil }

    // MARK: Levels

    static let maxLevel = 3

    /// Cost to reach `level` (2 or 3). Nil for starters.
    func upgradeCost(to level: Int) -> (gold: Int, cores: Int)? {
        guard !isStarter, level >= 2, level <= Self.maxLevel else { return nil }
        if let price { return (price * (level - 1), 0) }
        return (level == 2 ? 1200 : 2800, level - 1)
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
        case .standardBit, .standardHull, .standardTracks, .noModule:
            break
        }
        return s
    }

    var starterBlurb: String {
        switch self {
        case .standardBit: return "Reliable. No surprises."
        case .standardHull: return "Balanced plating."
        case .standardTracks: return "Steady steering."
        default: return "Nothing fitted."
        }
    }

    func detail(level: Int) -> String {
        isStarter ? starterBlurb : stats(level: level).summary
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
