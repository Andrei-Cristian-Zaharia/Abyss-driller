import SwiftUI

/// The four permanent upgrade tracks. Every number the game balances around
/// lives here so the whole curve can be read in one screen.
enum UpgradeTrack: String, CaseIterable, Identifiable, Codable {
    case power, fuel, armor, cargo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .power: return String(localized: "POWER", bundle: .app, comment: "Workshop upgrade name")
        case .fuel: return String(localized: "FUEL", bundle: .app, comment: "Workshop upgrade name")
        case .armor: return String(localized: "ARMOR", bundle: .app, comment: "Workshop upgrade name")
        case .cargo: return String(localized: "CARGO", bundle: .app, comment: "Workshop upgrade name")
        }
    }

    var tagline: String {
        switch self {
        case .power: return String(localized: "Bore through harder rock", bundle: .app)
        case .fuel: return String(localized: "Drill for longer", bundle: .app)
        case .armor: return String(localized: "Survive more hits", bundle: .app)
        case .cargo: return String(localized: "Haul more treasure home", bundle: .app)
        }
    }

    var icon: String {
        switch self {
        case .power: return "bolt.fill"
        case .fuel: return "fuelpump.fill"
        case .armor: return "shield.lefthalf.filled"
        case .cargo: return "shippingbox.fill"
        }
    }

    var tint: Color {
        switch self {
        case .power: return Palette.drillBody
        case .fuel: return Palette.mint
        case .armor: return Palette.window
        case .cargo: return Palette.gem
        }
    }

    /// Hand-tuned cost of the first levels. Past these, `price(atLevel:)`
    /// keeps going on a curve — tracks have no cap.
    var costs: [Int] {
        switch self {
        case .power: return [75, 180, 420, 900]
        case .fuel:  return [60, 150, 340, 700, 1300]
        case .armor: return [90, 220, 500, 1000]
        case .cargo: return [50, 130, 300, 650, 1200]
        }
    }

    /// Levels with a pip on the card. Not a cap: levels continue past it.
    var maxLevel: Int { costs.count }

    /// Price to go from `level` to `level + 1`. Each level past the authored
    /// list costs 1.55× the one before, rounded to 10, so gold stays useful
    /// without the curve ever flattening.
    func price(atLevel level: Int) -> Int? {
        if level < costs.count { return costs[level] }
        let extra = Double(level - costs.count + 1)
        return Int((Double(costs.last!) * pow(1.55, extra) / 10).rounded()) * 10
    }

    // MARK: Resolved stats

    static func power(_ level: Int) -> Int { 1 + level }                 // +1 per level, uncapped
    static func fuel(_ level: Int) -> Double { 100 + 10 * Double(level) } // +10 per level
    static func armor(_ level: Int) -> Int { 4 + level }                  // +1 per level
    static func cargo(_ level: Int) -> Int { 14 + 6 * level }             // +6 slots per level

    /// What the machine does right now.
    func currentText(level: Int) -> String {
        switch self {
        case .power: return String(localized: "Bores hardness \(Self.power(level))", bundle: .app, comment: "Workshop: the rock hardness the drill can break now")
        case .fuel:  return String(localized: "\(Int(Self.fuel(level))) fuel", bundle: .app, comment: "Workshop: current fuel tank size")
        case .armor: return String(localized: "\(Self.armor(level)) plates", bundle: .app, comment: "Workshop: current number of armour plates")
        case .cargo: return String(localized: "\(Self.cargo(level)) slots", bundle: .app, comment: "Workshop: current cargo hold slots")
        }
    }

    /// What the next level buys. Shown on the upgrade card.
    func nextBenefitText(level: Int) -> String {
        let next = level + 1
        switch self {
        case .power: return String(localized: "Bore hardness \(Self.power(next)) rock", bundle: .app, comment: "Workshop: what the next Power level unlocks")
        case .fuel:  return String(localized: "+10 fuel  →  \(Int(Self.fuel(next)))", bundle: .app, comment: "Workshop: next Fuel level")
        case .armor: return String(localized: "+1 plate  →  \(Self.armor(next)) hits", bundle: .app, comment: "Workshop: next Armor level")
        case .cargo: return String(localized: "+6 slots  →  \(Self.cargo(next))", bundle: .app, comment: "Workshop: next Cargo level")
        }
    }
}

struct UpgradeLevels: Codable, Equatable {
    var power = 0
    var fuel = 0
    var armor = 0
    var cargo = 0

    subscript(_ track: UpgradeTrack) -> Int {
        get {
            switch track {
            case .power: return power
            case .fuel: return fuel
            case .armor: return armor
            case .cargo: return cargo
            }
        }
        set {
            switch track {
            case .power: power = newValue
            case .fuel: fuel = newValue
            case .armor: armor = newValue
            case .cargo: cargo = newValue
            }
        }
    }
}

/// Upgrade levels flattened into the numbers the simulation actually reads.
struct Loadout {
    var power: Int
    var fuelCapacity: Double
    var armor: Int
    var cargoSlots: Int

    static func resolve(_ levels: UpgradeLevels) -> Loadout {
        Loadout(power: UpgradeTrack.power(levels.power),
                fuelCapacity: UpgradeTrack.fuel(levels.fuel),
                armor: UpgradeTrack.armor(levels.armor),
                cargoSlots: UpgradeTrack.cargo(levels.cargo))
    }

    /// Everyone drills the daily challenge in the same machine.
    static let dailyStandard = Loadout(power: 3, fuelCapacity: 144, armor: 4, cargoSlots: 26)
    static let dailyLevels = UpgradeLevels(power: 2, fuel: 2, armor: 1, cargo: 2)
}
