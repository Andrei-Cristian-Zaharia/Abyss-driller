#if DEBUG
import SwiftUI

// MARK: - Director mode (Debug builds only)
//
// Scripted scenarios for recording gameplay footage, e.g. in CI:
//
//   -scenario bossFight|goldRush|caveIn|deepBiome|garageUpgrades
//   -scenarioDuration 35        seconds of autopilot, then the app idles
//   -scenarioLayer 9            deepBiome: which `Strata.layers` index (default: the last)
//   -scenarioBoss 3             bossFight: which boss index (default: Crystal Golem)
//
// Launch arguments of the form `-key value` land in `UserDefaults`, which is
// how they are read here. A directed launch skips ads, consent and the
// cloud save, starts from a fresh in-memory profile and never saves it, so
// it cannot touch real progress. Nothing in this file ships: the whole file
// is compiled out of Release.

enum Scenario: String, CaseIterable {
    case bossFight, goldRush, caveIn, deepBiome, garageUpgrades
}

final class Director {
    static let shared = Director()

    let scenario: Scenario?
    let duration: Double
    let layerChoice: Int?
    let bossChoice: Int?

    var isActive: Bool { scenario != nil }

    /// Joystick deflection the autopilot is holding (unit length at most),
    /// or nil when the thumb is "lifted". `GameView` draws it like a real stick.
    private(set) var stick: CGVector?
    /// Where the autopilot's thumb rests, as a fraction of the play area.
    private(set) var stickAnchor = CGPoint(x: 0.5, y: 0.78)

