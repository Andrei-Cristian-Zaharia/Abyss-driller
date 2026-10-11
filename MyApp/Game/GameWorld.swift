import SwiftUI

enum RunPhase { case ready, drilling, choosing, stalled, ended }
enum RunEndReason { case outOfFuel, wrecked }

struct RunResult: Identifiable {
    let id = UUID()
    var depth: Int
    var previousBest: Int
    var newRecord: Bool
    var collected: Int        // ore value + coins
    var banked: Int           // what the run is worth before double gold
    var payout: Int           // after the double-gold multiplier
    /// The hold, sold at the surface.
    var oreValue: Int
    var oreCount: Int
    /// Weightless earnings: bounties, chests, trail and boss rewards.
    var coins: Int
    var gems: Int
    var chambers: Int
    var cargoOverflowed: Bool
    var reason: RunEndReason
    var bestCombo: Int
    var enemiesDefeated: Int
    var bossesDefeated: Int
    var bossKindsDefeated: [BossKind]
    /// Field Guide pages met this run, and kills per page.
    var bestiarySeen: Set<String>
    var bestiaryKills: [String: Int]
    /// Filled in by `AppModel`: pages unlocked for the first time.
    var newEntries: [String] = []
    /// Filled in by `AppModel` once it knows which drops were new.
    var newParts: [ShipPart] = []
    var isDaily: Bool
    var dailyScore: Int
}

/// The whole simulation. Deliberately *not* `@Observable`: the view redraws
/// every frame from a `TimelineView`, so per-property invalidation would be
/// pure overhead.
final class GameWorld {

    // MARK: - Tuning

    static let shaftWidth = 9.0
    static let wallMargin = 0.9
    static let descentSpeed = 7.2
    static let maxLateral = 6.6
    /// How fast the drill swings round to a new heading, radians per second.
    static let turnRate = 4.2
    static let fuelBurn = 3.3
    static let bandHeight = 6.0
    /// Drill sits a third of the way down so obstacles below are visible.
    static let cameraAnchor = 0.33
    static let bodyRadius = 0.72
    static let bitRadius = 0.45
    static let bitOffset = 0.95
    static let minGap = 2.7
    /// Descent speeds up with depth so the deep layers feel like a plunge.
    static let topSpeed = 10.2
    static let speedRampDepth = 500.0
    /// Seconds a combo survives without a new pickup, smash or near miss.
    static let comboWindow = 2.0
    /// Every this-many combo fires Overdrive.
    static let overdriveCombo = 20
    /// Combo needed for each extra x1 on gold (x2 at 10, x3 at 20, x4 at 30).
    static let comboStep = 10
    static let overdriveTime = 4.5
    static let overdriveBoost = 1.55
    /// Clearance under which passing a dangerous rock counts as a near miss.
    static let nearMissGap = 0.55
    static let nearMissFuel = 1.5
    static let fuelCanAmount = 18.0
    /// Treasure that will not fit is burned for this much fuel instead.
    static let overflowFuel = 0.3
    /// Fuel handed back for beating a boss.
    static let bossRefuel = 12.0
    /// Critter spawn chance per band: base + per unit of difficulty.
    static let enemyChance = (base: 0.2, depth: 0.4)
    /// Every critter moves this much faster than its tuned base speed.
    static let enemySpeed = 1.15
    /// Worms notice the drill inside this range and give chase.
    static let wormSight = 6.5
    static let wormTurnRate = 2.6
    static let enemyStun = 0.9
    /// Boss intro: real seconds for a full boss and a mini, and how fast the
    /// world runs meanwhile.
    static let bossIntroTime = (full: 2.6, mini: 1.5)
    static let bossIntroSlowMo = 0.3
    static let jellyShockRadius = 2.0
    static let anglerStrike = 3.0
    static let batSight = 5.0
    static let batDiveBoost = 2.0
    static let spitterRange = 8.0
    static let shotSpeed = 5.5

    // MARK: - Run setup

    /// Starts as the permanent rig; run perks can raise it.
    var loadout: Loadout
    let levels: UpgradeLevels
    let skin: DrillSkin
    let gear: Gear
    var build: ShipBuild { gear.build }
    /// Parts already owned, so a boss drop is only announced the first time.
    let ownedParts: Set<ShipPart>
    /// Bosses beaten in earlier runs; they come back as minis.
    let bossesBeaten: Set<BossKind>
    /// Field Guide pages the player already has, so first sightings get a popup.
    let knownBestiary: Set<String>
    private(set) var bestiarySeen: Set<String> = []
    private(set) var bestiaryKills: [String: Int] = [:]
    let isDaily: Bool
    let previousBest: Double
    let doubleGold: Bool

    var reduceMotion = false
    /// From Settings: scales the turn rate.
    var steerSensitivity = 1.0
    /// From Settings: 0 turns screen shake off. Read by the renderer only.
    var shakeScale = 1.0
    var onEnd: ((RunResult) -> Void)?
    /// The view cannot observe this class, so every phase change has to be
    /// pushed out. Without this the run can stop with no overlay on screen.
    var onPhaseChange: ((RunPhase) -> Void)?

    // MARK: - Drill state

    private(set) var phase: RunPhase = .ready {
        didSet { if phase != oldValue { onPhaseChange?(phase) } }
    }
    func setPhase(_ newPhase: RunPhase) { phase = newPhase }
    var depth = 0.0
    var maxDepth = 0.0
    var camera = 0.0
    var x = GameWorld.shaftWidth / 2
    var vx = 0.0
    var vy = 0.0
    var fuel: Double
    var armor: Int
    var spin = 0.0
    var tilt = 0.0
    /// Direction the bit points. 0 is straight down; direction is (-sin, cos).
    var heading = 0.0
    var headingVector: CGPoint { CGPoint(x: -sin(heading), y: cos(heading)) }
    var bitPoint: CGPoint {
        CGPoint(x: x + headingVector.x * Self.bitOffset, y: depth + headingVector.y * Self.bitOffset)
    }

    /// Weightless gold: bounties, chests, trails, bosses. Never limited by the hold.
    var coins = 0
    var bankedValue = 0
    var gemCount = 0
    var slotsUsed = 0
    /// What is in the hold, so better treasure can push out the worst of it.
    private var cargo: [(value: Int, slots: Int)] = []
    /// What the hold would sell for right now.
    var cargoValue: Int { cargo.reduce(0) { $0 + $1.value } }
    var oreCount: Int { cargo.count }
    /// Everything the run is worth so far.
    var collectedValue: Int { coins + cargoValue }
    var cargoSwaps = 0
    var chambersOpened = 0
    var enemiesDefeated = 0
    var bossesDefeated = 0
    var bossKindsDefeated: [BossKind] = []
    /// Counts down to the next Crystal Core shard.
    var coreCooldown = 1.0
    /// Seconds charged toward the Shield Module's next block.
    var shieldCharge = 0.0
    var shieldReady: Bool { gear.shieldRecharge > 0 && shieldCharge >= gear.shieldRecharge }

    // MARK: - Perks and bosses (see Perks.swift, Bosses.swift)

    var perkStacks: [Perk: Int] = [:]
    var perkOffer: [Perk] = []
    var perkRNG: SeededRandom
    var nextPerkDepth = GameWorld.firstPerkDepth
    /// Counts down to the perk offer that follows a boss kill.
    var pendingPerkDelay = 0.0
    var secondWindsUsed = 0
    var boss: Boss?
    var bossIndex = 0
    /// Seconds (real time) left of the boss intro, and how long it lasts.
    var bossIntro = 0.0
    var bossIntroLength = 0.0
    /// 0→1→0 over the intro: in for the first 15%, out over the last 15%.
    var bossIntroIntensity: Double {
        guard bossIntro > 0, bossIntroLength > 0 else { return 0 }
        let t = 1 - bossIntro / bossIntroLength
        return min(1, t / 0.15, (1 - t) / 0.15)
    }
    var cargoOverflowed = false
    var refillUsed = false

    // MARK: - Combo and Overdrive

    var combo = 0
    var bestCombo = 0
    /// Seconds left before the combo drops. Frozen during Overdrive.
    var comboTimer = 0.0
    /// Seconds of Overdrive left: faster, shatters everything, burns no fuel.
    var overdrive = 0.0
    /// Combo count the current Overdrive charge started from. Moves up when
    /// an Overdrive ends, so combo earned *during* one never chains into the
    /// next — otherwise smashing everything kept it running forever.
    private var overdriveBase = 0

    // MARK: - Input

    var isHolding = false
    /// Joystick direction from the drag gesture (screen axes, y down). Its
    /// length (0...1) is how hard the stick is pushed and scales the turn
    /// rate. Nil while the finger rests, which keeps the current heading.
    var steerVector: CGVector?

    // MARK: - Feel

    var shake = 0.0
    var damageFlash = 0.0
    var treasureFlash = 0.0
    var cargoFullNotice = 0.0
    var recordPulse = 0.0
    var crackSeed: UInt64 = 1
    var stun = 0.0
    private var bore = 0.0
    var invuln = 0.0
    private var coast = 0.0

    // MARK: - World contents

    var obstacles: [Obstacle] = []
    var pickups: [Pickup] = []
    var chambers: [Chamber] = []
    var enemies: [Enemy] = []
    var shots: [Shot] = []
    var lavaPools: [LavaPool] = []

    // MARK: - Events (see Events.swift)

    var event: RunEvent?
    var eventRNG: SeededRandom
    var nextEventDepth: Double
    var decor: [Decor] = []
    var particles: [Particle] = []
    var flying: [FlyingValue] = []
    var shouts: [Shout] = []
    var popups: [Popup] = []
    /// Centre line of the hole dug so far, newest last.
    var trail: [CGPoint] = []

    var goldAnchor = CGPoint(x: 60, y: 40)
    var cargoAnchor = CGPoint(x: 300, y: 90)
    var viewportSize = CGSize(width: 390, height: 844)
    /// Canvas frame in global coordinates, used to convert HUD positions into
    /// the canvas space that `flying` draws in.
    var canvasFrame = CGRect(x: 0, y: 0, width: 390, height: 844)
    var viewHeightMeters: Double {
        Double(viewportSize.height / max(viewportSize.width, 1)) * Self.shaftWidth
    }

    // MARK: - Internals

    /// Terrain only. Effects draw from `fx` so the shaft stays identical
    /// however the player drills it — the daily challenge depends on that.
    private var rng: SeededRandom
    var fx: SeededRandom
    private var nextID = 1
    private var generatedTo = 0.0
    private var dustCooldown = 0.0
    private var smokeCooldown = 0.0
    private var lastTime: TimeInterval?
    private var accumulator = 0.0
    private var endReason: RunEndReason = .outOfFuel
    private var recordAnnounced = false
    private(set) var clock = 0.0
    /// Fraction of the screen above the drill; slides down when heading up so
    /// the player can see where they are going.
    private var anchor = GameWorld.cameraAnchor

