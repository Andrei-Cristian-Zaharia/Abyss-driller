#if DEBUG
import SwiftUI

// MARK: - Director mode (Debug builds only)
//
// Scripted scenarios for recording gameplay footage, e.g. in CI:
//
//   -scenario bossFight|goldRush|caveIn|deepBiome|garageUpgrades|random
//   -scenarioSeed 12345         seeds everything: the moment, the terrain and
//                               the autopilot's moves (default: from the clock)
//   -scenarioDuration 35        seconds of autopilot, then the app idles
//   -scenarioLayer 9            deepBiome/goldRush/caveIn: force a `Strata.layers` index
//   -scenarioBoss 3             bossFight: force a boss index
//   -scenarioCapture 36         record this many seconds offline at exactly
//                               60 fps (Core/DirectorCapture.swift) to
//                               Documents/DirectorCapture/capture.mp4
//
// With -scenarioCapture the wall clock is out of the loop: the game, the
// autopilot and the garage script run on a virtual clock that advances by
// exactly 1/60 s per captured frame, and a frame is captured only after the
// world canvas has drawn it. A slow simulator just takes longer to capture;
// the clip still plays at normal speed with 60 unique frames per second.
// (Plain SwiftUI menu animations still run on real time.)
//
// Each launch rolls a different moment (biome, depth, boss, rig, perks, fuel,
// coins, events, early dig / mid run / near death / overdrive) and a
// procedural plan of moves (zig-zags, dives, sweeps, swirls, hooks, bursts,
// short thumb lifts). Everything comes from `SeededRandom`, so the same seed
// sets up the same moment and the same move plan; the frame-by-frame play
// still reacts to the live world, so two runs are alike, not identical.
// The plan is logged once as `[Director] PLAN {json}` for the CI manifest.
//
// Launch arguments of the form `-key value` land in `UserDefaults`, which is
// how they are read here. A directed launch skips ads, consent and the
// cloud save, starts from a fresh in-memory profile and never saves it, so
// it cannot touch real progress. Nothing in this file ships: the whole file
// is compiled out of Release.

enum Scenario: String, CaseIterable {
    case bossFight, goldRush, caveIn, deepBiome, garageUpgrades
}

/// When in a run the clip is set.
enum Moment: String, CaseIterable {
    case earlyDig, midRun, nearDeath, overdriveCombo
}

/// One stretch of the autopilot's move plan.
struct Move {
    enum Kind: String, CaseIterable { case cruise, zigzag, dive, sweep, swirl, hook, burst, pause }
    var kind: Kind
    var start: Double
    var duration: Double
    var side: Double        // -1 / +1
    var amp: Double         // radians
    var freq: Double        // rad/s
    var push: Double        // stick deflection, 0...1
    var phase: Double
}

/// Everything rolled for one clip.
struct DirectorPlan {
    var scenario: Scenario
    var moment: Moment
    var layer: Int?
    var depthOffset = 4.0
    var boss: Int?
    var bossHP = "full"           // full | enraged | lastLegs
    var approach = 9.0            // metres above the arena when the clip starts
    var levels: [UpgradeTrack: Int] = [:]
    var perks: [Perk] = []
    var fuelFraction = 1.0
    var armorLeft: Int?           // nearDeath
    var coins = 0
    var events: [RunEventKind] = []
    var eventGap = 0.8
    var eventAt = 0.0             // deepBiome: one event at this time (0 = none)
    var scatterEvery = 1.8
    var scatterCount = 7
    var heading = 0.0
    var garage: [(part: ShipPart, upgrades: Int)] = []
    var garageTracks: [UpgradeTrack: Int] = [:]
    var garageGold = 150_000
    var beat = 1.8
    var ease = 3.2
    var tremor = 0.05
    var perkThink = 1.4
    var dodgeEvery = 3.5
    var dodgeFor = 0.9
    var circleRadius = 2.5
    var moves: [Move] = []

    /// Scenario + parameters, used by CI to skip a repeat in the same run.
    var key: String {
        var parts = [scenario.rawValue, moment.rawValue]
        switch scenario {
        case .bossFight: parts += ["boss\(boss ?? -1)", bossHP]
        case .goldRush, .caveIn: parts += ["layer\(layer ?? -1)", events.map(eventName).joined(separator: "+")]
        case .deepBiome: parts += ["layer\(layer ?? -1)", eventAt > 0 ? events.map(eventName).joined(separator: "+") : "noEvent"]
        case .garageUpgrades: parts += garage.map { "\($0.part.rawValue)x\($0.upgrades)" }
        }
        parts.append(perks.map(\.rawValue).sorted().joined(separator: "+"))
        return parts.joined(separator: "|")
    }
}

func eventName(_ kind: RunEventKind) -> String {
    switch kind {
    case .caveIn: return "caveIn"
    case .goldRush: return "goldRush"
    case .darkness: return "darkness"
    }
}

/// Director capture's virtual clock, the one thing `GameView` observes.
@Observable final class DirectorClock {
    var date = Date(timeIntervalSinceReferenceDate: 0)
}

