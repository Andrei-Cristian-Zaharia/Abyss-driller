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
        case .magnet: return "MAGNET"
        case .wideBit: return "WIDE BIT"
        case .diamondBit: return "DIAMOND BIT"
        case .spikedHull: return "SPIKED HULL"
        case .comboKeeper: return "COMBO KEEPER"
        case .overcharge: return "OVERCHARGE"
        case .prospector: return "PROSPECTOR"
        case .efficientEngine: return "EFFICIENT ENGINE"
        case .secondWind: return "SECOND WIND"
        case .powerSurge: return "POWER SURGE"
        case .plating: return "EXTRA PLATING"
        case .bigHold: return "BIG HOLD"
        case .reserveTank: return "RESERVE TANK"
        case .bountyHunter: return "BOUNTY HUNTER"
        case .daredevil: return "DAREDEVIL"
        case .rockBreaker: return "ROCK BREAKER"
        case .bossBreaker: return "BOSS BREAKER"
        case .autoRepair: return "AUTO-REPAIR"
        case .thermalCore: return "THERMAL CORE"
        }
    }

    var detail: String {
        switch self {
        case .magnet: return "Treasure nearby flies to you"
        case .wideBit: return "Bigger bit: easier kills and blocks"
        case .diamondBit: return "Drill straight through geodes"
        case .spikedHull: return "Critters that touch you die instead"
        case .comboKeeper: return "Combo lasts 1.2 s longer"
        case .overcharge: return "Overdrive comes sooner, lasts longer"
        case .prospector: return "Ore is worth 30% more"
        case .efficientEngine: return "Burn 20% less fuel"
        case .secondWind: return "Survive one more fatal hit"
        case .powerSurge: return "+1 Power for this run"
        case .plating: return "+2 armour, repaired now"
        case .bigHold: return "+8 cargo slots"
        case .reserveTank: return "Refill now, +5 fuel capacity"
        case .bountyHunter: return "Critter kills pay 50% more"
        case .daredevil: return "Close calls refuel more, double combo"
        case .rockBreaker: return "Every rock you smash pays gold"
        case .bossBreaker: return "Bosses recover faster: hit them sooner"
        case .autoRepair: return "Repair 1 armour every 150 m"
        case .thermalCore: return "Lava can't burn you, frost can't chill"
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