    init(loadout: Loadout,
         levels: UpgradeLevels,
         skin: DrillSkin,
         gear: Gear = .standard,
         ownedParts: Set<ShipPart> = [],
         bossesBeaten: Set<BossKind> = [],
         knownBestiary: Set<String> = [],
         previousBest: Double,
         doubleGold: Bool,
         isDaily: Bool,
         seed: UInt64) {
        self.loadout = loadout
        self.levels = levels
        self.skin = skin
        self.gear = gear
        self.shieldCharge = gear.shieldRecharge   // starts the run charged
        self.ownedParts = ownedParts
        self.bossesBeaten = bossesBeaten
        self.knownBestiary = knownBestiary
        self.previousBest = previousBest
        self.doubleGold = doubleGold
        self.isDaily = isDaily
        self.fuel = loadout.fuelCapacity
        self.armor = loadout.armor
        self.rng = SeededRandom(seed: seed)
        self.fx = SeededRandom(seed: seed ^ 0x9E37_79B9_7F4A_7C15)
        self.perkRNG = SeededRandom(seed: seed ^ 0xBEEF_CAFE_F00D)
        var events = SeededRandom(seed: seed ^ 0xE7E7_0000_1234)
        self.nextEventDepth = Self.firstEventDepth + events.double(0...30)
        self.eventRNG = events
        self.crackSeed = seed ^ 0xA5A5
        self.camera = -Self.shaftWidth * 0.4
        placeChamber()
        trail = [CGPoint(x: x, y: -2), CGPoint(x: x, y: 0)]
    }

    func claimID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    // MARK: - Derived

    var fuelFraction: Double { max(0, min(1, fuel / loadout.fuelCapacity)) }
    var armorFraction: Double { max(0, min(1, Double(armor) / Double(loadout.armor))) }
    var cargoFraction: Double { min(1, Double(slotsUsed) / Double(loadout.cargoSlots)) }
    var cargoFull: Bool { slotsUsed >= loadout.cargoSlots }
    var currentLayer: StrataLayer { Strata.layer(for: max(0, depth)) }
    var isEngaged: Bool { isHolding && stun <= 0 && fuel > 0 && phase == .drilling }
    var showsBestLine: Bool { previousBest > 5 && abs(previousBest - depth) < 55 }
    var inOverdrive: Bool { overdrive > 0 }
    var comboMultiplier: Int { min(4, 1 + combo / Self.comboStep) }
    var comboFraction: Double { inOverdrive ? 1 : max(0, comboTimer / comboWindowNow) }
    /// Progress toward the next Overdrive, or what is left of the current one.
    var overdriveCharge: Double {
        inOverdrive
            ? overdrive / overdriveTimeNow
            : min(1, Double(combo - overdriveBase) / Double(overdriveComboNow))
    }
    private var speedRamp: Double { min(1, max(0, depth) / Self.speedRampDepth) }
    var descentTarget: Double {
        (Self.descentSpeed + (Self.topSpeed - Self.descentSpeed) * speedRamp)
            * (inOverdrive ? Self.overdriveBoost : 1)
            * gear.speedFactor
    }

    // MARK: - Lifecycle

    func beginIfNeeded() {
        if phase == .ready { phase = .drilling }
    }

    func setCanvasFrame(_ frame: CGRect) {
        guard frame.width > 1, frame.height > 1 else { return }
        canvasFrame = frame
        viewportSize = frame.size
    }

    /// Converts a global-space HUD rect into the canvas-local anchor coins fly to.
    func setCargoAnchor(globalFrame frame: CGRect) {
        cargoAnchor = CGPoint(x: frame.midX - canvasFrame.minX, y: frame.midY - canvasFrame.minY)
    }

    func setGoldAnchor(globalFrame frame: CGRect) {
        goldAnchor = CGPoint(x: frame.midX - canvasFrame.minX,
                             y: frame.midY - canvasFrame.minY)
    }

    /// Consume the one rewarded refill and resume the run.
    func refuelAndResume() {
        guard phase == .stalled, !refillUsed else { return }
        refillUsed = true
        fuel = loadout.fuelCapacity
        if armor <= 0 { armor = 1 }
        coast = 0
        phase = .drilling
        shout("REFUELLED", tint: Palette.mint)
        burstParticles(count: reduceMotion ? 8 : 22, kind: .spark, color: Palette.mint,
                       at: CGPoint(x: x, y: depth), speed: 5)
    }

    func confirmEnd() {
        guard phase == .stalled || phase == .drilling else { return }
        finish()
    }

    // MARK: - Clock

    func tick(_ now: TimeInterval) {
        guard let previous = lastTime else { lastTime = now; return }
        lastTime = now
        let raw = min(max(now - previous, 0), 0.25)
        accumulator += raw
        let step = 1.0 / 120.0
        var steps = 0
        while accumulator >= step && steps < 16 {
            advance(step)
            accumulator -= step
            steps += 1
        }
        if steps == 16 { accumulator = 0 }
    }

    // MARK: - Simulation

    private func advance(_ step: Double) {
        // Boss intro: the world runs in slow motion while the banner plays.
        var dt = step
        if bossIntro > 0 {
            bossIntro = max(0, bossIntro - step)
            dt *= Self.bossIntroSlowMo
        }
        clock += dt
        decayEffects(dt)
        updateParticles(dt)
        updateFlying(dt)
        updateShouts(dt)
        updatePopups(dt)
        updateChamberAnimation(dt)

        if phase == .drilling {
            // During a boss intro the drill holds still: a beat to take in the
            // boss, and no drifting into it before the fight starts.
            if bossIntro > 0 {
                vx = 0
                vy = 0
            } else {
                stepDrill(dt)
            }
            clampToArena()
            applyMagnet(dt)
            generateTerrain()
            updateTrail()
            resolveObstacles(dt)
            resolvePickups()
            resolveChambers()
            updateLavaPools(dt)
            resolveLava()
            updateEnemies(dt)
            resolveEnemies()
            spawnBossIfNeeded()
            updateBoss(dt)
            updateShots(dt)
            pruneBehind()
            checkEndConditions(dt)
            checkPerkOffer(dt)
            chargeShield(dt)
            updateEvents(dt)
        } else if phase == .stalled {
            // Let the machine settle so the results card does not snap in.
            vx *= max(0, 1 - dt * 6)
            vy *= max(0, 1 - dt * 6)
            x = min(max(x + vx * dt, Self.wallMargin), Self.shaftWidth - Self.wallMargin)
            depth = max(0, depth + vy * dt)
        }

        if phase == .drilling {
            let wanted = 0.5 - (0.5 - Self.cameraAnchor) * cos(heading)
            anchor += (wanted - anchor) * min(1, dt * 2.5)
        }
        var target = depth - viewHeightMeters * anchor
        if bossIntro > 0, let boss {
            // Intro framing: pan so the boss sits in the upper-middle, clear of
            // the name banner along the bottom, while keeping the drill on screen.
            target = boss.y - viewHeightMeters * 0.42
            target = min(max(target, depth - viewHeightMeters * 0.7), depth - viewHeightMeters * 0.1)
        }
        camera += (target - camera) * min(1, dt * 9)
    }

    private func chargeShield(_ dt: Double) {
        guard gear.shieldRecharge > 0, !shieldReady else { return }
        shieldCharge += dt
        if shieldReady {
            popup("SHIELD UP", at: CGPoint(x: x, y: depth - 0.9), tint: Palette.window)
        }
    }

    private func checkPerkOffer(_ dt: Double) {
        guard phase == .drilling else { return }
        if pendingPerkDelay > 0 {
            pendingPerkDelay -= dt
            if pendingPerkDelay <= 0 { offerPerks() }
            return
        }
        // Never interrupt a boss fight; the offer waits until it is over.
        let fighting = boss.map { $0.engaged && !$0.defeated } ?? false
        if maxDepth >= nextPerkDepth && !fighting {
            nextPerkDepth += Self.perkInterval
            offerPerks()
        }
    }

    /// Power check plus the Diamond Bit perk, which opens geodes.
    func canDrill(_ rock: Obstacle) -> Bool {
        rock.isDrillable(power: loadout.power) || (rock.kind == .geode && stacks(.diamondBit) > 0)
    }

    private func decayEffects(_ dt: Double) {
        stun = max(0, stun - dt)
        bore = max(0, bore - dt)
        invuln = max(0, invuln - dt)
        shake = max(0, shake - dt * 2.6)
        damageFlash = max(0, damageFlash - dt * 2.0)
        treasureFlash = max(0, treasureFlash - dt * 1.4)
        cargoFullNotice = max(0, cargoFullNotice - dt * 0.7)
        recordPulse = max(0, recordPulse - dt * 0.5)
        if phase == .drilling {
            if overdrive > 0 {
                overdrive = max(0, overdrive - dt)
                // A short grace period so Overdrive never ends inside a rock.
                if overdrive == 0 {
                    invuln = max(invuln, 0.8)
                    overdriveBase = combo
                    comboTimer = comboWindowNow
                }
            } else if combo > 0 {
                comboTimer -= dt
                if comboTimer <= 0 { combo = 0; overdriveBase = 0 }
            }
        }
        for i in obstacles.indices {
            obstacles[i].hitFlash = max(0, obstacles[i].hitFlash - dt * 3)
        }
        for i in pickups.indices {
            pickups[i].deniedFlash = max(0, pickups[i].deniedFlash - dt * 2)
        }
    }

    private func stepDrill(_ dt: Double) {
        let engaged = isEngaged

        // Swing toward the joystick direction at a limited turn rate, so
        // reversing takes a visible arc rather than a snap.
        var turning = 0.0
        if let steer = steerVector, isHolding, stun <= 0 {
            let target = atan2(-steer.dx, steer.dy)
            let delta = remainder(target - heading, 2 * .pi)
            // A nudge turns gently; only a full push swings at the top rate.
            let push = min(1, hypot(steer.dx, steer.dy))
            let limit = Self.turnRate * steerSensitivity * gear.turnFactor
                * (0.25 + 0.75 * push) * (inOverdrive ? 1.3 : 1) * dt
            let step = max(-limit, min(limit, delta))
            heading = remainder(heading + step, 2 * .pi)
            turning = step / (Self.turnRate * dt)
        }
        tilt += (turning - tilt) * min(1, dt * 8)

        let speed = engaged ? descentTarget * (bore > 0 && !inOverdrive && !gear.noBore ? 0.4 : 1) : 0
        let direction = headingVector
        let response = min(1, dt * (engaged ? 10 : 14))
        vx += (direction.x * speed - vx) * response
        vy += (direction.y * speed - vy) * response

        if engaged {
            if !inOverdrive { fuel = max(0, fuel - fuelBurnNow * dt) }
            spin += dt * (inOverdrive ? 26 : 16)
            emitDust(dt)
            emitSmoke(dt)
            if inOverdrive { emitOverdriveFlame(dt) }
            fireCrystalCore(dt)
        } else {
            spin += dt * 1.5
        }

        // Turned sideways the bit reaches further, so keep it on screen.
        let margin = Self.wallMargin + abs(sin(heading)) * 0.55
        x = min(max(x + vx * dt, margin), Self.shaftWidth - margin)
        depth += vy * dt
        // The surface is a hard ceiling.
        if depth < 0 { depth = 0; vy = max(0, vy) }
        if depth > maxDepth {
            maxDepth = depth
            if !recordAnnounced, previousBest > 5, maxDepth > previousBest {
                recordAnnounced = true
                recordPulse = 1
                shout("NEW RECORD", tint: Palette.gold)
                Haptics.celebrate()
            }
        }
    }