final class Director {
    static let shared = Director()

    let scenario: Scenario?
    let requested: String?
    let seed: UInt64
    let duration: Double
    let layerChoice: Int?
    let bossChoice: Int?

    var isActive: Bool { scenario != nil }

    /// `-scenarioCapture <seconds>`: offline 60 fps capture on a virtual clock.
    let captureSeconds: Double?
    var isCapturing: Bool { isActive && captureSeconds != nil }
    static let captureFPS = 60
    /// Observed by `GameView` while capturing: its date is the virtual clock,
    /// and changing it is what makes the canvas draw the next frame.
    let clock = DirectorClock()
    private(set) var virtualNow: TimeInterval = 0
    private var captureOrigin: TimeInterval = 0
    /// First captured frame that shows the run's world canvas (CI measures
    /// unique frames per second from there on).
    private(set) var captureRunFrom: Int?
    #if canImport(UIKit)
    private var recorder: DirectorRecorder?
    #endif

    /// Terrain seed for the directed run (read by `AppModel.startRun`).
    var terrainSeed: UInt64? { isActive ? stableSeed("terrain:\(seed)") | 1 : nil }

    /// Joystick deflection the autopilot is holding (unit length at most),
    /// or nil when the thumb is "lifted". `GameView` draws it like a real stick.
    private(set) var stick: CGVector?
    /// Where the autopilot's thumb rests, as a fraction of the play area.
    private(set) var stickAnchor = CGPoint(x: 0.5, y: 0.78)

    private(set) var plan: DirectorPlan?
    /// Choices made during play (dodge sides, escapes) come from their own
    /// stream, so they never shift the logged plan.
    private var liveRNG: SeededRandom

    private weak var app: AppModel?
    private var startTime: TimeInterval?
    private var lastTime: TimeInterval?
    private var setUpWorld: ObjectIdentifier?
    private var finished = false
    private var aim = 0.0
    private var choosingSince: Double?
    private var nextEventTime = 0.0
    private var nextEventIndex = 0
    private var nextScatterTime = 0.0
    private var nextComboTime = 0.0
    private var bossHPApplied = false
    private var moveIndex = 0
    private var swirlGoal: Double?
    private var nextDodge = 0.0
    private var dodgeUntil = 0.0
    private var dodgeSide = 1.0
    private var guardSide = 1.0
    private var lastGuard = false
    private var progressCheck: (t: Double, x: Double, depth: Double)?
    private var escapeUntil = 0.0
    private var escapeSide = 1.0

    // Debug log (stderr; the CI workflow prints it in the Actions log).
    private var timelineFrames = 0
    private var renders = 0
    private var lastRenderFrame: Date?
    private var logWindowStart: TimeInterval?
    private var lastLoggedSteps = 0
    private var lastLoggedDropped = 0.0
    private var lastLoggedPosition: (x: Double, depth: Double, camera: Double)?
    private var stuckSeconds = 0
    private var lastCommand = ""

    private init() {
        let defaults = UserDefaults.standard
        let name = defaults.string(forKey: "scenario")
        requested = name
        let seconds = defaults.double(forKey: "scenarioDuration")
        duration = seconds > 0 ? seconds : 35
        let capture = defaults.double(forKey: "scenarioCapture")
        captureSeconds = capture > 0 ? capture : nil
        layerChoice = defaults.object(forKey: "scenarioLayer") != nil ? defaults.integer(forKey: "scenarioLayer") : nil
        bossChoice = defaults.object(forKey: "scenarioBoss") != nil ? defaults.integer(forKey: "scenarioBoss") : nil
        let given = defaults.string(forKey: "scenarioSeed").flatMap { UInt64($0.trimmingCharacters(in: .whitespaces)) }
        seed = given ?? UInt64(Date().timeIntervalSince1970 * 1000) % 1_000_000_000
        liveRNG = SeededRandom(seed: stableSeed("live:\(seed)"))
        var rng = SeededRandom(seed: stableSeed("director:\(seed)"))
        if name == "random" {
            scenario = rng.pick(Scenario.allCases)
        } else {
            scenario = name.flatMap(Scenario.init(rawValue:))
        }
        if let scenario {
            plan = Self.roll(scenario, rng: &rng, duration: duration, layer: layerChoice, boss: bossChoice)
        }
    }

    // MARK: - Rolling a moment

