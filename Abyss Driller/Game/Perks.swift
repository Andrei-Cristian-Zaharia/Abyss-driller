import SwiftUI

/// Run-only upgrades. Every `perkInterval` metres, and after each boss, the run
/// pauses and offers three of these. They last until the run ends, which keeps
/// them separate from the four permanent `UpgradeTrack`s.
enum Perk: String, CaseIterable, Identifiable {
    case magnet, wideBit, diamondBit, spikedHull, comboKeeper, overcharge
    case prospector, efficientEngine, secondWind, powerSurge, plating, bigHold, reserveTank
    case bountyHunter, daredevil, rockBreaker, bossBreaker, autoRepair, thermalCore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .magnet: return String(localized: "MAGNET", bundle: .app, comment: "Perk name")
        case .wideBit: return String(localized: "WIDE BIT", bundle: .app, comment: "Perk name")
        case .diamondBit: return String(localized: "DIAMOND BIT", bundle: .app, comment: "Perk name")
        case .spikedHull: return String(localized: "SPIKED HULL", bundle: .app, comment: "Perk name")
        case .comboKeeper: return String(localized: "COMBO KEEPER", bundle: .app, comment: "Perk name")
        case .overcharge: return String(localized: "OVERCHARGE", bundle: .app, comment: "Perk name")
        case .prospector: return String(localized: "PROSPECTOR", bundle: .app, comment: "Perk name")
        case .efficientEngine: return String(localized: "EFFICIENT ENGINE", bundle: .app, comment: "Perk name")
        case .secondWind: return String(localized: "SECOND WIND", bundle: .app, comment: "Perk name")
        case .powerSurge: return String(localized: "POWER SURGE", bundle: .app, comment: "Perk name")
        case .plating: return String(localized: "EXTRA PLATING", bundle: .app, comment: "Perk name")
        case .bigHold: return String(localized: "BIG HOLD", bundle: .app, comment: "Perk name")
        case .reserveTank: return String(localized: "RESERVE TANK", bundle: .app, comment: "Perk name")
        case .bountyHunter: return String(localized: "BOUNTY HUNTER", bundle: .app, comment: "Perk name")
        case .daredevil: return String(localized: "DAREDEVIL", bundle: .app, comment: "Perk name")
        case .rockBreaker: return String(localized: "ROCK BREAKER", bundle: .app, comment: "Perk name")
        case .bossBreaker: return String(localized: "BOSS BREAKER", bundle: .app, comment: "Perk name")
        case .autoRepair: return String(localized: "AUTO-REPAIR", bundle: .app, comment: "Perk name")
        case .thermalCore: return String(localized: "THERMAL CORE", bundle: .app, comment: "Perk name")
        }
    }

    var detail: String {
        switch self {
        case .magnet: return String(localized: "Treasure nearby flies to you", bundle: .app, comment: "Perk description")
        case .wideBit: return String(localized: "Bigger bit: easier kills and blocks", bundle: .app, comment: "Perk description")
        case .diamondBit: return String(localized: "Drill straight through geodes", bundle: .app, comment: "Perk description")
        case .spikedHull: return String(localized: "Critters that touch you die instead", bundle: .app, comment: "Perk description")
        case .comboKeeper: return String(localized: "Combo lasts 1.2 s longer", bundle: .app, comment: "Perk description")
        case .overcharge: return String(localized: "Overdrive comes sooner, lasts longer", bundle: .app, comment: "Perk description")
        case .prospector: return String(localized: "Ore is worth 30% more", bundle: .app, comment: "Perk description")
        case .efficientEngine: return String(localized: "Burn 20% less fuel", bundle: .app, comment: "Perk description")
        case .secondWind: return String(localized: "Survive one more fatal hit", bundle: .app, comment: "Perk description")
        case .powerSurge: return String(localized: "+1 Power for this run", bundle: .app, comment: "Perk description")
        case .plating: return String(localized: "+2 armour, repaired now", bundle: .app, comment: "Perk description")
        case .bigHold: return String(localized: "+8 cargo slots", bundle: .app, comment: "Perk description")
        case .reserveTank: return String(localized: "Refill now, +5 fuel capacity", bundle: .app, comment: "Perk description")
        case .bountyHunter: return String(localized: "Critter kills pay 50% more", bundle: .app, comment: "Perk description")
        case .daredevil: return String(localized: "Close calls refuel more, double combo", bundle: .app, comment: "Perk description")
        case .rockBreaker: return String(localized: "Every rock you smash pays gold", bundle: .app, comment: "Perk description")
        case .bossBreaker: return String(localized: "Bosses recover faster: hit them sooner", bundle: .app, comment: "Perk description")
        case .autoRepair: return String(localized: "Repair 1 armour every 150 m", bundle: .app, comment: "Perk description")
        case .thermalCore: return String(localized: "Lava can't burn you, frost can't chill", bundle: .app, comment: "Perk description")
        }
    }

    var icon: String {
        switch self {
        case .magnet: return "dot.radiowaves.left.and.right"
        case .wideBit: return "arrow.up.left.and.arrow.down.right"
        case .diamondBit: return "diamond.fill"
        case .spikedHull: return "staroflife.fill"
        case .comboKeeper: return "timer"
        case .overcharge: return "bolt.circle.fill"
        case .prospector: return "sparkles"
        case .efficientEngine: return "leaf.fill"
        case .secondWind: return "heart.fill"
        case .powerSurge: return "bolt.fill"
        case .plating: return "shield.lefthalf.filled"
        case .bigHold: return "shippingbox.fill"
        case .reserveTank: return "fuelpump.fill"
        case .bountyHunter: return "scope"
        case .daredevil: return "figure.fall"
        case .rockBreaker: return "hammer.fill"
        case .bossBreaker: return "crown.fill"
        case .autoRepair: return "wrench.and.screwdriver.fill"
        case .thermalCore: return "thermometer.sun.fill"
        }
    }

    var tint: Color {
        switch self {
        case .magnet, .prospector, .bountyHunter, .rockBreaker: return Palette.gold
        case .daredevil: return Palette.window
        case .bossBreaker: return Palette.hazard
        case .autoRepair: return Palette.mint
        case .thermalCore: return Palette.lava
        case .wideBit, .diamondBit, .powerSurge, .overcharge: return Palette.drillBody
        case .spikedHull, .secondWind: return Palette.hazard
        case .comboKeeper, .bigHold: return Palette.gem
        case .efficientEngine, .reserveTank: return Palette.mint
        case .plating: return Palette.window
        }
    }

    /// Most perks stack without limit (with soft caps in the effects below);
    /// these two only ever do one thing.
    var maxStacks: Int {
        switch self {
        case .diamondBit, .spikedHull, .thermalCore: return 1
        default: return .max
        }
    }
}