    private func updateTrail() {
        let last = trail.last ?? CGPoint(x: x, y: depth)
        guard hypot(x - last.x, depth - last.y) > 0.3 else { return }
        trail.append(CGPoint(x: x, y: depth))
        if trail.count > 400 { trail.removeFirst(trail.count - 400) }
    }

    // MARK: - Collisions

    private func drillCircles() -> [(CGPoint, Double)] {
        [(CGPoint(x: x, y: depth), Self.bodyRadius),
         (bitPoint, bitReach)]
    }

    private func resolveObstacles(_ dt: Double) {
        let circles = drillCircles()
        for index in obstacles.indices {
            var rock = obstacles[index]
            guard !rock.destroyed, abs(rock.y - depth) < 4 else { continue }
            checkNearMiss(index)
            guard circles.contains(where: { hits(rock, circle: $0.0, radius: $0.1) }) else { continue }

            if inOverdrive || canDrill(rock) {
                obstacles[index].destroyed = true
                let point = CGPoint(x: rock.x, y: rock.y)
                if inOverdrive {
                    burstParticles(count: reduceMotion ? 8 : 24, kind: .chunk,
                                   color: rock.kind == .geode ? Palette.hazard : Palette.rock(hardness: rock.hardness),
                                   at: point, speed: 9)
                    burstParticles(count: reduceMotion ? 3 : 10, kind: .spark,
                                   color: Palette.drillBody, at: point, speed: 7)
                    popup("SMASH", at: point, tint: Palette.drillBody)
                    if !reduceMotion { shake = max(shake, 0.45) }
                    Haptics.bump()
                } else {
                    bore = 0.22
                    fuel = max(0, fuel - (0.8 + Double(rock.hardness) * 0.5))
                    burstParticles(count: reduceMotion ? 6 : 16, kind: .chunk,
                                   color: Palette.rock(hardness: rock.hardness),
                                   at: point, speed: 6)
                    if !reduceMotion { shake = max(shake, 0.28) }
                    Haptics.tap()
                }
                if gear.smashFuel > 0 { fuel = min(loadout.fuelCapacity, fuel + gear.smashFuel) }
                bumpCombo(at: point)
            } else if invuln <= 0 {
                rock.hitFlash = 1
                obstacles[index] = rock
                takeDamage(from: rock)
            }
        }
    }

    /// Threading past a rock that would have hurt is worth a little fuel and
    /// keeps the combo alive — the reward for steering close instead of wide.
    /// Works in any direction: the rock is armed when the hull skims inside
    /// `nearMissGap`, and pays out once the drill pulls clear without a hit.
    private func checkNearMiss(_ index: Int) {
        let rock = obstacles[index]
        guard !rock.passed, !canDrill(rock) else { return }
        let gap = clearance(from: rock)
        if gap < Self.nearMissGap {
            obstacles[index].skimmed = true
            return
        }
        guard rock.skimmed, gap > Self.nearMissGap + 0.35 else { return }
        obstacles[index].passed = true
        guard !inOverdrive, invuln <= 0 else { return }
        fuel = min(loadout.fuelCapacity, fuel + Self.nearMissFuel)
        burstParticles(count: reduceMotion ? 3 : 9, kind: .spark, color: Palette.textPrimary,
                       at: CGPoint(x: x, y: depth), speed: 4)
        popup("CLOSE!", at: CGPoint(x: x, y: depth - 0.6), tint: Palette.window)
        Haptics.tap()
        bumpCombo(at: CGPoint(x: x, y: depth))
    }

    /// Distance from the hull to the rock's surface.
    private func clearance(from rock: Obstacle) -> Double {
        switch rock.kind {
        case .slab:
            let dx = max(0, abs(rock.x - x) - rock.w / 2)
            let dy = max(0, abs(rock.y - depth) - rock.h / 2)
            return hypot(dx, dy) - Self.bodyRadius
        case .boulder, .geode:
            return hypot(rock.x - x, rock.y - depth) - rock.w * 0.42 - Self.bodyRadius
        }
    }

    private func hits(_ rock: Obstacle, circle: CGPoint, radius: Double) -> Bool {
        switch rock.kind {
        case .slab:
            // Axis-aligned box is close enough and reads fairly to the player.
            let box = rock.bounds.insetBy(dx: -radius * 0.78, dy: -radius * 0.78)
            return box.contains(circle)
        case .boulder, .geode:
            let reach = rock.w * 0.42 + radius
            let dx = rock.x - circle.x
            let dy = rock.y - circle.y
            return dx * dx + dy * dy < reach * reach
        }
    }

    private func takeDamage(from rock: Obstacle) {
        // Mark it passed so bouncing clear of it is not scored as a near miss.
        if let index = obstacles.firstIndex(where: { $0.id == rock.id }) { obstacles[index].passed = true }
        var away = CGPoint(x: x - rock.x, y: depth - rock.y)
        if rock.kind == .slab {
            // Push out along the slab's short axis unless we hit an end.
            away = abs(x - rock.x) > rock.w / 2 ? CGPoint(x: x - rock.x, y: 0) : CGPoint(x: 0, y: depth - rock.y)
        }
        hurt(amount: rock.kind.damage, away: away,
             chunk: rock.kind == .geode ? Palette.hazard : Palette.rock(hardness: 3),
             at: CGPoint(x: rock.x, y: rock.y))
        if gear.noStun { stun = 0 }
    }

    func hurt(amount: Int, away: CGPoint, chunk: Color, at point: CGPoint) {
        // Shield Module eats the hit outright.
        if shieldReady {
            shieldCharge = 0
            invuln = max(invuln, 0.8)
            popup("BLOCKED", at: CGPoint(x: x, y: depth - 0.9), tint: Palette.window, big: true)
            burstParticles(count: reduceMotion ? 6 : 18, kind: .spark, color: Palette.window,
                           at: CGPoint(x: x, y: depth), speed: 6)
            let length = max(0.01, hypot(away.x, away.y))
            vx = away.x / length * 3
            vy = away.y / length * 3
            Haptics.bump()
            return
        }
        armor -= amount + gear.extraDamage
        if armor <= 0, secondWindsUsed < stacks(.secondWind) {
            secondWindsUsed += 1
            armor = 1
            invuln = 2.5
            shout("SECOND WIND", tint: Palette.hazard)
            Haptics.celebrate()
        }
        if combo >= Self.comboStep {
            popup("COMBO LOST", at: CGPoint(x: x, y: depth - 0.9), tint: Palette.hazard)
        }
        combo = 0
        overdriveBase = 0
        comboTimer = 0
        invuln = max(invuln, 1.1)
        stun = 0.32
        fuel = max(0, fuel - 2.5)
        damageFlash = 1
        crackSeed = crackSeed &* 6364136223846793005 &+ 1442695040888963407
        if !reduceMotion { shake = 1 }
        // Knock the drill clear, otherwise a held finger pins it against the
        // obstacle and drains armour in one spot.
        let length = max(0.001, hypot(away.x, away.y))
        let normal = length < 0.01 ? CGPoint(x: -headingVector.x, y: -headingVector.y)
                                   : CGPoint(x: away.x / length, y: away.y / length)
        x = min(max(x + normal.x * 0.55, Self.wallMargin), Self.shaftWidth - Self.wallMargin)
        depth = max(0, depth + normal.y * 0.55)
        vx = normal.x * 3.4
        vy = normal.y * 3.4
        burstParticles(count: reduceMotion ? 8 : 20, kind: .chunk, color: chunk, at: point, speed: 7)
        Haptics.thud()
    }

    private func resolvePickups() {
        let circles = drillCircles()
        for index in pickups.indices {
            guard !pickups[index].collected else { continue }
            let pickup = pickups[index]
            guard abs(pickup.y - depth) < 3 else { continue }
            let reach = 0.58
            let touching = circles.contains { circle, radius in
                let dx = pickup.x - circle.x
                let dy = pickup.y - circle.y
                let limit = reach + radius
                return dx * dx + dy * dy < limit * limit
            }
            guard touching else { continue }
            let point = CGPoint(x: pickup.x, y: pickup.y)

            if pickup.kind == .fuel {
                pickups[index].collected = true
                fuel = min(loadout.fuelCapacity, fuel + Self.fuelCanAmount)
                burstParticles(count: reduceMotion ? 4 : 14, kind: .spark, color: Palette.mint,
                               at: point, speed: 4.5)
                popup("+FUEL", at: point, tint: Palette.mint)
                Haptics.bump()
                bumpCombo(at: point)
            } else if let gain = stow(value: Int(Double(pickup.value * comboMultiplier) * treasureBonus)
                                          * (goldRushActive ? 2 : 1),
                                      slots: pickup.kind.slots) {
                pickups[index].collected = true
                let value = Int(Double(pickup.value * comboMultiplier) * treasureBonus)
                    * (goldRushActive ? 2 : 1)
                if pickup.kind == .gem { gemCount += 1 }
                let ore = Strata.layer(for: max(0, pickup.y)).ore
                launchToCounter(from: point, color: pickup.kind == .gem ? Palette.gem : ore.color,
                                big: pickup.kind == .gem, toCargo: true)
                burstParticles(count: reduceMotion ? 3 : 8, kind: .spark,
                               color: pickup.kind == .gem ? Palette.gem : Palette.gold,
                               at: point, speed: 3.5)
                if gain < value {
                    // Something cheaper got thrown out to make room.
                    popup("SWAP +\(gain)", at: point, tint: Palette.window)
                    burstParticles(count: reduceMotion ? 2 : 6, kind: .chunk, color: Palette.goldShadow,
                                   at: CGPoint(x: x, y: depth), speed: 4)
                } else {
                    popup("+\(value)", at: point,
                          tint: pickup.kind == .gem ? Palette.gem : Strata.layer(for: max(0, pickup.y)).ore.color)
                }
                Haptics.tap()
                bumpCombo(at: point)
                if let trail = pickup.trail { checkTrailSwept(trail, at: point) }
            } else {
                // The hold is full of richer ore: smelt this one for a little
                // fuel so the pickup still feeds the run and the combo.
                pickups[index].collected = true
                cargoOverflowed = true
                cargoFullNotice = 1
                fuel = min(loadout.fuelCapacity, fuel + Self.overflowFuel)
                burstParticles(count: reduceMotion ? 3 : 8, kind: .spark, color: Palette.exhaust,
                               at: point, speed: 3)
                popup("SMELT +FUEL", at: point, tint: Palette.exhaust)
                Haptics.tap()
                bumpCombo(at: point)
            }
        }
    }

    /// Puts treasure in the hold, throwing out the lowest value-per-slot items
    /// if that makes room *and* comes out ahead. Returns the net gold gained,
    /// or nil when the new item is not worth more than what it would replace.
    private func stow(value: Int, slots: Int) -> Int? {
        let free = loadout.cargoSlots - slotsUsed
        if slots <= free {
            cargo.append((value, slots))
            slotsUsed += slots
            return value
        }
        let order = cargo.indices.sorted {
            Double(cargo[$0].value) / Double(cargo[$0].slots) < Double(cargo[$1].value) / Double(cargo[$1].slots)
        }
        var freed = free, lost = 0
        var evict: [Int] = []
        for i in order where freed < slots {
            evict.append(i)
            freed += cargo[i].slots
            lost += cargo[i].value
        }
        guard freed >= slots, lost < value else { return nil }
        for i in evict.sorted(by: >) {
            slotsUsed -= cargo[i].slots
            cargo.remove(at: i)
        }
        cargo.append((value, slots))
        slotsUsed += slots
        cargoSwaps += 1
        return value - lost
    }