    private weak var app: AppModel?
    private var startTime: TimeInterval?
    private var lastTime: TimeInterval?
    private var setUpWorld: ObjectIdentifier?
    private var finished = false
    private var aim = 0.0
    private var phases: [Double] = (0..<4).map { _ in Double.random(in: 0...(2 * .pi)) }
    private var liftUntil = 0.0
    private var nextLift = 0.0
    private var choosingSince: Double?
    private var nextEventTime = 0.0
    private var nextScatterTime = 0.0

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
        scenario = defaults.string(forKey: "scenario").flatMap(Scenario.init(rawValue:))
        let seconds = defaults.double(forKey: "scenarioDuration")
        duration = seconds > 0 ? seconds : 35
        layerChoice = defaults.object(forKey: "scenarioLayer") != nil ? defaults.integer(forKey: "scenarioLayer") : nil
        bossChoice = defaults.object(forKey: "scenarioBoss") != nil ? defaults.integer(forKey: "scenarioBoss") : nil
    }

    // MARK: - Start

    /// Called once from `ContentView` when the app appears.
    func begin(app: AppModel) {
        guard let scenario, self.app == nil else { return }
        self.app = app
        log("begin scenario=\(scenario.rawValue) duration=\(duration)s")
        // The duration covers the whole scenario, menus included.
        startTime = Date().timeIntervalSinceReferenceDate
        switch scenario {
        case .garageUpgrades:
            runGarageScript(app)
        case .bossFight, .goldRush, .caveIn, .deepBiome:
            // A late-game rig (Power bores hardness 11, so even Void rock
            // cracks): deep layers and bosses don't stall the footage.
            for track in UpgradeTrack.allCases {
                app.profile.levels[track] = max(app.profile.levels[track], 10)
            }
            app.startRun()
        }
    }

    /// The garage half of `garageUpgrades`: buy and upgrade a few parts on
    /// screen, top up the Workshop, then drill with the new rig.
    private func runGarageScript(_ app: AppModel) {
        giveGold(150_000)
        app.screen = .garage
        Task { @MainActor in
            func beat(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
            await beat(1.6)
            app.buy(ShipPart.heavyBit)
            await beat(1.9)
            app.upgrade(ShipPart.heavyBit)
            await beat(1.9)
            app.upgrade(ShipPart.heavyBit)
            await beat(1.9)
            app.buy(ShipPart.sportTracks)
            await beat(1.9)
            app.buy(ShipPart.magnetCoil)
            await beat(1.6)
            for track in UpgradeTrack.allCases {
                for _ in 0..<3 { app.buy(track) }
            }
            await beat(1.2)
            app.startRun()
        }
    }

    // MARK: - Per frame

    /// Called by `GameView` every frame, before the world ticks.
    func frame(world: GameWorld, now: TimeInterval) {
        guard let scenario else { return }
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
            setUp(scenario, world: world, t: t)
        }
        keepAlive(world)
        script(scenario, world: world, t: t)
        autopilot(scenario, world: world, t: t, dt: dt)
    }

    private func setUp(_ scenario: Scenario, world: GameWorld, t: Double) {
        aim = world.heading
        nextLift = t + Double.random(in: 5...8)
        switch scenario {
        case .bossFight:
            spawnBoss(index: bossChoice ?? 3, in: world)
        case .goldRush:
            jump(toLayer: 2, in: world)          // Deep Caves: real gold ore
            world.loadout.cargoSlots = max(world.loadout.cargoSlots, 80)
            trigger(.goldRush, in: world)
            nextEventTime = t + RunEventKind.goldRush.duration + 0.4
            nextScatterTime = t + 1.5
        case .caveIn:
            jump(toLayer: 3, in: world)          // Crystal Caves
            trigger(.caveIn, in: world)
            nextEventTime = t + RunEventKind.caveIn.duration + 0.8
        case .deepBiome:
            jump(toLayer: layerChoice ?? (Strata.layers.count - 1), in: world)
        case .garageUpgrades:
            break                                // a normal run with the new rig
        }
    }

    /// Footage should never end on a wreck or an empty tank.
    private func keepAlive(_ world: GameWorld) {
        if world.fuelFraction < 0.4 { world.fuel = world.loadout.fuelCapacity }
        if world.armor <= 2 { setArmor(world.loadout.armor, in: world) }
        if world.phase == .stalled {
            world.refillUsed = false
            world.refuelAndResume()
        }
    }

    private func script(_ scenario: Scenario, world: GameWorld, t: Double) {
        switch scenario {
        case .goldRush:
            if t >= nextEventTime, world.event == nil {
                trigger(.goldRush, in: world)
                nextEventTime = t + RunEventKind.goldRush.duration + 0.4
            }
            if t >= nextScatterTime {
                scatterTreasure(in: world)
                nextScatterTime = t + 1.8
            }
        case .caveIn:
            if t >= nextEventTime, world.event == nil {
                trigger(.caveIn, in: world)
                nextEventTime = t + RunEventKind.caveIn.duration + 0.8
            }
        case .bossFight, .deepBiome, .garageUpgrades:
            break
        }
    }

    // MARK: - Autopilot

    /// Steers like a thumb on the joystick: a slow wander with small random
    /// wobble, pulled toward the scenario's goal and away from walls and
    /// rock the bit cannot crack.
    private func autopilot(_ scenario: Scenario, world: GameWorld, t: Double, dt: Double) {
        // Perk offers: pause as if reading, then tap one.
        if world.phase == .choosing {
            stick = nil
            world.isHolding = false
            world.steerVector = nil
            if choosingSince == nil { choosingSince = t }
            command("perk-wait", t: t)
            if let since = choosingSince, t - since > 1.4, let perk = world.perkOffer.randomElement() {
                log(String(format: "t=%.1fs autopilot: pick perk %@", t, String(describing: perk)))
                world.choosePerk(perk)
                choosingSince = nil
            }
            return
        }
        choosingSince = nil
        guard world.phase == .drilling else { return }

        let fighting = world.boss.map { $0.engaged && !$0.defeated } ?? false

        // An occasional short lift of the thumb, as players do (not mid-fight).
        if !fighting, t >= nextLift {
            liftUntil = t + Double.random(in: 0.18...0.35)
            nextLift = t + Double.random(in: 5...9)
            stickAnchor = CGPoint(x: 0.5 + Double.random(in: -0.12...0.12), y: 0.76 + Double.random(in: -0.04...0.04))
        }
        if t < liftUntil {
            stick = nil
            world.isHolding = false
            world.steerVector = nil
            command("lift", t: t)
            return
        }

        // Base: drill downward with a lazy weave.
        var goal = 0.55 * sin(t * 0.65 + phases[0]) + 0.25 * sin(t * 1.7 + phases[1])
        if let target = goalPoint(scenario, world: world) {
            goal = atan2(-(target.x - world.x), target.y - world.depth)
        }

        // Keep off the walls.
        let fromCentre = (world.x - GameWorld.shaftWidth / 2) / (GameWorld.shaftWidth / 2)
        if abs(fromCentre) > 0.55 { goal += fromCentre * 0.7 }

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

        // The thumb never snaps: ease toward the goal, plus a little tremor.
        let ease = min(1, dt * 3.2)
        aim = remainder(aim + remainder(goal - aim, 2 * .pi) * ease, 2 * .pi)
        let tremor = 0.06 * sin(t * 7.3 + phases[2]) + Double.random(in: -0.02...0.02)
        let push = 0.78 + 0.18 * sin(t * 1.1 + phases[3])
        let angle = aim + tremor
        let vector = CGVector(dx: -sin(angle) * push, dy: cos(angle) * push)
        stick = vector
        world.isHolding = true
        world.steerVector = vector
        command(fighting ? "steer-boss" : (goalPoint(scenario, world: world) != nil ? "steer-goal" : "steer-wander"), t: t)
    }

    // MARK: - Debug log

    /// Called from the world canvas each time it actually draws.
    func noteRender(frame: Date) {
        guard isActive else { return }
        renders += 1
        lastRenderFrame = frame
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
    private func log(_ line: String) {
        FileHandle.standardError.write(Data("[Director] \(line)\n".utf8))
    }

    private func goalPoint(_ scenario: Scenario, world: GameWorld) -> CGPoint? {
        if let boss = world.boss, !boss.defeated, boss.engaged {
            guard world.bossIntro <= 0 else { return nil }
            // Just landed a hit: the boss is immune, so circle wide for a moment.
            if boss.guardTime > 0 {
                let side: Double = world.x < boss.x ? -1 : 1
                return CGPoint(x: boss.x + side * (boss.radius + 2.5), y: boss.y - boss.radius - 1.5)
            }
            return CGPoint(x: boss.x, y: boss.y)
        }
        if scenario == .goldRush {
            let near = world.pickups
                .filter { !$0.collected && $0.y > world.depth - 0.5 && $0.y < world.depth + 9 }
                .min { hypot($0.x - world.x, $0.y - world.depth) < hypot($1.x - world.x, $1.y - world.depth) }
            if let near { return CGPoint(x: near.x, y: near.y) }
        }
        return nil
    }

    // MARK: - Cheats

    /// Lands just above boss `index`'s arena so its intro and fight follow.
    func spawnBoss(index: Int, in world: GameWorld) {
        let top = GameWorld.bossBoundary(max(0, index)) - GameWorld.arenaHeight
        world.debugJump(toDepth: top - 9)
    }

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

    func jump(toDepth depth: Double, in world: GameWorld) {
        world.debugJump(toDepth: depth)
    }

    /// A few metres into a layer, past its boss arena.
    func jump(toLayer index: Int, in world: GameWorld) {
        let layer = Strata.layers[min(max(0, index), Strata.layers.count - 1)]
        world.debugJump(toDepth: layer.startDepth + 4)
    }

    func trigger(_ kind: RunEventKind, in world: GameWorld) {
        world.debugTriggerEvent(kind)
    }

    /// Ore and the odd gem strewn along the drill's path.
    private func scatterTreasure(in world: GameWorld) {
        let ahead = world.headingVector
        for k in 0..<7 {
            let distance = 3.5 + Double(k) * 0.9
            let x = min(max(world.x + ahead.x * distance + Double.random(in: -1.8...1.8), 1.2), GameWorld.shaftWidth - 1.2)
            let y = world.depth + max(2.5, ahead.y * distance) + Double.random(in: -0.8...0.8)
            let gem = k == 6
            world.pickups.append(Pickup(id: world.claimID(), kind: gem ? .gem : .gold, x: x, y: y,
                                        value: gem ? world.currentLayer.gemValue : world.currentLayer.goldValue,
                                        phase: Double.random(in: 0...6.28)))
        }
    }
}
#endif