extension GameWorld {
    static let perkInterval = 120.0
    static let firstPerkDepth = 50.0

    func stacks(_ perk: Perk) -> Int { perkStacks[perk] ?? 0 }

    /// Pauses the run on a pick-1-of-3. Offers come from their own seeded
    /// stream so a daily run offers everyone the same first choices.
    func offerPerks() {
        let open = Perk.allCases.filter { stacks($0) < $0.maxStacks }
        guard !open.isEmpty else { return }
        var pool = open
        var offer: [Perk] = []
        while offer.count < 3 && !pool.isEmpty {
            offer.append(pool.remove(at: perkRNG.int(0...(pool.count - 1))))
        }
        perkOffer = offer
        perksSeen.formUnion(offer.map(\.rawValue))
        isHolding = false
        steerVector = nil
        vx = 0
        vy = 0
        setPhase(.choosing)
        Haptics.bump()
    }

    func choosePerk(_ perk: Perk) {
        guard phase == .choosing, perkOffer.contains(perk) else { return }
        perkStacks[perk, default: 0] += 1
        perkOffer = []
        switch perk {
        case .powerSurge:
            loadout.power += 1
        case .plating:
            loadout.armor += 2
            armor = min(loadout.armor, armor + 2)
        case .bigHold:
            loadout.cargoSlots += 8
        case .reserveTank:
            loadout.fuelCapacity += 5
            fuel = loadout.fuelCapacity
        default:
            break
        }
        invuln = max(invuln, 0.6)
        setPhase(.drilling)
        shout(perk.title, tint: perk.tint)
        Audio.shared.play(.perk)
        burstParticles(count: reduceMotion ? 8 : 24, kind: .spark, color: perk.tint,
                       at: CGPoint(x: x, y: depth), speed: 6)
        Haptics.celebrate()
    }

    // MARK: Resolved perk effects

    // Stacks are unlimited, so anything that could break the game curves
    // toward a ceiling instead of growing forever.
    var bitReach: Double {
        Self.bitRadius * gear.bitFactor * (1 + 0.8 * (1 - pow(0.6, Double(stacks(.wideBit)))))
    }
    var comboWindowNow: Double { Self.comboWindow + 1.2 * Double(stacks(.comboKeeper)) }
    var overdriveComboNow: Int { max(8, Self.overdriveCombo - 4 * stacks(.overcharge)) }
    var overdriveTimeNow: Double { Self.overdriveTime + 1.5 * Double(stacks(.overcharge)) }
    var fuelBurnNow: Double {
        Self.fuelBurn * gear.burnFactor * max(0.35, pow(0.8, Double(stacks(.efficientEngine))))
            * (poison > 0 ? Self.poisonBurn : 1)
    }
    /// Bounty Hunter: critter kill gold multiplier (soft-capped at ×3).
    var bountyBonus: Double { 1 + min(2, 0.5 * Double(stacks(.bountyHunter))) }
    /// Rock Breaker: gold per smashed rock, as a share of the layer's ore value.
    var smashPay: Int { Int(Double(currentLayer.goldValue) * min(2, 0.5 * Double(stacks(.rockBreaker)))) }
    /// Boss Breaker: how long a boss stays immune after each hit.
    var bossGuardNow: Double { Self.bossHitGuard * max(0.45, pow(0.75, Double(stacks(.bossBreaker)))) }
    /// Auto-Repair: metres of new depth per armour repaired.
    var repairInterval: Double { max(60, 150 * pow(0.8, Double(stacks(.autoRepair) - 1))) }
    /// Lava-proof (Heat Shield or Thermal Core).
    var heatProof: Bool { gear.lavaImmune || stacks(.thermalCore) > 0 }

    var treasureBonus: Double { (1 + 0.3 * Double(stacks(.prospector))) * gear.oreBonus }
    var magnetRange: Double {
        let coil = gear.magnet
        let perk = stacks(.magnet) == 0 ? 0 : 1.4 + 1.2 * Double(stacks(.magnet))
        return min(6, max(coil, perk) + (coil > 0 && perk > 0 ? 1 : 0))
    }

    /// Pulls loose treasure toward the hull while Magnet is held.
    func applyMagnet(_ dt: Double) {
        let range = magnetRange
        guard range > 0 else { return }
        for index in pickups.indices where !pickups[index].collected {
            let dx = x - pickups[index].x, dy = depth - pickups[index].y
            let distance = hypot(dx, dy)
            guard distance < range, distance > 0.05 else { continue }
            let pull = min(distance, (4 + 6 * (1 - distance / range)) * dt)
            pickups[index].x += dx / distance * pull
            pickups[index].y += dy / distance * pull
        }
    }
}