    private func checkTrailSwept(_ trail: Int, at point: CGPoint) {
        let members = pickups.filter { $0.trail == trail }
        guard members.count >= 4, members.allSatisfy(\.collected) else { return }
        let bonus = currentLayer.goldValue * 3 * comboMultiplier
        coins += bonus
        treasureFlash = max(treasureFlash, 0.45)
        popup("TRAIL +\(bonus)", at: CGPoint(x: point.x, y: point.y - 0.8), tint: Palette.gold, big: true)
        burstParticles(count: reduceMotion ? 6 : 20, kind: .spark, color: Palette.gold,
                       at: point, speed: 5.5)
        Haptics.celebrate()
    }

    func bumpCombo(at point: CGPoint) {
        let before = comboMultiplier
        combo += 1
        bestCombo = max(bestCombo, combo)
        comboTimer = comboWindowNow
        if comboMultiplier > before {
            popup("x\(comboMultiplier) GOLD", at: CGPoint(x: x, y: depth - 1.4),
                  tint: Palette.drillBody, big: true)
            Haptics.bump()
        }
        if !inOverdrive, combo - overdriveBase >= overdriveComboNow { startOverdrive() }
    }

    private func startOverdrive() {
        overdrive = overdriveTimeNow
        shout("OVERDRIVE!", tint: Palette.drillBody)
        if !reduceMotion { shake = max(shake, 0.6) }
        burstParticles(count: reduceMotion ? 10 : 36, kind: .spark, color: Palette.drillBody,
                       at: CGPoint(x: x, y: depth), speed: 8)
        Haptics.celebrate()
    }

    private func resolveChambers() {
        for index in chambers.indices {
            guard !chambers[index].opened else { continue }
            let chamber = chambers[index]
            let dx = chamber.x - x
            let dy = chamber.y - depth
            guard dx * dx + dy * dy < (chamber.radius * 0.85) * (chamber.radius * 0.85) else { continue }
            chambers[index].opened = true
            chambersOpened += 1

            // A chest ignores the hold limit — it is the reward for going deep.
            coins += chamber.reward
            treasureFlash = 1
            shout("TREASURE  +\(chamber.reward)", tint: Palette.gold)
            for _ in 0..<(reduceMotion ? 4 : 12) {
                launchToCounter(from: CGPoint(x: chamber.x + fx.double(-0.6...0.6),
                                              y: chamber.y + fx.double(-0.6...0.6)),
                                color: Palette.gold)
            }
            burstParticles(count: reduceMotion ? 10 : 34, kind: .spark, color: Palette.gold,
                           at: CGPoint(x: chamber.x, y: chamber.y), speed: 6)
            Haptics.celebrate()
        }
    }

    // MARK: - Enemies

    private func updateEnemies(_ dt: Double) {
        let wake = viewHeightMeters * 0.9
        for index in enemies.indices {
            var enemy = enemies[index]
            guard !enemy.dead else { continue }
            if !enemy.awake {
                guard abs(enemy.y - depth) < wake else { continue }
                enemy.awake = true
                noteSighting(.critter(enemy.kind), at: CGPoint(x: enemy.x, y: enemy.y))
            }
            enemy.hitFlash = max(0, enemy.hitFlash - dt * 3)
            enemy.stun = max(0, enemy.stun - dt)

            switch enemy.kind {
            case .worm: steerWorm(&enemy, dt)
            case .bat: steerBat(&enemy, dt)
            case .beetle: steerBeetle(&enemy, dt)
            case .spitter: steerSpitter(&enemy, dt)
            case .ember: steerEmber(&enemy, dt)
            case .jelly: steerJelly(&enemy, dt)
            case .angler: steerAngler(&enemy, dt)
            case .mole: steerMole(&enemy, dt)
            case .spider: steerSpider(&enemy, dt)
            case .centipede: steerCentipede(&enemy, dt)
            case .slime: steerSlime(&enemy, dt)
            case .slug: steerSlug(&enemy, dt)
            }

            let pace = (enemy.stun > 0 ? 0.35 : 1) * enemy.pace
            let direction = CGPoint(x: -sin(enemy.heading), y: cos(enemy.heading))
            enemy.x += direction.x * enemy.speed * pace * dt
            enemy.y += direction.y * enemy.speed * pace * dt
            // Walls turn them round rather than letting them leave the shaft.
            let low = Self.wallMargin * 0.6, high = Self.shaftWidth - Self.wallMargin * 0.6
            if enemy.x < low || enemy.x > high {
                enemy.x = min(max(enemy.x, low), high)
                enemy.heading = -enemy.heading
            }

            if enemy.kind == .worm || enemy.kind == .centipede {
                // Rope-follow: each segment hangs a fixed distance behind the last.
                let spacing = enemy.kind == .centipede ? 0.3 : 0.3
                var lead = CGPoint(x: enemy.x, y: enemy.y)
                for k in enemy.segments.indices {
                    let dx = enemy.segments[k].x - lead.x
                    let dy = enemy.segments[k].y - lead.y
                    let length = hypot(dx, dy)
                    if length > spacing {
                        enemy.segments[k] = CGPoint(x: lead.x + dx / length * spacing,
                                                    y: lead.y + dy / length * spacing)
                    }
                    lead = enemy.segments[k]
                }
            }
            enemies[index] = enemy
        }
    }

    private func steerWorm(_ worm: inout Enemy, _ dt: Double) {
        let dx = x - worm.x, dy = depth - worm.y
        let sees = hypot(dx, dy) < Self.wormSight
        if sees && !worm.chasing && worm.stun <= 0 {
            popup("!", at: CGPoint(x: worm.x, y: worm.y - 0.6), tint: Palette.hazard, big: true)
        }
        worm.chasing = sees
        let target: Double
        if sees {
            target = atan2(-dx, dy)
        } else {
            // Wander across the shaft in a lazy S, drifting back to its row.
            let across: Double = sin(worm.heading) < 0 ? -.pi / 2 : .pi / 2
            let drift = max(-0.6, min(0.6, (worm.y - worm.homeY) * 0.3))
            target = across + (across > 0 ? -drift : drift) + sin(clock * 2.2 + worm.phase) * 0.5
        }
        let delta = remainder(target - worm.heading, 2 * .pi)
        let limit = Self.wormTurnRate * dt
        worm.heading = remainder(worm.heading + max(-limit, min(limit, delta)), 2 * .pi)
    }

    /// Bobs along its row; when the drill comes close it freezes, shakes for
    /// a beat (the tell), then dives in a straight line and flies back home.
    private func steerBat(_ bat: inout Enemy, _ dt: Double) {
        bat.timer -= dt
        let dx = x - bat.x, dy = depth - bat.y
        switch bat.mode {
        case .patrol:
            bat.pace = 1
            let across: Double = sin(bat.heading) < 0 ? -.pi / 2 : .pi / 2
            let bob = sin(clock * 3 + bat.phase) * 0.6
            let drift = max(-0.5, min(0.5, (bat.y - bat.homeY) * 0.4))
            bat.heading = across + (across > 0 ? -drift - bob : drift + bob)
            if bat.timer <= 0, bat.stun <= 0, hypot(dx, dy) < Self.batSight {
                bat.mode = .windup
                bat.timer = 0.5
                popup("!", at: CGPoint(x: bat.x, y: bat.y - 0.6), tint: Palette.hazard, big: true)
            }
        case .windup:
            bat.pace = 0.05
            bat.chasing = true
            if bat.timer <= 0 {
                bat.mode = .attack
                bat.timer = 0.75
                bat.heading = atan2(-dx, dy)   // committed: it does not track
            }
        case .attack:
            bat.pace = Self.batDiveBoost
            if bat.timer <= 0 {
                bat.mode = .recover
                bat.timer = 1.6
                bat.chasing = false
            }
        case .recover:
            bat.pace = 0.8
            bat.heading = atan2(0.0, bat.homeY - bat.y)
            if abs(bat.y - bat.homeY) < 0.4 || bat.timer <= 0 {
                bat.mode = .patrol
                bat.timer = 1.4      // cooldown before the next dive
                bat.heading = sin(bat.phase) < 0 ? -.pi / 2 : .pi / 2
            }
        }
    }

    /// Crawls its row and, in range, roots itself, glows, then fires a shard
    /// at where the drill is now.
    private func steerSpitter(_ spitter: inout Enemy, _ dt: Double) {
        spitter.timer -= dt
        let dx = x - spitter.x, dy = depth - spitter.y
        let across: Double = sin(spitter.heading) < 0 ? -.pi / 2 : .pi / 2
        switch spitter.mode {
        case .windup:
            spitter.pace = 0
            spitter.chasing = true
            if spitter.timer <= 0 {
                let length = max(0.01, hypot(dx, dy))
                shots.append(Shot(id: claimID(), x: spitter.x, y: spitter.y,
                                  vx: dx / length * Self.shotSpeed, vy: dy / length * Self.shotSpeed,
                                  life: 3))
                burstParticles(count: reduceMotion ? 2 : 6, kind: .spark, color: Palette.spitter,
                               at: CGPoint(x: spitter.x, y: spitter.y), speed: 3)
                spitter.mode = .patrol
                spitter.chasing = false
                spitter.timer = max(1.4, 2.4 - 0.8 * min(1, max(0, spitter.y - 330) / 200))
            }
        default:
            spitter.pace = 1
            spitter.heading = across - (across > 0 ? 1 : -1) * max(-0.3, min(0.3, (spitter.y - spitter.homeY) * 0.5))
            if spitter.timer <= 0, spitter.stun <= 0, hypot(dx, dy) < Self.spitterRange {
                spitter.mode = .windup
                spitter.timer = 0.55
            }
        }
    }

    /// Drifts toward the drill in a wobble; close in, it swells for a beat and
    /// bursts. Pop it with the bit first and it is just gold.
    private func steerEmber(_ ember: inout Enemy, _ dt: Double) {
        let dx = x - ember.x, dy = depth - ember.y
        let distance = hypot(dx, dy)
        switch ember.mode {
        case .windup:
            ember.pace = 0
            ember.timer -= dt
            if ember.timer <= 0 {
                ember.dead = true
                let point = CGPoint(x: ember.x, y: ember.y)
                burstParticles(count: reduceMotion ? 8 : 26, kind: .spark, color: Palette.ember, at: point, speed: 8)
                burstParticles(count: reduceMotion ? 3 : 10, kind: .smoke, color: Palette.lava, at: point, speed: 3)
                if !reduceMotion { shake = max(shake, 0.5) }
                if distance < 1.8, invuln <= 0, !inOverdrive {
                    hurt(amount: 1, away: CGPoint(x: dx, y: dy), chunk: Palette.ember, at: point)
                }
            }
        default:
            ember.pace = 1
            ember.chasing = distance < 7
            let target = ember.chasing
                ? atan2(-dx, dy) + sin(clock * 4 + ember.phase) * 0.5
                : (sin(ember.heading) < 0 ? -.pi / 2 : .pi / 2) + sin(clock * 2 + ember.phase) * 0.6
            let delta = remainder(target - ember.heading, 2 * .pi)
            ember.heading = remainder(ember.heading + max(-3 * dt, min(3 * dt, delta)), 2 * .pi)
            if distance < 1.6 && ember.stun <= 0 {
                ember.mode = .windup
                ember.timer = 0.6
            }
        }
    }

