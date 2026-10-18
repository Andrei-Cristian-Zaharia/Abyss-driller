import SwiftUI

/// The four permanent upgrade tracks. Every number the game balances around
/// lives here so the whole curve can be read in one screen.
enum UpgradeTrack: String, CaseIterable, Identifiable, Codable {
    case power, fuel, armor, cargo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .power: return "POWER"
        case .fuel: return "FUEL"
        case .armor: return "ARMOR"
        case .cargo: return "CARGO"
        }
    }

    var tagline: String {
        switch self {
        case .power: return "Bore through harder rock"
        case .fuel: return "Drill for longer"
        case .armor: return "Survive more hits"
        case .cargo: return "Haul more treasure home"
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
        case .power: return "Bores hardness \(Self.power(level))"
        case .fuel:  return "\(Int(Self.fuel(level))) fuel"
        case .armor: return "\(Self.armor(level)) plates"
        case .cargo: return "\(Self.cargo(level)) slots"
        }
    }

    /// What the next level buys. Shown on the upgrade card.
    func nextBenefitText(level: Int) -> String {
        let next = level + 1
        switch self {
        case .power: return "Bore hardness \(Self.power(next)) rock"
        case .fuel:  return "+10 fuel  →  \(Int(Self.fuel(next)))"
        case .armor: return "+1 plate  →  \(Self.armor(next)) hits"
        case .cargo: return "+6 slots  →  \(Self.cargo(next))"
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