    private static func roll(_ scenario: Scenario, rng: inout SeededRandom, duration: Double,
                             layer: Int?, boss: Int?) -> DirectorPlan {
        let lastLayer = Strata.layers.count - 1
        let moment: Moment = scenario == .garageUpgrades
            ? .earlyDig
            : rng.pick([.earlyDig, .midRun, .midRun, .nearDeath, .overdriveCombo, .overdriveCombo])
        var plan = DirectorPlan(scenario: scenario, moment: moment)

        // A late-game rig (Power 10+ bores hardness 11, so even Void rock
        // cracks): deep layers and bosses don't stall the footage.
        plan.levels[.power] = rng.int(10...12)
        for track in UpgradeTrack.allCases where track != .power { plan.levels[track] = rng.int(7...12) }

        switch moment {
        case .earlyDig:
            plan.fuelFraction = rng.double(0.85...1)
        case .midRun:
            plan.fuelFraction = rng.double(0.55...0.85)
            plan.coins = rng.int(400...3_500)
        case .nearDeath:
            plan.fuelFraction = rng.double(0.18...0.3)
            plan.armorLeft = 2
            plan.coins = rng.int(800...5_000)
        case .overdriveCombo:
            plan.fuelFraction = rng.double(0.6...1)
            plan.coins = rng.int(200...2_500)
        }
        let perkCount: Int
        switch moment {
        case .earlyDig: perkCount = 0
        case .midRun: perkCount = rng.int(1...3)
        case .nearDeath: perkCount = rng.int(0...2)
        case .overdriveCombo: perkCount = rng.int(1...2)
        }
        var pool = Perk.allCases.filter { $0.maxStacks > 0 }
        if moment == .overdriveCombo, rng.chance(0.6) {
            plan.perks.append(.overcharge)
            pool.removeAll { $0 == .overcharge }
        }
        while plan.perks.count < perkCount, !pool.isEmpty {
            plan.perks.append(pool.remove(at: rng.int(0...(pool.count - 1))))
        }

        switch scenario {
        case .bossFight:
            plan.boss = boss ?? rng.int(0...lastLayer)
            plan.bossHP = rng.pick(["full", "full", "enraged", "lastLegs"])
            plan.approach = rng.double(7...11)
        case .goldRush:
            plan.layer = layer ?? rng.int(1...lastLayer)
            plan.depthOffset = rng.double(4...40)
            plan.events = rng.chance(0.3) ? [.goldRush, .darkness] : [.goldRush]
            plan.eventGap = rng.double(0.3...1.2)
            plan.scatterEvery = rng.double(1.4...2.4)
            plan.scatterCount = rng.int(5...9)
        case .caveIn:
            plan.layer = layer ?? rng.int(1...lastLayer)
            plan.depthOffset = rng.double(4...40)
            plan.events = rng.pick([[.caveIn], [.caveIn], [.caveIn, .darkness], [.caveIn, .goldRush]])
            plan.eventGap = rng.double(0.5...2.0)
        case .deepBiome:
            plan.layer = layer ?? rng.int(2...lastLayer)
            plan.depthOffset = rng.double(4...45)
            if rng.chance(0.55) {
                plan.events = [rng.pick(RunEventKind.allCases)]
                plan.eventAt = rng.double(5...min(15, max(6, duration / 2)))
            }
        case .garageUpgrades:
            var parts = ShipPart.allCases.filter { $0.droppedBy == nil && $0.price != nil }
            for _ in 0..<rng.int(2...4) where !parts.isEmpty {
                let part = parts.remove(at: rng.int(0...(parts.count - 1)))
                plan.garage.append((part: part, upgrades: rng.int(0...2)))
            }
            for track in UpgradeTrack.allCases { plan.garageTracks[track] = rng.int(0...3) }
            plan.garageGold = rng.int(150...220) * 1_000
            plan.beat = rng.double(1.4...2.1)
        }

        plan.heading = rng.double(-0.5...0.5)
        plan.ease = rng.double(2.6...3.8)
        plan.tremor = rng.double(0.03...0.07)
        plan.perkThink = rng.double(0.9...1.8)
        plan.dodgeEvery = rng.double(2.5...5)
        plan.dodgeFor = rng.double(0.6...1.3)
        plan.circleRadius = rng.double(2...3.5)
        plan.moves = rollMoves(rng: &rng, until: duration + 20)
        return plan
    }

    /// A move plan covering `until` seconds: varied stretches with no long
    /// idle part (a lift is short and never follows another lift).
    private static func rollMoves(rng: inout SeededRandom, until: Double) -> [Move] {
        let weights: [(Move.Kind, Double)] = [(.cruise, 3), (.zigzag, 3), (.dive, 2), (.sweep, 2.5),
                                              (.swirl, 1.2), (.hook, 1.2), (.burst, 2), (.pause, 1)]
        let total = weights.reduce(0) { $0 + $1.1 }
        var moves: [Move] = []
        var t = 0.0
        while t < until {
            var kind = Move.Kind.cruise
            var roll = rng.double(0...total)
            for (k, w) in weights {
                if roll < w { kind = k; break }
                roll -= w
            }
            if kind == .pause, moves.isEmpty || moves.last?.kind == .pause { kind = .cruise }
            if moves.last?.kind == kind, kind != .cruise { kind = .cruise }
            let duration: Double
            switch kind {
            case .cruise: duration = rng.double(2...4)
            case .zigzag: duration = rng.double(2...3.5)
            case .dive: duration = rng.double(1.2...2.4)
            case .sweep: duration = rng.double(1.6...3)
            case .swirl: duration = rng.double(2...3)
            case .hook: duration = rng.double(1.4...2.2)
            case .burst: duration = rng.double(1...2)
            case .pause: duration = rng.double(0.2...0.5)
            }
            let move = Move(kind: kind, start: t, duration: duration,
                            side: rng.chance(0.5) ? 1 : -1,
                            amp: rng.double(0.35...0.9),
                            freq: rng.double(0.8...2.2),
                            push: rng.double(0.72...0.95),
                            phase: rng.double(0...(2 * .pi)))
            moves.append(move)
            t += duration
        }
        return moves
    }