    /// Boss-made pools warm up, then expire.
    private func updateLavaPools(_ dt: Double) {
        guard lavaPools.contains(where: { $0.life != nil }) else { return }
        for index in lavaPools.indices where lavaPools[index].life != nil {
            lavaPools[index].warmup = max(0, lavaPools[index].warmup - dt)
            lavaPools[index].life! -= dt
        }
        lavaPools.removeAll { ($0.life ?? 1) <= 0 }
    }

    /// Bobs toward the drill. Close in, it glows and crackles for a beat, then
    /// shocks everything around it. Pop it with the bit before it goes off.
    private func steerJelly(_ jelly: inout Enemy, _ dt: Double) {
        let dx = x - jelly.x, dy = depth - jelly.y
        let distance = hypot(dx, dy)
        jelly.timer -= dt
        switch jelly.mode {
        case .windup:
            jelly.pace = 0.1
            if jelly.timer <= 0 {
                burstParticles(count: reduceMotion ? 6 : 18, kind: .spark, color: Palette.jelly,
                               at: CGPoint(x: jelly.x, y: jelly.y), speed: 7)
                if distance < Self.jellyShockRadius, invuln <= 0, !inOverdrive {
                    hurt(amount: 1, away: CGPoint(x: dx, y: dy), chunk: Palette.jelly, at: CGPoint(x: x, y: depth))
                }
                jelly.mode = .recover
                jelly.timer = 2.4
                jelly.chasing = false
            }
        case .recover:
            jelly.pace = 0.4
            if jelly.timer <= 0 { jelly.mode = .patrol }
        default:
            jelly.pace = 1
            jelly.chasing = distance < 6
            // Pulsing swim: speed rises and falls with each bell beat.
            let beat = 0.5 + 0.5 * sin(clock * 3 + jelly.phase)
            jelly.pace = 0.4 + beat
            let target = jelly.chasing ? atan2(-dx, dy) : .pi + sin(clock * 0.6 + jelly.phase) * 0.8
            let delta = remainder(target - jelly.heading, 2 * .pi)
            jelly.heading = remainder(jelly.heading + max(-1.6 * dt, min(1.6 * dt, delta)), 2 * .pi)
            if jelly.chasing, distance < 2.6, jelly.timer <= 0 {
                jelly.mode = .windup
                jelly.timer = 0.8
            }
        }
    }

    /// Sits still in the dark with its lure glowing like a pearl. When the
    /// drill comes close, it lunges.
    private func steerAngler(_ angler: inout Enemy, _ dt: Double) {
        let dx = x - angler.x, dy = depth - angler.y
        let distance = hypot(dx, dy)
        angler.timer -= dt
        switch angler.mode {
        case .windup:
            angler.pace = 0
            angler.heading = atan2(-dx, dy)
            if angler.timer <= 0 { angler.mode = .attack; angler.timer = 0.6 }
        case .attack:
            angler.pace = 3.2
            if angler.timer <= 0 { angler.mode = .recover; angler.timer = 1.6; angler.chasing = false }
        case .recover:
            angler.pace = 0.25
            if angler.timer <= 0 { angler.mode = .patrol }
        default:
            angler.pace = 0.15
            angler.heading += sin(clock * 0.5 + angler.phase) * 0.3 * dt
            if distance < Self.anglerStrike {
                angler.mode = .windup
                angler.timer = 0.35
                angler.chasing = true
                popup("!", at: CGPoint(x: angler.x, y: angler.y - 0.7), tint: Palette.hazard, big: true)
            }
        }
    }

    /// Records a Field Guide sighting; the first ever gets a popup.
    func noteSighting(_ subject: BestiaryEntry.Subject, at point: CGPoint) {
        let key = BestiaryEntry.key(subject)
        guard bestiarySeen.insert(key).inserted, !knownBestiary.contains(key) else { return }
        let name = BestiaryEntry.all.first { $0.id == key }?.name.uppercased() ?? "?"
        popup("NEW ENTRY: \(name)", at: CGPoint(x: point.x, y: point.y - 1), tint: Palette.paper, big: true)
    }

    func noteBossKill(_ kind: BossKind) {
        bestiaryKills[BestiaryEntry.key(.boss(kind)), default: 0] += 1
    }

    // MARK: New critters

    /// Underground (untouchable, shown as a moving mound) until close; then
    /// it shakes, pops up and lunges, and lingers above ground before diving.
    private func steerMole(_ mole: inout Enemy, _ dt: Double) {
        let dx = x - mole.x, dy = depth - mole.y
        let distance = hypot(dx, dy)
        mole.timer -= dt
        switch mole.mode {
        case .windup:
            mole.pace = 0
            if mole.timer <= 0 {
                mole.mode = .attack
                mole.timer = 0.45
                mole.heading = atan2(-dx, dy)
                burstParticles(count: reduceMotion ? 4 : 12, kind: .chunk, color: currentLayer.pebble,
                               at: CGPoint(x: mole.x, y: mole.y), speed: 5)
            }
        case .attack:
            mole.pace = 2.6
            if mole.timer <= 0 { mole.mode = .recover; mole.timer = 1.3 }
        case .recover:
            mole.pace = 0
            if mole.timer <= 0 { mole.mode = .patrol; mole.timer = 2 }
        default:
            mole.pace = 1
            let target = distance < 7 ? atan2(-dx, dy) : (sin(mole.heading) < 0 ? -.pi / 2 : .pi / 2)
            let delta = remainder(target - mole.heading, 2 * .pi)
            mole.heading = remainder(mole.heading + max(-2.5 * dt, min(2.5 * dt, delta)), 2 * .pi)
            if distance < 1.9, mole.timer <= 0 {
                mole.mode = .windup
                mole.timer = 0.5
                popup("!", at: CGPoint(x: mole.x, y: mole.y - 0.6), tint: Palette.hazard, big: true)
            }
        }
    }

    /// Hangs on silk below its anchor (`homeY`). When the drill passes under
    /// it, it drops fast, then climbs back up.
    private func steerSpider(_ spider: inout Enemy, _ dt: Double) {
        let dx = x - spider.x
        spider.timer -= dt
        // Drift slowly toward the drill's column.
        spider.x += max(-1, min(1, dx)) * 0.6 * dt
        switch spider.mode {
        case .attack:
            spider.heading = 0
            spider.pace = 2.6
            if spider.y > spider.homeY + 5 || spider.y > depth + 0.6 || spider.timer <= 0 {
                spider.mode = .recover
                spider.timer = 2
            }
        case .recover:
            spider.heading = .pi
            spider.pace = 0.5
            if spider.y <= spider.homeY + 0.8 { spider.mode = .patrol; spider.timer = 1.2 }
        default:
            spider.heading = sin(clock * 1.5 + spider.phase) > 0 ? 0 : .pi
            spider.pace = 0.08
            let below = depth - spider.y
            if abs(dx) < 1.4, below > 0, below < 5.5, spider.timer <= 0 {
                spider.mode = .attack
                spider.timer = 1.2
                spider.chasing = true
            }
        }
    }

    /// Fast zig-zag across the shaft; it never chases, it just gets in the way.
    private func steerCentipede(_ centipede: inout Enemy, _ dt: Double) {
        let across: Double = sin(centipede.heading) < 0 ? -.pi / 2 : .pi / 2
        let weave = sin(clock * 3 + centipede.phase) * 0.7
        let drift = max(-0.5, min(0.5, (centipede.y - centipede.homeY) * 0.4))
        centipede.heading = across + (across > 0 ? -drift : drift) + weave
        centipede.pace = 1
    }

    /// Hops toward the drill in bursts; between hops it sits still.
    private func steerSlime(_ slime: inout Enemy, _ dt: Double) {
        let dx = x - slime.x, dy = depth - slime.y
        let hop = max(0, sin(clock * 4 + slime.phase))
        slime.pace = hop * 2
        if hop < 0.05 {
            slime.heading = hypot(dx, dy) < 7 ? atan2(-dx, dy) : slime.heading + 0.6
        }
    }

    /// Crawls its row and leaves lava behind it (Heat Shield shrugs it off).
    private func steerSlug(_ slug: inout Enemy, _ dt: Double) {
        let across: Double = sin(slug.heading) < 0 ? -.pi / 2 : .pi / 2
        let drift = max(-0.3, min(0.3, (slug.y - slug.homeY) * 0.5))
        slug.heading = across + (across > 0 ? -drift : drift)
        slug.pace = 1
        slug.timer -= dt
        if slug.timer <= 0 {
            slug.timer = 1.1
            let back = CGPoint(x: slug.x + sin(slug.heading) * 0.5, y: slug.y)
            lavaPools.append(LavaPool(id: claimID(), x: back.x, y: back.y, radius: 0.5,
                                      seed: UInt64(claimID()) | 1, life: 3.4, warmup: 0.35))
        }
    }

    /// Lava burns on contact unless the hull is lava-proof.
    private func resolveLava() {
        guard invuln <= 0, !inOverdrive, !gear.lavaImmune else { return }
        for pool in lavaPools where pool.warmup <= 0 && abs(pool.y - depth) < pool.radius + 1 {
            let dx = x - pool.x, dy = depth - pool.y
            if hypot(dx, dy) < pool.radius * 0.85 + Self.bodyRadius * 0.4 {
                popup("BURN!", at: CGPoint(x: x, y: depth - 0.8), tint: Palette.lava)
                hurt(amount: 1, away: CGPoint(x: dx, y: dy), chunk: Palette.lava, at: CGPoint(x: x, y: depth))
                return
            }
        }
    }

    private func updateShots(_ dt: Double) {
        let bit = bitPoint
        for index in shots.indices {
            shots[index].x += shots[index].vx * dt
            shots[index].y += shots[index].vy * dt
            shots[index].life -= dt
            if shots[index].style == .homing {
                // Turn toward the drill at a limited rate, constant speed.
                let speed = hypot(shots[index].vx, shots[index].vy)
                let current = atan2(shots[index].vy, shots[index].vx)
                let wanted = atan2(depth - shots[index].y, x - shots[index].x)
                let delta = remainder(wanted - current, 2 * .pi)
                let heading = current + max(-2.2 * dt, min(2.2 * dt, delta))
                let pace = min(4.6, speed + 3 * dt)
                shots[index].vx = cos(heading) * pace
                shots[index].vy = sin(heading) * pace
            }
            let shot = shots[index]
            let point = CGPoint(x: shot.x, y: shot.y)
            if shot.friendly {
                resolveFriendlyShot(index)
                continue
            }
            if shot.style == .boulder {
                if hypot(shot.x - bit.x, shot.y - bit.y) < bitReach + 0.45 || inOverdrive && hypot(shot.x - x, shot.y - depth) < 1.2 {
                    shots[index].life = 0
                    burstParticles(count: reduceMotion ? 4 : 12, kind: .chunk, color: Palette.rock(hardness: 2),
                                   at: point, speed: 6)
                    popup("SMASH", at: point, tint: Palette.drillBody)
                    Haptics.tap()
                    bumpCombo(at: point)
                } else if hypot(shot.x - x, shot.y - depth) < Self.bodyRadius + 0.4 {
                    shots[index].life = 0
                    if invuln <= 0 {
                        hurt(amount: 1, away: CGPoint(x: x - shot.x, y: 1), chunk: Palette.rock(hardness: 2), at: point)
                    }
                }
                continue
            }
            if hypot(shot.x - bit.x, shot.y - bit.y) < bitReach + 0.3 {
                // Parried with the bit.
                shots[index].life = 0
                burstParticles(count: reduceMotion ? 3 : 10, kind: .spark, color: Palette.spitter,
                               at: point, speed: 5)
                popup("BLOCK", at: point, tint: Palette.window)
                Haptics.tap()
                bumpCombo(at: point)
            } else if hypot(shot.x - x, shot.y - depth) < Self.bodyRadius + 0.2 {
                shots[index].life = 0
                if invuln <= 0 && !inOverdrive {
                    hurt(amount: 1, away: CGPoint(x: shot.vx, y: shot.vy),
                         chunk: Palette.spitter, at: point)
                }
            } else if obstacles.contains(where: { !$0.destroyed && abs($0.y - shot.y) < 2
                                                  && hypot($0.x - shot.x, $0.y - shot.y) < $0.w * 0.42 }) {
                shots[index].life = 0
                burstParticles(count: reduceMotion ? 2 : 5, kind: .spark, color: Palette.spitter,
                               at: point, speed: 3)
            }
        }
        shots.removeAll { $0.life <= 0 || $0.x < -1 || $0.x > Self.shaftWidth + 1 }
    }

    /// Crystal Core: a shard straight off the bit every couple of seconds.
    private func fireCrystalCore(_ dt: Double) {
        guard gear.coreCooldown > 0 else { return }
        coreCooldown -= dt
        guard coreCooldown <= 0 else { return }
        coreCooldown = gear.coreCooldown
        let direction = headingVector
        shots.append(Shot(id: claimID(), x: bitPoint.x, y: bitPoint.y,
                          vx: direction.x * 11, vy: direction.y * 11, life: 1.6, style: .friendly))
        burstParticles(count: reduceMotion ? 2 : 6, kind: .spark, color: Palette.window, at: bitPoint, speed: 3)
    }

    /// Player shards kill critters, crack rock the bit could crack, and chip bosses.
    private func resolveFriendlyShot(_ index: Int) {
        let shot = shots[index]
        let point = CGPoint(x: shot.x, y: shot.y)
        if let target = enemies.firstIndex(where: { !$0.dead && $0.awake
                                                    && $0.surfaced && hypot($0.x - shot.x, $0.y - shot.y) < $0.radius + 0.25 }) {
            shots[index].life = 0
            if enemies[target].isKillable(power: loadout.power) || inOverdrive {
                defeat(target)
            } else {
                enemies[target].hitFlash = 1
                burstParticles(count: reduceMotion ? 2 : 6, kind: .spark, color: Palette.window, at: point, speed: 3)
            }
            return
        }
        if let rock = obstacles.firstIndex(where: { !$0.destroyed && abs($0.y - shot.y) < 2
                                                    && hypot($0.x - shot.x, $0.y - shot.y) < $0.w * 0.45 }) {
            shots[index].life = 0
            if canDrill(obstacles[rock]) {
                obstacles[rock].destroyed = true
                burstParticles(count: reduceMotion ? 5 : 14, kind: .chunk,
                               color: Palette.rock(hardness: obstacles[rock].hardness),
                               at: CGPoint(x: obstacles[rock].x, y: obstacles[rock].y), speed: 6)
                bumpCombo(at: point)
            } else {
                burstParticles(count: reduceMotion ? 2 : 6, kind: .spark, color: Palette.window, at: point, speed: 3)
            }
            return
        }
        if shotHitsBoss(at: point) { shots[index].life = 0 }
    }

    private func steerBeetle(_ beetle: inout Enemy, _ dt: Double) {
        // Straight across and back on its own row.
        let across: Double = sin(beetle.heading) < 0 ? -.pi / 2 : .pi / 2
        let correction = max(-0.3, min(0.3, (beetle.y - beetle.homeY) * 0.5))
        beetle.heading = across + (across > 0 ? -correction : correction)
    }

    private func resolveEnemies() {
        let bit = bitPoint
        for index in enemies.indices {
            let enemy = enemies[index]
            guard enemy.awake, !enemy.dead, enemy.surfaced else { continue }
            // Freshly split slimes get a moment before they can be popped or bite.
            if enemy.small && enemy.stun > 0.2 { continue }
            let radius = enemy.radius
            let toBit = hypot(enemy.x - bit.x, enemy.y - bit.y)
            let toBody = hypot(enemy.x - x, enemy.y - depth)

            if toBit < bitReach + radius {
                if inOverdrive || enemy.isKillable(power: loadout.power) {
                    defeat(index)
                } else if invuln <= 0 {
                    hitBy(index)
                }
            } else if toBody < Self.bodyRadius + radius {
                if inOverdrive || stacks(.spikedHull) > 0 {
                    defeat(index)
                } else if invuln <= 0 {
                    hitBy(index)
                }
            } else if enemy.kind == .centipede, !inOverdrive {
                // Armoured body: it hurts the hull and turns the bit aside.
                for segment in enemy.segments {
                    if invuln <= 0, hypot(segment.x - x, segment.y - depth) < Self.bodyRadius + 0.28 {
                        hurt(amount: 1, away: CGPoint(x: x - segment.x, y: depth - segment.y),
                             chunk: Palette.centipede, at: segment)
                        break
                    }
                    if hypot(segment.x - bit.x, segment.y - bit.y) < bitReach + 0.26 {
                        let away = CGPoint(x: x - segment.x, y: depth - segment.y)
                        let length = max(0.01, hypot(away.x, away.y))
                        vx = away.x / length * 4
                        vy = away.y / length * 4
                        stun = max(stun, 0.2)
                        popup("CLANK", at: segment, tint: Palette.drillBit)
                        burstParticles(count: reduceMotion ? 2 : 6, kind: .spark, color: Palette.drillBit, at: segment, speed: 4)
                        break
                    }
                }
            }
        }
    }

    private func defeat(_ index: Int) {
        enemies[index].dead = true
        let enemy = enemies[index]
        let point = CGPoint(x: enemy.x, y: enemy.y)
        enemiesDefeated += 1
        bestiaryKills[BestiaryEntry.key(.critter(enemy.kind)), default: 0] += 1
        if gear.killFuel > 0 { fuel = min(loadout.fuelCapacity, fuel + gear.killFuel) }
        let bounty = Int(Double(currentLayer.goldValue * (enemy.kind == .worm ? 1 : 2) * comboMultiplier)
                         * gear.killGold)
        coins += bounty
        for _ in 0..<(reduceMotion ? 2 : 4) {
            launchToCounter(from: CGPoint(x: point.x + fx.double(-0.4...0.4),
                                          y: point.y + fx.double(-0.4...0.4)), color: Palette.gold)
        }
        let color: Color
        switch enemy.kind {
        case .worm: color = Palette.worm
        case .bat: color = Palette.batWing
        case .beetle: color = Palette.beetleSheen
        case .spitter: color = Palette.spitter
        case .ember: color = Palette.ember
        case .jelly: color = Palette.jelly
        case .angler: color = Palette.anglerBelly
        case .mole: color = Palette.mole
        case .spider: color = Palette.spider
        case .centipede: color = Palette.centipede
        case .slime: color = Palette.slime
        case .slug: color = Palette.slug
        }
        if enemy.kind == .slime && !enemy.small {
            // Pop a big slime and two little ones bounce out to either side of
            // the bit (not onto it, or they would pop in the same instant).
            let across = CGPoint(x: -headingVector.y, y: headingVector.x)
            for side in [-1.0, 1.0] {
                let spot = CGPoint(x: min(max(enemy.x + across.x * side * 1.0, 1), Self.shaftWidth - 1),
                                   y: enemy.y + across.y * side * 1.0)
                var half = Enemy(id: claimID(), kind: .slime, x: spot.x, y: spot.y,
                                 heading: side * .pi / 2, homeY: enemy.homeY, hardness: 0,
                                 speed: enemy.speed * 1.2, phase: enemy.phase + side)
                half.small = true
                half.awake = true
                half.stun = 0.5
                enemies.append(half)
            }
        }
        burstParticles(count: reduceMotion ? 8 : 24, kind: .chunk, color: color, at: point, speed: 7)
        burstParticles(count: reduceMotion ? 3 : 10, kind: .spark, color: Palette.gold, at: point, speed: 5)
        for segment in enemy.segments {
            burstParticles(count: reduceMotion ? 1 : 3, kind: .chunk, color: Palette.wormShadow,
                           at: segment, speed: 4)
        }
        popup("+\(bounty)", at: point, tint: Palette.gold, big: true)
        if !reduceMotion { shake = max(shake, 0.4) }
        Haptics.bump()
        bumpCombo(at: point)
    }

    private func hitBy(_ index: Int) {
        let enemy = enemies[index]
        enemies[index].hitFlash = 1
        enemies[index].stun = Self.enemyStun
        // The critter recoils the other way so it cannot chain-bite.
        enemies[index].heading = atan2(-(enemy.x - x), enemy.y - depth)
        if enemy.kind == .bat {
            enemies[index].mode = .recover
            enemies[index].timer = 1.6
        }
        if enemy.kind == .mole {
            // A mole that bites dives straight back underground.
            enemies[index].mode = .patrol
            enemies[index].timer = 2.2
        }
        if enemy.kind == .ember {
            // Touching one sets it off.
            enemies[index].dead = true
            burstParticles(count: reduceMotion ? 8 : 26, kind: .spark, color: Palette.ember,
                           at: CGPoint(x: enemy.x, y: enemy.y), speed: 8)
        }
        hurt(amount: 1, away: CGPoint(x: x - enemy.x, y: depth - enemy.y),
             chunk: enemy.kind == .worm ? Palette.worm : Palette.bat,
             at: CGPoint(x: enemy.x, y: enemy.y))
    }

    // MARK: - Endings

    private func checkEndConditions(_ dt: Double) {
        if armor <= 0 {
            endReason = .wrecked
            stall()
            return
        }
        if fuel <= 0 {
            endReason = .outOfFuel
            coast += dt
            if coast > 0.65 || hypot(vx, vy) < 0.3 { stall() }
        }
    }

    private func stall() {
        guard phase == .drilling else { return }
        phase = .stalled
        isHolding = false
        steerVector = nil
        // Out of fuel with a refill still available means the player gets the
        // offer instead of the results card.
        if endReason == .outOfFuel, !refillUsed, !isDaily, armor > 0 {
            return
        }
        finish()
    }

    private func finish() {
        phase = .ended
        let depthInt = Int(maxDepth.rounded(.down))
        // The hold sells at the surface; coins were already in the wallet.
        bankedValue = coins + cargoValue
        let payout = doubleGold && !isDaily ? bankedValue * 2 : bankedValue
        let result = RunResult(
            depth: depthInt,
            previousBest: Int(previousBest.rounded(.down)),
            newRecord: !isDaily && Double(depthInt) > previousBest,
            collected: collectedValue,
            banked: bankedValue,
            payout: payout,
            oreValue: cargoValue,
            oreCount: oreCount,
            coins: coins,
            gems: gemCount,
            chambers: chambersOpened,
            cargoOverflowed: cargoOverflowed,
            reason: endReason,
            bestCombo: bestCombo,
            enemiesDefeated: enemiesDefeated,
            bossesDefeated: bossesDefeated,
            bossKindsDefeated: bossKindsDefeated,
            bestiarySeen: bestiarySeen,
            bestiaryKills: bestiaryKills,
            isDaily: isDaily,
            dailyScore: DailyChallenge.score(depth: depthInt, gold: bankedValue)
        )
        onEnd?(result)
    }