    /// The plan as one JSON line for the CI manifest.
    private func planJSON(_ plan: DirectorPlan) -> String {
        var params: [String: Any] = [
            "moment": plan.moment.rawValue,
            "levels": Dictionary(uniqueKeysWithValues: plan.levels.map { ($0.key.rawValue, $0.value) }),
            "perks": plan.perks.map(\.rawValue),
            "fuelFraction": (plan.fuelFraction * 100).rounded() / 100,
            "coins": plan.coins,
            "startHeading": (plan.heading * 100).rounded() / 100,
        ]
        if let layer = plan.layer {
            params["layer"] = layer
            params["biome"] = Strata.layers[min(max(0, layer), Strata.layers.count - 1)].name
            params["depthOffset"] = plan.depthOffset.rounded()
        }
        if let boss = plan.boss {
            params["boss"] = boss
            params["bossKind"] = String(describing: GameWorld.bossKind(boss))
            params["bossHP"] = plan.bossHP
        }
        if !plan.events.isEmpty { params["events"] = plan.events.map(eventName) }
        if plan.eventAt > 0 { params["eventAt"] = plan.eventAt.rounded() }
        if let armor = plan.armorLeft { params["armorLeft"] = armor }
        if !plan.garage.isEmpty {
            params["garage"] = plan.garage.map { ["part": $0.part.rawValue, "upgrades": $0.upgrades] as [String: Any] }
            params["garageGold"] = plan.garageGold
        }
        let movement: [String: Any] = [
            "pattern": plan.moves.prefix(24).map { "\($0.kind.rawValue):\(String(format: "%.1f", $0.duration))" }
                .joined(separator: ","),
            "ease": (plan.ease * 100).rounded() / 100,
            "dodgeEvery": (plan.dodgeEvery * 10).rounded() / 10,
            "dodgeFor": (plan.dodgeFor * 10).rounded() / 10,
        ]
        let object: [String: Any] = [
            "seed": String(seed),
            "requested": requested ?? "",
            "scenario": plan.scenario.rawValue,
            "key": plan.key,
            "params": params,
            "movement": movement,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Start

    /// Called once from `ContentView` when the app appears.
    func begin(app: AppModel) {
        guard let scenario, let plan, self.app == nil else { return }
        self.app = app
        log("begin scenario=\(scenario.rawValue) seed=\(seed) duration=\(duration)s")
        log("PLAN \(planJSON(plan))")
        // The duration covers the whole scenario, menus included.
        startTime = Date().timeIntervalSinceReferenceDate
        #if canImport(UIKit)
        if let captureSeconds {
            captureOrigin = startTime ?? 0
            virtualNow = captureOrigin
            clock.date = Date(timeIntervalSinceReferenceDate: virtualNow)
            let recorder = DirectorRecorder(seconds: captureSeconds, fps: Self.captureFPS)
            self.recorder = recorder
            recorder.start()
        }
        #endif
        switch scenario {
        case .garageUpgrades:
            runGarageScript(app, plan: plan)
        case .bossFight, .goldRush, .caveIn, .deepBiome:
            for track in UpgradeTrack.allCases {
                app.profile.levels[track] = max(app.profile.levels[track], plan.levels[track] ?? 10)
            }
            app.startRun()
        }
    }

    /// The garage half of `garageUpgrades`: buy and upgrade a few random
    /// parts on screen, top up the Workshop, then drill with the new rig.
    private func runGarageScript(_ app: AppModel, plan: DirectorPlan) {
        giveGold(plan.garageGold)
        app.screen = .garage
        Task { @MainActor in
            func beat(_ seconds: Double) async {
                guard self.isCapturing else { try? await Task.sleep(for: .seconds(seconds)); return }
                // Capturing: wait in game time, so the beats keep their length in the clip.
                let end = self.virtualNow + seconds
                while self.virtualNow < end { try? await Task.sleep(for: .milliseconds(4)) }
            }
            await beat(plan.beat * 0.85)
            for (part, upgrades) in plan.garage {
                app.buy(part)
                await beat(plan.beat)
                for _ in 0..<upgrades {
                    app.upgrade(part)
                    await beat(plan.beat)
                }
            }
            for track in UpgradeTrack.allCases {
                for _ in 0..<(plan.garageTracks[track] ?? 0) { _ = app.buy(track) }
            }
            await beat(plan.beat * 0.7)
            app.startRun()
        }
    }

    // MARK: - Per frame

    /// Called by `GameView` every frame, before the world ticks.
    func frame(world: GameWorld, now: TimeInterval) {
        guard let scenario, let plan else { return }
        timelineFrames += 1
        logStatus(world: world, now: now)
        guard !finished else { return }
        if startTime == nil { startTime = now }
        let t = now - (startTime ?? now)
        let dt = min(0.1, max(0, now - (lastTime ?? now)))
        lastTime = now

        if t >= duration {
            // Recording is stopped from outside; let the drill come to rest.
            finished = true
            stick = nil
            world.isHolding = false
            world.steerVector = nil
            log(String(format: "t=%.1fs scenario finished, thumb lifted", t))
            return
        }

        // A slow simulator (software rendering, ~15-20 fps) can need more
        // than 16 fixed steps per frame; catch up to the full 0.25 s the
        // clock allows so the world keeps real speed on screen.
        world.maxStepsPerTick = 30
        world.beginIfNeeded()
        if setUpWorld != ObjectIdentifier(world), world.phase == .drilling {
            setUpWorld = ObjectIdentifier(world)
            setUp(scenario, plan: plan, world: world, t: t)
        }
        keepAlive(world, plan: plan)
        script(scenario, plan: plan, world: world, t: t)
        autopilot(scenario, plan: plan, world: world, t: t, dt: dt)
    }

    private func setUp(_ scenario: Scenario, plan: DirectorPlan, world: GameWorld, t: Double) {
        switch scenario {
        case .bossFight:
            let top = GameWorld.bossBoundary(max(0, plan.boss ?? 3)) - GameWorld.arenaHeight
            world.debugJump(toDepth: top - plan.approach)
        case .goldRush, .caveIn, .deepBiome:
            jump(toLayer: plan.layer ?? (Strata.layers.count - 1), offset: plan.depthOffset, in: world)
        case .garageUpgrades:
            break                                // a normal run with the new rig
        }
        if scenario != .garageUpgrades { world.heading = plan.heading }
        aim = world.heading
        for perk in plan.perks {
            world.perkOffer = [perk]
            world.setPhase(.choosing)
            world.choosePerk(perk)
        }
        world.fuel = world.loadout.fuelCapacity * plan.fuelFraction
        if let armor = plan.armorLeft { setArmor(min(armor, world.loadout.armor), in: world) }
        world.coins += plan.coins

        switch scenario {
        case .goldRush:
            world.loadout.cargoSlots = max(world.loadout.cargoSlots, 80)
            nextEventTime = t
            nextScatterTime = t + 1.2
        case .caveIn:
            nextEventTime = t
        case .deepBiome:
            nextEventTime = plan.eventAt > 0 ? t + plan.eventAt : .infinity
        case .bossFight, .garageUpgrades:
            break
        }
        if plan.moment == .midRun { scatterTreasure(in: world, count: 5) }
        if plan.moment == .overdriveCombo { nextComboTime = t + 1.5 }
        log(String(format: "t=%.1fs set up %@ (%@) at %.0f m", t, scenario.rawValue, plan.moment.rawValue, world.depth))
    }

    /// Footage should never end on a wreck or an empty tank. A near-death
    /// clip stays low (blinking fuel, one hit from the end) but survives.
    private func keepAlive(_ world: GameWorld, plan: DirectorPlan) {
        if plan.moment == .nearDeath {
            if world.fuelFraction < 0.1 { world.fuel = world.loadout.fuelCapacity * 0.25 }
            if world.armor <= 1 { setArmor(min(2, world.loadout.armor), in: world) }
        } else {
            if world.fuelFraction < 0.4 { world.fuel = world.loadout.fuelCapacity }
            if world.armor <= 2 { setArmor(world.loadout.armor, in: world) }
        }
        if world.phase == .stalled {
            world.refillUsed = false
            world.refuelAndResume()
        }
    }

    private func script(_ scenario: Scenario, plan: DirectorPlan, world: GameWorld, t: Double) {
        if !plan.events.isEmpty, t >= nextEventTime, world.event == nil, world.phase == .drilling {
            let kind = plan.events[nextEventIndex % plan.events.count]
            nextEventIndex += 1
            trigger(kind, in: world)
            nextEventTime = scenario == .deepBiome ? .infinity : t + kind.duration + plan.eventGap
            if kind == .goldRush { scatterTreasure(in: world, count: plan.scatterCount) }
        }
        if scenario == .goldRush, t >= nextScatterTime {
            scatterTreasure(in: world, count: plan.scatterCount)
            nextScatterTime = t + plan.scatterEvery
        }
        if plan.moment == .overdriveCombo, t >= nextComboTime, world.phase == .drilling, !world.inOverdrive,
           world.bossIntro <= 0 {
            // Charge the meter close to full, then let a trail of ore ahead
            // set Overdrive off on screen.
            var guardCount = 0
            while world.overdriveCharge < 0.8, guardCount < 60 {
                world.bumpCombo(at: CGPoint(x: world.x, y: world.depth))
                guardCount += 1
            }
            scatterTreasure(in: world, count: 8)
            nextComboTime = t + world.overdriveTimeNow + liveRNG.double(5...9)
        }
        if scenario == .bossFight, !bossHPApplied, let boss = world.boss, boss.engaged, world.bossIntro <= 0 {
            bossHPApplied = true
            switch plan.bossHP {
            case "enraged": setBossHP(boss.maxHP / 2, in: world)
            case "lastLegs": setBossHP(max(1, boss.maxHP / 4), in: world)
            default: break
            }
        }
    }

    // MARK: - Autopilot

    /// Steers like a thumb on the joystick, following the rolled move plan,
    /// pulled toward the scenario's goal and away from walls and rock the
    /// bit cannot crack. Every curve is smooth (sines and easing); no
    /// per-frame noise, so the stick never jitters.
    private func autopilot(_ scenario: Scenario, plan: DirectorPlan, world: GameWorld, t: Double, dt: Double) {
        // Perk offers: pause as if reading, then tap one.
        if world.phase == .choosing {
            lift(world)
            if choosingSince == nil { choosingSince = t }
            command("perk-wait", t: t)
            if let since = choosingSince, t - since > plan.perkThink, !world.perkOffer.isEmpty {
                let perk = world.perkOffer[liveRNG.int(0...(world.perkOffer.count - 1))]
                log(String(format: "t=%.1fs autopilot: pick perk %@", t, perk.rawValue))
                world.choosePerk(perk)
                choosingSince = nil
            }
            return
        }
        choosingSince = nil
        guard world.phase == .drilling else { return }

        let fighting = world.boss.map { $0.engaged && !$0.defeated } ?? false
        let moves = plan.moves
        guard !moves.isEmpty else { return }
        let span = (moves.last.map { $0.start + $0.duration }) ?? 1
        let local = t.truncatingRemainder(dividingBy: span)
        while moveIndex < moves.count - 1, local >= moves[moveIndex].start + moves[moveIndex].duration { moveIndex += 1 }
        if local < moves[moveIndex].start { moveIndex = 0 }
        var move = moves[moveIndex]
        let u = local - move.start
        if move.kind != .swirl { swirlGoal = nil }

        // Near the surface (a ceiling) or mid-fight, no upward moves.
        if (move.kind == .swirl || move.kind == .hook), world.depth < 12 || fighting { move.kind = .sweep }
        // No thumb lifts while a boss is on the attack.
        if move.kind == .pause, fighting { move.kind = .burst }

        if move.kind == .pause {
            lift(world)
            command("lift", t: t)
            return
        }

        var push = move.push
        var goal: Double
        switch move.kind {
        case .cruise:
            goal = move.amp * sin(u * move.freq + move.phase) + 0.2 * sin(u * move.freq * 2.3 + move.phase)
        case .zigzag:
            let period = max(0.6, 2 * .pi / move.freq) * 0.9
            goal = move.side * move.amp * 1.3 * tanh(3 * sin(2 * .pi * u / period))
        case .dive:
            goal = move.side * 0.08 * sin(u * 2)
            push = 1
        case .sweep:
            goal = move.side * (0.8 + move.amp * 0.7) * sin(.pi * min(1, u / move.duration))
        case .swirl:
            // Lead the heading round a full loop; the drill's turn rate sets the curve.
            if swirlGoal == nil { swirlGoal = aim }
            swirlGoal = (swirlGoal ?? aim) + move.side * 2.6 * dt
            goal = swirlGoal ?? aim
        case .hook:
            goal = u < move.duration * 0.45 ? move.side * 2.2 : move.side * 0.3
        case .burst:
            goal = move.amp * 0.35 * sin(u * move.freq * 2 + move.phase)
            push = 1
        case .pause:
            goal = aim
        }

        var targetKind = "steer-\(move.kind.rawValue)"
        if let target = goalPoint(scenario, plan: plan, world: world, t: t) {
            // A goal (boss, ore) wins; the move only adds a small weave.
            let toward = atan2(-(target.x - world.x), target.y - world.depth)
            goal = toward + 0.25 * sin(u * move.freq + move.phase)
            targetKind = fighting ? (t < dodgeUntil ? "boss-dodge" : "steer-boss") : "steer-goal"
        }

        // Keep off the walls.
        let fromCentre = (world.x - GameWorld.shaftWidth / 2) / (GameWorld.shaftWidth / 2)
        if abs(fromCentre) > 0.55 { goal = remainder(goal, 2 * .pi) + fromCentre * 0.8 }

        // Swerve round rock the bit cannot crack.
        let forward = world.headingVector
        for rock in world.obstacles where !rock.destroyed && !world.canDrill(rock) {
            let rx = rock.x - world.x
            let ry = rock.y - world.depth
            let along = rx * forward.x + ry * forward.y
            let reach = max(rock.w, rock.h) / 2 + 1.0
            guard along > 0, along < 5, hypot(rx, ry) < 5 + reach else { continue }
            let lateral = abs(rx * forward.y - ry * forward.x)
            guard lateral < reach else { continue }
            let towardRock = atan2(-rx, ry)
            let delta = remainder(towardRock - world.heading, 2 * .pi)
            goal -= (delta >= 0 ? 1 : -1) * 1.0 * (1 - along / 5)
        }

        // Stuck (holding but not moving): turn away for a moment.
        if let check = progressCheck {
            if t - check.t >= 0.6 {
                let moved = hypot(world.x - check.x, world.depth - check.depth)
                if moved < 0.15, world.bossIntro <= 0, t >= escapeUntil {
                    escapeUntil = t + 0.9
                    escapeSide = liveRNG.chance(0.5) ? 1 : -1
                    log(String(format: "t=%.1fs autopilot: unstick", t))
                }
                progressCheck = (t, world.x, world.depth)
            }
        } else {
            progressCheck = (t, world.x, world.depth)
        }
        if t < escapeUntil {
            goal = aim + escapeSide * 1.6
            push = 1
            targetKind = "escape"
        }

        // The thumb never snaps: ease toward the goal, plus a slow tremor.
        let ease = min(1, dt * plan.ease)
        aim = remainder(aim + remainder(goal - aim, 2 * .pi) * ease, 2 * .pi)
        let tremor = plan.tremor * (sin(t * 7.3 + move.phase) + 0.4 * sin(t * 3.1))
        push = min(1, push + 0.06 * sin(t * 1.1 + move.phase))
        let angle = aim + tremor
        let vector = CGVector(dx: -sin(angle) * push, dy: cos(angle) * push)
        stick = vector
        world.isHolding = true
        world.steerVector = vector
        command(targetKind, t: t)
    }

    private func lift(_ world: GameWorld) {
        stick = nil
        world.isHolding = false
        world.steerVector = nil
    }

    // MARK: - Debug log

    /// Called from the world canvas each time it actually draws.
    func noteRender(frame: Date) {
        guard isActive else { return }
        renders += 1
        lastRenderFrame = frame
    }

    // MARK: - Offline capture (driven by DirectorRecorder)

    /// True once the screen shows virtual frame `index`: on the run screen
    /// the world canvas must have drawn the current clock date; menus have
    /// no canvas to wait for.
    func captureFrameOnScreen(_ index: Int) -> Bool {
        guard let app, app.screen == .run, app.world != nil else { return true }
        guard lastRenderFrame == clock.date else { return false }
        if captureRunFrom == nil {
            captureRunFrom = index
            log("CAPTURE world canvas from frame \(index)")
        }
        return true
    }

    /// Moves everything to virtual frame `index`: exactly 1/60 s of game time
    /// per frame. Mirrors what `GameView`'s timeline does per tick (paused
    /// or results showing: the world stands still, the frame is still taken).
    func captureAdvance(to index: Int) {
        let previous = virtualNow
        virtualNow = captureOrigin + Double(index) / Double(Self.captureFPS)
        if let app, app.screen == .run, let world = app.world, !app.isPaused, app.result == nil {
            frame(world: world, now: virtualNow)
            world.debugAdvance(seconds: virtualNow - previous)
            Audio.shared.updateRun(world, paused: false)
        }
        clock.date = Date(timeIntervalSinceReferenceDate: virtualNow)
    }

    /// Logs autopilot mode changes (the per-second line carries the stick).
    private func command(_ kind: String, t: Double) {
        guard kind != lastCommand else { return }
        lastCommand = kind
        log(String(format: "t=%.1fs autopilot: %@", t, kind))
    }

    /// Once a second: real render fps vs timeline fps, sim steps, pause
    /// state, drill and camera position, and the stick being held.
    private func logStatus(world: GameWorld, now: TimeInterval) {
        guard let start = logWindowStart else { logWindowStart = now; return }
        let window = now - start
        guard window >= 1 else { return }
        let t = now - (startTime ?? now)
        let steps = world.stepsRun - lastLoggedSteps
        let dropped = world.droppedTime - lastLoggedDropped
        let stickText = stick.map { String(format: "(%.2f,%.2f)", $0.dx, $0.dy) } ?? "lifted"
        let bossText = world.boss.map { b in
            "\(b.kind) hp=\(b.hp)/\(b.maxHP) engaged=\(b.engaged) defeated=\(b.defeated) at=(\(String(format: "%.1f,%.1f", b.x, b.y)))"
        } ?? "none"
        log(String(format: "t=%.1fs renderFps=%.1f timelineFps=%.1f simSteps/s=%.0f dropped=%.2fs "
                   + "paused=%@ phase=%@ result=%@ bossIntro=%.2f drill=(%.2f, %.2f m) camera=%.2f "
                   + "holding=%@ stick=%@ boss=%@",
                   t, Double(renders) / window, Double(timelineFrames) / window, Double(steps) / window, dropped,
                   String(describing: app?.isPaused ?? false), String(describing: world.phase),
                   String(describing: app?.result != nil), world.bossIntro,
                   world.x, world.depth, world.camera,
                   String(describing: world.isHolding), stickText, bossText))
        if timelineFrames > 0, renders == 0 {
            log("WARNING: timeline ticked \(timelineFrames)x but the world canvas did not redraw")
        }
        if let last = lastLoggedPosition, world.phase == .drilling, world.isHolding,
           abs(last.x - world.x) < 0.01, abs(last.depth - world.depth) < 0.01, abs(last.camera - world.camera) < 0.01 {
            stuckSeconds += 1
            if stuckSeconds >= 2 { log("WARNING: drill and camera have not moved for \(stuckSeconds)s while holding") }
        } else {
            stuckSeconds = 0
        }
        lastLoggedPosition = (world.x, world.depth, world.camera)
        lastLoggedSteps = world.stepsRun
        lastLoggedDropped = world.droppedTime
        timelineFrames = 0
        renders = 0
        logWindowStart = now
    }

    /// Unbuffered stderr, so lines reach `simctl launch --stderr` at once.
    func log(_ line: String) {
        FileHandle.standardError.write(Data("[Director] \(line)\n".utf8))
    }

    private func goalPoint(_ scenario: Scenario, plan: DirectorPlan, world: GameWorld, t: Double) -> CGPoint? {
        if let boss = world.boss, !boss.defeated, boss.engaged {
            guard world.bossIntro <= 0 else { return nil }
            // Just landed a hit: the boss is immune, so circle wide for a moment.
            if boss.guardTime > 0 {
                if !lastGuard { guardSide = liveRNG.chance(0.5) ? 1 : -1 }
                lastGuard = true
                return CGPoint(x: boss.x + guardSide * (boss.radius + plan.circleRadius),
                               y: boss.y - boss.radius - plan.circleRadius * 0.6)
            }
            lastGuard = false
            // Now and then back off to one side, as if dodging, then go in again.
            if t >= nextDodge {
                dodgeUntil = t + plan.dodgeFor * liveRNG.double(0.7...1.3)
                nextDodge = dodgeUntil + plan.dodgeEvery * liveRNG.double(0.6...1.4)
                dodgeSide = liveRNG.chance(0.5) ? 1 : -1
            }
            if t < dodgeUntil {
                let x = min(max(world.x + dodgeSide * 3, 1.2), GameWorld.shaftWidth - 1.2)
                return CGPoint(x: x, y: min(world.depth, boss.y) - 1.5)
            }
            return CGPoint(x: boss.x, y: boss.y)
        }
        if scenario == .goldRush || plan.moment == .overdriveCombo {
            let near = world.pickups
                .filter { !$0.collected && $0.y > world.depth - 0.5 && $0.y < world.depth + 9 }
                .min { hypot($0.x - world.x, $0.y - world.depth) < hypot($1.x - world.x, $1.y - world.depth) }
            if let near { return CGPoint(x: near.x, y: near.y) }
        }
        return nil
    }

    // MARK: - Cheats

    /// Sets the boss's remaining HP (it cannot exceed its maximum).
    func setBossHP(_ hp: Int, in world: GameWorld) {
        guard var boss = world.boss else { return }
        boss.hp = min(max(1, hp), boss.maxHP)
        world.boss = boss
    }

    func setArmor(_ armor: Int, in world: GameWorld) {
        world.armor = max(1, armor)
    }

    /// Run coins during a run, banked gold in the menus.
    func giveGold(_ amount: Int) {
        guard let app else { return }
        if app.screen == .run, let world = app.world {
            world.coins += amount
        } else {
            app.profile.gold += amount
        }
    }

    /// `offset` metres into a layer, clear of its boss arena.
    func jump(toLayer index: Int, offset: Double = 4, in world: GameWorld) {
        let i = min(max(0, index), Strata.layers.count - 1)
        let start = Strata.layers[i].startDepth
        let latest = GameWorld.bossBoundary(i) - GameWorld.arenaHeight - 30
        world.debugJump(toDepth: start + min(max(4, offset), max(4, latest - start)))
    }

    func trigger(_ kind: RunEventKind, in world: GameWorld) {
        world.debugTriggerEvent(kind)
    }

    /// Ore and the odd gem strewn along the drill's path (positions from
    /// the live stream, never the terrain `rng`).
    private func scatterTreasure(in world: GameWorld, count: Int = 7) {
        let ahead = world.headingVector
        for k in 0..<count {
            let distance = 3.5 + Double(k) * 0.9
            let x = min(max(world.x + ahead.x * distance + liveRNG.double(-1.8...1.8), 1.2), GameWorld.shaftWidth - 1.2)
            let y = world.depth + max(2.5, ahead.y * distance) + liveRNG.double(-0.8...0.8)
            let gem = k == count - 1
            world.pickups.append(Pickup(id: world.claimID(), kind: gem ? .gem : .gold, x: x, y: y,
                                        value: gem ? world.currentLayer.gemValue : world.currentLayer.goldValue,
                                        phase: liveRNG.double(0...6.28)))
        }
    }
}
#endif