    /// True while the rewarded-refill offer is the right thing to show.
    var offersRefill: Bool {
        phase == .stalled && endReason == .outOfFuel && !refillUsed && !isDaily && armor > 0
    }

    // MARK: - Particles and flourishes

    private func emitDust(_ dt: Double) {
        dustCooldown -= dt
        guard dustCooldown <= 0 else { return }
        dustCooldown = reduceMotion ? 0.09 : 0.022
        let layer = currentLayer
        let count = reduceMotion ? 1 : 2
        for _ in 0..<count {
            let side = fx.chance(0.5) ? -1.0 : 1.0
            // Spray sideways off the bit and back along the hull.
            let forward = headingVector
            let across = CGPoint(x: -forward.y, y: forward.x)
            let spray = fx.double(1.4...3.6)
            let kick = fx.double(0.6...3.4)
            let offset = fx.double(0.15...0.5)
            particles.append(Particle(
                x: bitPoint.x + across.x * side * offset,
                y: bitPoint.y + across.y * side * offset + fx.double(-0.1...0.2),
                vx: across.x * side * spray - forward.x * kick,
                vy: across.y * side * spray - forward.y * kick,
                life: fx.double(0.28...0.6),
                maxLife: 0.6,
                size: fx.double(0.08...0.2),
                angle: fx.double(0...6.28),
                spin: fx.double(-7...7),
                color: fx.chance(0.65) ? layer.pebble : layer.soilDeep,
                kind: .dust))
        }
        if !reduceMotion, fx.chance(0.25) {
            particles.append(Particle(
                x: bitPoint.x + fx.double(-0.35...0.35),
                y: bitPoint.y,
                vx: fx.double(-2...2),
                vy: fx.double(-2.4...(-0.4)),
                life: 0.5, maxLife: 0.5,
                size: fx.double(0.1...0.18),
                angle: fx.double(0...6.28),
                spin: fx.double(-9...9),
                color: layer.soil,
                kind: .chunk))
        }
        trimParticles()
    }

    private func emitSmoke(_ dt: Double) {
        guard !reduceMotion else { return }
        smokeCooldown -= dt
        guard smokeCooldown <= 0 else { return }
        smokeCooldown = 0.12
        let rear = CGPoint(x: x - headingVector.x * 1.0, y: depth - headingVector.y * 1.0)
        particles.append(Particle(
            x: rear.x + headingVector.y * 0.52,
            y: rear.y - headingVector.x * 0.52,
            vx: fx.double(-0.5...0.2),
            vy: fx.double(-1.6...(-0.7)),
            life: 0.75, maxLife: 0.75,
            size: fx.double(0.14...0.26),
            angle: 0, spin: fx.double(-2...2),
            color: Palette.exhaust,
            kind: .smoke))
        trimParticles()
    }

    /// Gold flame streaming off the hull while Overdrive is running.
    private func emitOverdriveFlame(_ dt: Double) {
        let count = reduceMotion ? 1 : 3
        for _ in 0..<count {
            let back = fx.double(0.2...0.9)
            let thrust = fx.double(3...6)
            particles.append(Particle(
                x: x - headingVector.x * back + fx.double(-0.5...0.5),
                y: depth - headingVector.y * back + fx.double(-0.5...0.5),
                vx: -headingVector.x * thrust + fx.double(-0.8...0.8),
                vy: -headingVector.y * thrust + fx.double(-0.8...0.8),
                life: fx.double(0.2...0.4), maxLife: 0.4,
                size: fx.double(0.12...0.24),
                angle: 0, spin: 0,
                color: fx.chance(0.5) ? Palette.drillBody : Palette.exhaust,
                kind: .spark))
        }
        trimParticles()
    }

    func burstParticles(count: Int, kind: ParticleKind, color: Color,
                                at point: CGPoint, speed: Double) {
        for _ in 0..<count {
            let angle = fx.double(0...(.pi * 2))
            let magnitude = fx.double(speed * 0.35...speed)
            particles.append(Particle(
                x: point.x, y: point.y,
                vx: cos(angle) * magnitude,
                vy: sin(angle) * magnitude - 1.2,
                life: fx.double(0.3...0.8),
                maxLife: 0.8,
                size: fx.double(0.1...0.26),
                angle: fx.double(0...6.28),
                spin: fx.double(-10...10),
                color: color,
                kind: kind))
        }
        trimParticles()
    }

    private func trimParticles() {
        let cap = reduceMotion ? 80 : 260
        if particles.count > cap { particles.removeFirst(particles.count - cap) }
    }

    private func updateParticles(_ dt: Double) {
        for index in particles.indices {
            particles[index].life -= dt
            particles[index].x += particles[index].vx * dt
            particles[index].y += particles[index].vy * dt
            particles[index].angle += particles[index].spin * dt
            switch particles[index].kind {
            case .dust, .chunk:
                particles[index].vy += 7 * dt          // settles back down
                particles[index].vx *= max(0, 1 - dt * 2.5)
            case .spark:
                particles[index].vy += 3 * dt
                particles[index].vx *= max(0, 1 - dt * 2)
            case .smoke:
                particles[index].vy -= 0.6 * dt         // keeps rising
                particles[index].size += dt * 0.35
            }
        }
        particles.removeAll { $0.life <= 0 }
    }

    /// A coin (or ore chunk) arcing from the world to its HUD counter: coins to
    /// the wallet, ore to the hold.
    func launchToCounter(from world: CGPoint, color: Color, big: Bool = false, toCargo: Bool = false) {
        let goldAnchor = toCargo ? cargoAnchor : self.goldAnchor
        let scale = viewportSize.width / Self.shaftWidth
        let start = CGPoint(x: world.x * scale, y: (world.y - camera) * scale)
        let control = CGPoint(x: (start.x + goldAnchor.x) / 2 + fx.double(-40...40),
                              y: min(start.y, goldAnchor.y) - fx.double(30...90))
        flying.append(FlyingValue(id: claimID(), from: start, control: control,
                                  to: goldAnchor, color: color, big: big))
        if flying.count > 60 { flying.removeFirst(flying.count - 60) }
    }

    private func updateFlying(_ dt: Double) {
        let speed = reduceMotion ? 3.2 : 2.1
        for index in flying.indices { flying[index].t += dt * speed }
        flying.removeAll { $0.t >= 1 }
    }

    func shout(_ text: String, tint: Color) {
        shouts.append(Shout(id: claimID(), text: text, tint: tint))
    }

    func popup(_ text: String, at point: CGPoint, tint: Color, big: Bool = false) {
        popups.append(Popup(id: claimID(), x: point.x, y: point.y, text: text, tint: tint, big: big))
        if popups.count > 16 { popups.removeFirst(popups.count - 16) }
    }

    private func updatePopups(_ dt: Double) {
        for index in popups.indices { popups[index].t += dt * (popups[index].big ? 0.9 : 1.5) }
        popups.removeAll { $0.t >= 1 }
    }

    private func updateShouts(_ dt: Double) {
        for index in shouts.indices { shouts[index].t += dt * 0.55 }
        shouts.removeAll { $0.t >= 1 }
    }

    private func updateChamberAnimation(_ dt: Double) {
        for index in chambers.indices where chambers[index].opened {
            chambers[index].openT = min(1, chambers[index].openT + dt * 2.5)
        }
    }

    // MARK: - Terrain generation

    private func placeChamber() {
        // Just past the player's best, so the pull is always "a little further".
        let base: Double
        if isDaily {
            base = 150
        } else if previousBest > 40 {
            guard rng.chance(0.7) else { return }
            base = previousBest + rng.double(5...20)
        } else {
            base = rng.double(70...110)
        }
        let reward = 55 + Int(base / 3.5)
        chambers.append(Chamber(id: claimID(),
                                x: rng.double(2.4...(Self.shaftWidth - 2.4)),
                                y: base,
                                radius: rng.double(2.1...2.7),
                                reward: reward))
    }

    private func generateTerrain() {
        while generatedTo < depth + viewHeightMeters + 18 {
            generateBand(at: generatedTo)
            generatedTo += Self.bandHeight
        }
    }

    private func clearedByChamber(_ point: CGPoint, pad: Double) -> Bool {
        chambers.contains { chamber in
            let dx = chamber.x - point.x
            let dy = chamber.y - point.y
            let reach = chamber.radius + pad
            return dx * dx + dy * dy < reach * reach
        }
    }

    private func generateBand(at bandTop: Double) {
        let layerIndex = Strata.index(for: max(0, bandTop))
        let layer = Strata.layers[layerIndex]
        let difficulty = min(1.0, bandTop / 520)
        // Critters keep getting denser and faster past the point where the
        // rest of the curve tops out, so deep runs never settle into a cruise.
        let danger = min(2.0, bandTop / 520)

        // Decor first — it is cheap and sets the mood even in the opening metres.
        // Broad mottling behind everything, then pebbles, veins and crystals.
        for _ in 0..<rng.int(2...3) {
            decor.append(Decor(id: claimID(), kind: .blotch,
                               x: rng.double(-0.5...(Self.shaftWidth + 0.5)),
                               y: bandTop + rng.double(0...Self.bandHeight),
                               size: rng.double(1.6...3.4),
                               angle: rng.double(0...6.28),
                               seed: rng.next()))
        }
        for _ in 0..<rng.int(3...5) {
            let wantsCrystal = layer.crystal != nil && rng.chance(0.32)
            decor.append(Decor(id: claimID(),
                               kind: wantsCrystal ? .crystal : .pebble,
                               x: rng.double(0.2...(Self.shaftWidth - 0.2)),
                               y: bandTop + rng.double(0...Self.bandHeight),
                               size: wantsCrystal ? rng.double(0.45...0.9) : rng.double(0.25...0.95),
                               angle: rng.double(0...6.28),
                               seed: rng.next()))
        }
        if rng.chance(0.45) {
            decor.append(Decor(id: claimID(), kind: .vein,
                               x: rng.double(0...Self.shaftWidth),
                               y: bandTop + rng.double(0...Self.bandHeight),
                               size: rng.double(1.4...2.8),
                               angle: rng.double(0...6.28),
                               seed: rng.next()))
        }

        // The first stretch is a free runway so the player learns the controls.
        guard bandTop > 16 else { return }

        var blocked: [ClosedRange<Double>] = []
        let attempts: Int
        if bandTop < 50 {
            attempts = 1
        } else if difficulty > 0.35 && rng.chance(0.15 + 0.35 * difficulty) {
            attempts = 3
        } else {
            attempts = rng.chance(0.5 + 0.4 * difficulty) ? 2 : 1
        }

        for _ in 0..<attempts {
            let kind = pickObstacleKind(layerIndex: layerIndex, difficulty: difficulty)
            var width: Double
            var height: Double
            switch kind {
            case .boulder:
                width = rng.double(1.3...2.1); height = width * rng.double(0.85...1.0)
            case .slab:
                width = rng.double(2.4...3.5); height = rng.double(0.85...1.15)
            case .geode:
                width = rng.double(1.1...1.5); height = width
            }

            let centreX = rng.double((Self.wallMargin + width / 2)...(Self.shaftWidth - Self.wallMargin - width / 2))
            let centreY = bandTop + rng.double(0.6...(Self.bandHeight - 0.6))
            let span = (centreX - width / 2 - 0.25)...(centreX + width / 2 + 0.25)

            // Never seal the shaft: a drillable gap must survive.
            guard gapSurvives(adding: span, to: blocked) else { continue }
            guard !Self.inArena(centreY, pad: 1.5) else { continue }
            guard !clearedByChamber(CGPoint(x: centreX, y: centreY), pad: 1.2) else { continue }

            let hardness = kind == .geode ? Int.max : kind.baseHardness + layerIndex
            blocked.append(span)
            obstacles.append(Obstacle(id: claimID(), kind: kind,
                                      x: centreX, y: centreY,
                                      w: width, h: height,
                                      hardness: hardness,
                                      angle: kind == .slab ? rng.double(-0.1...0.1) : rng.double(0...6.28),
                                      seed: rng.next()))
        }

        // Magma Core: molten pools. They count toward the lane check like rock.
        if layerIndex >= 4, rng.chance(0.6) {
            let radius = rng.double(0.9...1.5)
            let centreX = rng.double((Self.wallMargin + radius)...(Self.shaftWidth - Self.wallMargin - radius))
            let centreY = bandTop + rng.double(1...(Self.bandHeight - 1))
            let span = (centreX - radius - 0.25)...(centreX + radius + 0.25)
            let poolSeed = rng.next()
            let clear = !obstacles.contains { abs($0.y - centreY) < $0.h / 2 + radius && abs($0.x - centreX) < $0.w / 2 + radius }
            if clear, gapSurvives(adding: span, to: blocked), !Self.inArena(centreY, pad: 2),
               !clearedByChamber(CGPoint(x: centreX, y: centreY), pad: 1) {
                blocked.append(span)
                lavaPools.append(LavaPool(id: claimID(), x: centreX, y: centreY, radius: radius, seed: poolSeed))
            }
        }

        // Treasure. Sometimes a weaving trail that pays a bonus when swept
        // whole, otherwise loose nuggets. Richer and more gem-heavy deeper down.
        if rng.chance(0.3) {
            layTrail(at: bandTop, value: layer.goldValue)
        }
        let goldCount = rng.int(1...2) + (difficulty > 0.4 ? 1 : 0)
        for _ in 0..<goldCount {
            let point = CGPoint(x: rng.double((Self.wallMargin + 0.3)...(Self.shaftWidth - Self.wallMargin - 0.3)),
                                y: bandTop + rng.double(0.5...(Self.bandHeight - 0.5)))
            // Draw before the checks: `crowdsPickup` looks at live pickups,
            // which Magnet and Gold Rush move, so a draw behind it would let
            // play shift the terrain stream.
            let phase = rng.double(0...6.28)
            guard !overlapsObstacle(point, pad: 0.75), !Self.inArena(point.y) else { continue }
            guard !clearedByChamber(point, pad: 0.4) else { continue }
            guard !crowdsPickup(point, pad: 1.1) else { continue }
            pickups.append(Pickup(id: claimID(), kind: .gold, x: point.x, y: point.y,
                                  value: layer.goldValue, phase: phase))
        }

        if rng.chance(0.08 + 0.26 * difficulty) {
            let point = CGPoint(x: rng.double((Self.wallMargin + 0.4)...(Self.shaftWidth - Self.wallMargin - 0.4)),
                                y: bandTop + rng.double(0.6...(Self.bandHeight - 0.6)))
            let phase = rng.double(0...6.28)
            if !overlapsObstacle(point, pad: 0.85), !clearedByChamber(point, pad: 0.4),
               !crowdsPickup(point, pad: 1.2), !Self.inArena(point.y) {
                pickups.append(Pickup(id: claimID(), kind: .gem, x: point.x, y: point.y,
                                      value: layer.gemValue, phase: phase))
            }
        }

        // Fuel cans are what let a skilled run outlast the tank.
        if bandTop > 30, rng.chance(0.11) {
            let point = CGPoint(x: rng.double((Self.wallMargin + 0.4)...(Self.shaftWidth - Self.wallMargin - 0.4)),
                                y: bandTop + rng.double(0.6...(Self.bandHeight - 0.6)))
            let phase = rng.double(0...6.28)
            if !overlapsObstacle(point, pad: 0.85), !clearedByChamber(point, pad: 0.4),
               !crowdsPickup(point, pad: 1.2), !Self.inArena(point.y) {
                pickups.append(Pickup(id: claimID(), kind: .fuel, x: point.x, y: point.y,
                                      value: 0, phase: phase))
            }
        }

        // Critters: each biome has a signature one and keeps a few of the
        // earlier kinds in the mix.
        if bandTop > 30, rng.chance(min(0.85, Self.enemyChance.base + Self.enemyChance.depth * danger)) {
            let roll = rng.double(0...1)
            let kind: EnemyKind
            // Each biome's natives first, then a few from the biome above.
            func pick(_ table: [(EnemyKind, Double)]) -> EnemyKind {
                var acc = 0.0
                for (kind, weight) in table { acc += weight; if roll < acc { return kind } }
                return table.last!.0
            }
            switch layerIndex {
            case 0: kind = pick([(.worm, 0.6), (.mole, 0.4)])
            case 1: kind = pick([(.bat, 0.45), (.spider, 0.35), (.worm, 0.1), (.mole, 0.1)])
            case 2: kind = pick([(.beetle, 0.4), (.centipede, 0.35), (.bat, 0.15), (.spider, 0.1)])
            case 3: kind = pick([(.spitter, 0.4), (.slime, 0.35), (.beetle, 0.15), (.centipede, 0.1)])
            case 4: kind = pick([(.ember, 0.4), (.slug, 0.35), (.spitter, 0.15), (.slime, 0.1)])
            default: kind = pick([(.jelly, 0.35), (.angler, 0.35), (.ember, 0.15), (.slug, 0.15)])
            }
            let point = CGPoint(x: rng.double((Self.wallMargin + 0.6)...(Self.shaftWidth - Self.wallMargin - 0.6)),
                                y: bandTop + rng.double(1...(Self.bandHeight - 1)))
            let goingRight = rng.chance(0.5)
            let phase = rng.double(0...6.28)
            if !clearedByChamber(point, pad: 1.5), !Self.inArena(point.y, pad: 3) {
                let speed: Double
                switch kind {
                case .worm: speed = 3.4 + 1.6 * difficulty
                case .bat: speed = 3.6 + 1.4 * difficulty
                case .beetle: speed = 2.6 + 1.8 * difficulty
                case .spitter: speed = 1.1
                case .ember: speed = 2.6 + 1.2 * difficulty
                case .jelly: speed = 1.6 + 0.6 * difficulty
                case .angler: speed = 3.0
                case .mole: speed = 2.2 + 0.8 * difficulty
                case .spider: speed = 3.0
                case .centipede: speed = 3.8 + 1.2 * difficulty
                case .slime: speed = 2.2 + 0.6 * difficulty
                case .slug: speed = 1.2
                }
                var enemy = Enemy(id: claimID(), kind: kind,
                                  x: point.x, y: point.y,
                                  heading: goingRight ? -.pi / 2 : .pi / 2, homeY: point.y,
                                  hardness: kind == .beetle ? 2 + layerIndex : 0,
                                  speed: speed * Self.enemySpeed * (1 + 0.15 * max(0, danger - 1)), phase: phase)
                if kind == .worm || kind == .centipede {
                    let back: Double = goingRight ? -0.3 : 0.3
                    let count = kind == .centipede ? 8 : 6
                    enemy.segments = (1...count).map { CGPoint(x: point.x + back * Double($0), y: point.y) }
                }
                if kind == .spider { enemy.homeY = point.y - 1.5 }
                enemies.append(enemy)
            }
        }
    }

    private func layTrail(at bandTop: Double, value: Int) {
        let amplitude = rng.double(1.0...2.0)
        let centre = rng.double((Self.wallMargin + 0.4 + amplitude)...(Self.shaftWidth - Self.wallMargin - 0.4 - amplitude))
        let phase = rng.double(0...(.pi * 2))
        let id = claimID()
        var placed: [Pickup] = []
        for step in 0..<5 {
            let point = CGPoint(x: centre + sin(phase + Double(step) * 0.9) * amplitude,
                                y: bandTop + 0.5 + Double(step) * 1.2)
            let bob = rng.double(0...6.28)
            guard !overlapsObstacle(point, pad: 0.6), !Self.inArena(point.y) else { continue }
            guard !clearedByChamber(point, pad: 0.4) else { continue }
            placed.append(Pickup(id: claimID(), kind: .gold, x: point.x, y: point.y,
                                 value: value, phase: bob,
                                 trail: id))
        }
        // A trail cut short by rock is just loose gold.
        if placed.count < 4 {
            for index in placed.indices { placed[index].trail = nil }
        }
        pickups += placed
    }

    private func pickObstacleKind(layerIndex: Int, difficulty: Double) -> ObstacleKind {
        let geodeChance = 0.06 + 0.2 * difficulty
        let slabChance = 0.25 + 0.2 * difficulty
        let roll = rng.double(0...1)
        if roll < geodeChance { return .geode }
        if roll < geodeChance + slabChance { return .slab }
        return .boulder
    }

    /// Checks that adding `span` still leaves `minGap` of clear shaft.
    private func gapSurvives(adding span: ClosedRange<Double>, to blocked: [ClosedRange<Double>]) -> Bool {
        var spans = blocked + [span]
        spans.sort { $0.lowerBound < $1.lowerBound }
        var cursor = Self.wallMargin
        var widest = 0.0
        for range in spans {
            if range.lowerBound > cursor {
                widest = max(widest, range.lowerBound - cursor)
            }
            cursor = max(cursor, range.upperBound)
        }
        widest = max(widest, (Self.shaftWidth - Self.wallMargin) - cursor)
        return widest >= Self.minGap
    }

    private func crowdsPickup(_ point: CGPoint, pad: Double) -> Bool {
        pickups.contains { other in
            abs(other.y - point.y) < pad && abs(other.x - point.x) < pad
        }
    }

    private func overlapsObstacle(_ point: CGPoint, pad: Double) -> Bool {
        obstacles.contains { rock in
            abs(rock.y - point.y) < rock.h / 2 + pad && abs(rock.x - point.x) < rock.w / 2 + pad
        } || lavaPools.contains { hypot($0.x - point.x, $0.y - point.y) < $0.radius + pad }
    }

    private func pruneBehind() {
        // Generous, because the drill can turn back up the shaft.
        let cutoff = camera - 30
        obstacles.removeAll { $0.y < cutoff }
        enemies.removeAll { $0.dead || $0.y < cutoff }
        shots.removeAll { $0.y < cutoff }
        lavaPools.removeAll { $0.y < cutoff }
        pickups.removeAll { $0.y < cutoff }
        decor.removeAll { $0.y < cutoff }
        chambers.removeAll { $0.y < cutoff && $0.openT >= 1 }
        particles.removeAll { $0.y < cutoff }
        popups.removeAll { $0.y < cutoff }
    }
}
