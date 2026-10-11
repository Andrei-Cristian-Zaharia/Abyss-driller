import SwiftUI

/// One boss guards the last stretch of each biome. Its arena is a cleared
/// `arenaHeight`-tall pocket ending at the biome boundary, sealed below by
/// bedrock until the boss dies.
nonisolated enum BossKind: CaseIterable, Hashable {
    case wormQueen      // Surface
    case batMatriarch   // Shallow Caves
    case beetleTank     // Deep Caves
    case crystalGolem   // Crystal Caves
    case magmaTitan     // Magma Core
    case abyssAngler    // The Abyss, then the cycle repeats harder

    /// Stable id for save data (boss cores).
    var key: String { String(describing: self) }

    var title: String {
        switch self {
        case .wormQueen: return "WORM QUEEN"
        case .batMatriarch: return "BAT MATRIARCH"
        case .beetleTank: return "BEETLE TANK"
        case .crystalGolem: return "CRYSTAL GOLEM"
        case .magmaTitan: return "MAGMA TITAN"
        case .abyssAngler: return "ABYSS ANGLER"
        }
    }

    var radius: Double {
        switch self {
        case .wormQueen: return 0.85
        case .batMatriarch: return 0.95
        case .beetleTank: return 1.15
        case .crystalGolem: return 1.25
        case .magmaTitan: return 1.35
        case .abyssAngler: return 1.4
        }
    }

    var baseHP: Int {
        switch self {
        case .wormQueen: return 5
        case .batMatriarch: return 7
        case .beetleTank: return 5
        case .crystalGolem: return 8
        case .magmaTitan: return 9
        case .abyssAngler: return 10
        }
    }

    var tint: Color {
        switch self {
        case .wormQueen: return Palette.worm
        case .batMatriarch: return Palette.batWing
        case .beetleTank: return Palette.beetleSheen
        case .crystalGolem: return Palette.spitter
        case .magmaTitan: return Palette.lava
        case .abyssAngler: return Palette.abyssGlow
        }
    }
}

struct Boss {
    let kind: BossKind
    /// 0 for the first lap of bosses; each later lap adds HP and speed.
    let lap: Int
    let arenaTop: Double
    let arenaBottom: Double
    var x: Double
    var y: Double
    var heading: Double
    var hp: Int
    let maxHP: Int
    var mode: EnemyMode = .patrol
    var timer = 2.0
    /// Brief immunity after each hit so one ram counts once.
    var guardTime = 0.0
    /// Knocked silly: the Beetle Tank is only vulnerable while this runs.
    var dazed = 0.0
    var hitFlash = 0.0
    var volleys = 0
    /// Magma Titan: x of each lava geyser lane, warned then erupting.
    var geysers: [Double] = []
    var engaged = false
    var defeated = false
    var segments: [CGPoint] = []
    /// Which of the three powers is in play (0...2).
    var power = 0
    /// Half HP or below: the third power joins the rotation.
    var enraged = false
    /// A repeat encounter: smaller, about half the HP, a bit faster.
    var mini = false
    var speedScale = 1.0
    var spawnTimer = 0.0
    /// Worm Queen burrow: underground and untouchable, surfacing at `mark`.
    var burrowed = false
    var mark: CGPoint?
    /// Bat Matriarch screech: ring radius, the angle of its gap, and whether
    /// it already hit this time.
    var ring: Double?
    var ringGap = 0.0
    var ringHit = false
    /// Beetle Tank mines (geode obstacles) and how long each has left.
    var mines: [BossMine] = []
    /// Abyss Angler: seconds of arena blackout left (only its lure shows).
    var blackout = 0.0

    var arenaMid: Double { (arenaTop + arenaBottom) / 2 }
    var radius: Double { kind.radius * (mini ? 0.65 : 1) }
    var title: String { (mini ? "MINI " : "") + kind.title }
}

struct BossMine {
    let id: Int
    var life: Double
}

extension GameWorld {
    static let arenaHeight = 15.0
    static let bossHitGuard = 1.4
    /// Half-width (radians) of the safe gap in the Bat Matriarch's screech.
    static let screechGap = 0.6

    /// Biome boundaries, then every 150 m below the last biome's start.
    static func bossBoundary(_ index: Int) -> Double {
        let boundaries = Strata.layers.dropFirst().map(\.startDepth) + [Strata.layers.last!.startDepth + 150]
        if index < boundaries.count { return boundaries[index] }
        return boundaries.last! + Double(index - boundaries.count + 1) * 150
    }

    static func bossKind(_ index: Int) -> BossKind {
        BossKind.allCases[index % BossKind.allCases.count]
    }

    /// True when `y` falls inside a boss arena, so generation leaves it clear.
    static func inArena(_ y: Double, pad: Double = 1) -> Bool {
        var index = 0
        while true {
            let bottom = bossBoundary(index)
            if y < bottom - arenaHeight - pad { return false }
            if y <= bottom + pad { return true }
            index += 1
        }
    }

    var bossBlocking: Bool { boss.map { !$0.defeated } ?? false }

    // MARK: - Lifecycle

    func spawnBossIfNeeded() {
        guard boss == nil || boss!.defeated else { return }
        let bottom = Self.bossBoundary(bossIndex)
        let top = bottom - Self.arenaHeight
        // Appear just before the arena scrolls into view.
        guard depth > top - viewHeightMeters * 0.7 else { return }
        let kind = Self.bossKind(bossIndex)
        let lap = bossIndex / BossKind.allCases.count
        // Beaten before (in an earlier run, or earlier in this one): it comes
        // back as a mini version — a quick, sharp fight instead of a wall.
        let mini = bossesBeaten.contains(kind) || bossKindsDefeated.contains(kind)
        let full = kind.baseHP + 2 * lap
        let hp = mini ? max(3, full / 2) : full
        var boss = Boss(kind: kind, lap: lap, arenaTop: top, arenaBottom: bottom,
                        x: Self.shaftWidth / 2, y: top + Self.arenaHeight * 0.6,
                        heading: .pi / 2, hp: hp, maxHP: hp)
        boss.mini = mini
        boss.speedScale = mini ? 1.15 : 1
        switch kind {
        case .wormQueen:
            boss.segments = (1...10).map { CGPoint(x: boss.x + 0.6 * Double($0), y: boss.y) }
        case .batMatriarch:
            boss.y = top + 4
        case .beetleTank:
            boss.y = bottom - 3
        case .crystalGolem:
            boss.y = bottom - 3.6
        case .magmaTitan:
            boss.y = bottom - 3.2
        case .abyssAngler:
            boss.y = top + Self.arenaHeight * 0.45
        }
        self.boss = boss
        bossIndex += 1
    }

    func updateBoss(_ dt: Double) {
        guard var boss, !boss.defeated else { return }
        boss.guardTime = max(0, boss.guardTime - dt)
        boss.hitFlash = max(0, boss.hitFlash - dt * 3)
        boss.dazed = max(0, boss.dazed - dt)
        boss.blackout = max(0, boss.blackout - dt)
        expireMines(&boss, dt)
        if !boss.engaged {
            guard depth > boss.arenaTop + 1 else { self.boss = boss; return }
            boss.engaged = true
            noteSighting(.boss(boss.kind), at: CGPoint(x: boss.x, y: boss.y))
            // The intro banner replaces the old shout; nothing can hurt the
            // drill while it plays.
            bossIntroLength = boss.mini ? Self.bossIntroTime.mini : Self.bossIntroTime.full
            bossIntro = bossIntroLength
            invuln = max(invuln, bossIntroLength * Self.bossIntroSlowMo + 0.3)
            if !reduceMotion { shake = max(shake, 0.6) }
            Haptics.thud()
        }
        // The boss holds still until its intro is over.
        if bossIntro > 0 {
            self.boss = boss
            return
        }
        boss.timer -= dt
        let lapSpeed = (1 + 0.15 * Double(boss.lap)) * boss.speedScale

        switch boss.kind {
        case .wormQueen: stepWormQueen(&boss, dt, lapSpeed)
        case .batMatriarch: stepBatMatriarch(&boss, dt, lapSpeed)
        case .beetleTank: stepBeetleTank(&boss, dt, lapSpeed)
        case .crystalGolem: stepCrystalGolem(&boss, dt, lapSpeed)
        case .magmaTitan: stepMagmaTitan(&boss, dt, lapSpeed)
        case .abyssAngler: stepAbyssAngler(&boss, dt, lapSpeed)
        }

        let r = boss.radius
        boss.x = min(max(boss.x, r * 0.6), Self.shaftWidth - r * 0.6)
        boss.y = min(max(boss.y, boss.arenaTop + r), boss.arenaBottom - r)
        self.boss = boss
        resolveBossContact()
    }

    private func expireMines(_ boss: inout Boss, _ dt: Double) {
        guard !boss.mines.isEmpty else { return }
        for k in boss.mines.indices { boss.mines[k].life -= dt }
        for mine in boss.mines where mine.life <= 0 { removeMine(mine.id) }
        boss.mines.removeAll { $0.life <= 0 }
    }

    private func removeMine(_ id: Int) {
        guard let index = obstacles.firstIndex(where: { $0.id == id }), !obstacles[index].destroyed else { return }
        obstacles[index].destroyed = true
        burstParticles(count: reduceMotion ? 3 : 10, kind: .chunk, color: Palette.hazard,
                       at: CGPoint(x: obstacles[index].x, y: obstacles[index].y), speed: 4)
    }

    /// Keeps the drill above the bedrock seal while the boss lives.
    func clampToArena() {
        guard let boss, !boss.defeated, depth > boss.arenaTop - 2 else { return }
        let floor = boss.arenaBottom - 0.6 - max(0, headingVector.y) * Self.bitOffset
        if depth > floor {
            depth = floor
            vy = min(vy, 0)
        }
    }

    // MARK: - Behaviours
    //
    // Every boss has three powers and uses them in rotation (`nextPower`), each
    // with a telegraph: a popup, a pause, a warning shape. Patrol between them.

    private func turn(_ boss: inout Boss, toward target: Double, rate: Double, _ dt: Double) {
        let delta = remainder(target - boss.heading, 2 * .pi)
        boss.heading = remainder(boss.heading + max(-rate * dt, min(rate * dt, delta)), 2 * .pi)
    }

    private func move(_ boss: inout Boss, speed: Double, _ dt: Double) {
        boss.x += -sin(boss.heading) * speed * dt
        boss.y += cos(boss.heading) * speed * dt
    }

    private func headingToDrill(from boss: Boss) -> Double {
        atan2(-(x - boss.x), depth - boss.y)
    }

    /// Opens with two powers; at half HP the boss enrages and adds its third.
    @discardableResult
    private func nextPower(_ boss: inout Boss) -> Int {
        let enraged = boss.hp * 2 <= boss.maxHP
        if enraged && !boss.enraged {
            boss.enraged = true
            announce("ENRAGED!", boss)
            boss.power = 2          // show off the new power straight away
            boss.volleys = 0
            return boss.power
        }
        boss.power = boss.volleys % (boss.enraged ? 3 : 2)
        boss.volleys += 1
        return boss.power
    }

    private func announce(_ text: String, _ boss: Boss, tint: Color = Palette.hazard) {
        popup(text, at: CGPoint(x: boss.x, y: boss.y - boss.radius - 0.6), tint: tint, big: true)
    }

    /// Time between powers, shrinking as the boss is worn down.
    private func patrolGap(_ boss: Boss, base: Double) -> Double {
        max(base * 0.55, base - 0.25 * Double(boss.maxHP - boss.hp)) / boss.speedScale
    }

    // MARK: Worm Queen — lunge · burrow · brood

    private func stepWormQueen(_ boss: inout Boss, _ dt: Double, _ lap: Double) {
        switch boss.mode {
        case .patrol:
            let orbit = clock * 0.9
            let target = CGPoint(x: Self.shaftWidth / 2 + cos(orbit) * 2.6,
                                 y: boss.arenaMid + sin(orbit) * 4)
            turn(&boss, toward: atan2(-(target.x - boss.x), target.y - boss.y), rate: 3, dt)
            move(&boss, speed: 4 * lap, dt)
            if boss.timer <= 0 {
                switch nextPower(&boss) {
                case 0: boss.timer = 0.7; announce("!", boss)
                case 1: boss.timer = 0.6; announce("BURROW!", boss, tint: Palette.worm)
                default: boss.timer = 0.6; announce("BROOD!", boss, tint: Palette.worm)
                }
                boss.mode = .windup
            }
        case .windup:
            if boss.power == 0 { turn(&boss, toward: headingToDrill(from: boss), rate: 6, dt) }
            move(&boss, speed: 0.6, dt)
            guard boss.timer <= 0 else { break }
            switch boss.power {
            case 0:
                boss.mode = .attack; boss.timer = 1.0
            case 1:
                // Under the dirt: untouchable, tracked by a warning ring.
                boss.burrowed = true
                boss.mark = CGPoint(x: x, y: depth)
                boss.mode = .attack; boss.timer = 1.3
                burstParticles(count: reduceMotion ? 6 : 18, kind: .dust, color: currentLayer.pebble,
                               at: CGPoint(x: boss.x, y: boss.y), speed: 5)
            default:
                spawnBrood(around: boss)
                boss.mode = .recover; boss.timer = 0.8
            }
        case .attack:
            if boss.power == 1 {
                if boss.burrowed {
                    // The ring follows the drill, then locks for the last beat.
                    if boss.timer > 0.5, let mark = boss.mark {
                        boss.mark = CGPoint(x: mark.x + (x - mark.x) * min(1, dt * 4),
                                            y: mark.y + (depth - mark.y) * min(1, dt * 4))
                    }
                    if boss.timer <= 0, let mark = boss.mark {
                        boss.burrowed = false
                        boss.mark = nil
                        boss.x = mark.x
                        boss.y = mark.y + 1.4
                        boss.heading = .pi
                        boss.segments = (1...boss.segments.count).map { CGPoint(x: mark.x, y: mark.y + 1.4 + 0.6 * Double($0)) }
                        boss.timer = 0.6
                        burstParticles(count: reduceMotion ? 8 : 26, kind: .chunk, color: currentLayer.pebble,
                                       at: mark, speed: 8)
                        if !reduceMotion { shake = max(shake, 0.7) }
                        Haptics.thud()
                    }
                } else {
                    move(&boss, speed: 10 * lap, dt)
                    if boss.timer <= 0 { boss.mode = .recover; boss.timer = 1.0 }
                }
            } else {
                turn(&boss, toward: headingToDrill(from: boss), rate: 0.8, dt)
                move(&boss, speed: 9 * lap, dt)
                if boss.timer <= 0 { boss.mode = .recover; boss.timer = 1.0 }
            }
        case .recover:
            move(&boss, speed: 2, dt)
            if boss.timer <= 0 { boss.mode = .patrol; boss.timer = patrolGap(boss, base: 2.6) }
        }
        var lead = CGPoint(x: boss.x, y: boss.y)
        for k in boss.segments.indices {
            let dx = boss.segments[k].x - lead.x, dy = boss.segments[k].y - lead.y
            let length = hypot(dx, dy)
            if length > 0.6 {
                boss.segments[k] = CGPoint(x: lead.x + dx / length * 0.6, y: lead.y + dy / length * 0.6)
            }
            lead = boss.segments[k]
        }
    }

    private func spawnBrood(around boss: Boss) {
        let alive = enemies.filter { !$0.dead && $0.kind == .worm && $0.y > boss.arenaTop && $0.y < boss.arenaBottom }
        guard alive.count < 4 else { return }
        for k in 0..<3 {
            let angle = Double(k) / 3 * 2 * .pi + clock
            let spot = CGPoint(x: min(max(boss.x + cos(angle) * 1.6, 1.2), Self.shaftWidth - 1.2),
                               y: min(max(boss.y + sin(angle) * 1.6, boss.arenaTop + 1), boss.arenaBottom - 1))
            var worm = Enemy(id: claimID(), kind: .worm, x: spot.x, y: spot.y,
                             heading: angle, homeY: spot.y, hardness: 0, speed: 3.6, phase: Double(k))
            worm.segments = (1...5).map { CGPoint(x: spot.x, y: spot.y - 0.3 * Double($0)) }
            enemies.append(worm)
            burstParticles(count: reduceMotion ? 2 : 6, kind: .chunk, color: Palette.worm, at: spot, speed: 3)
        }
    }

    // MARK: Bat Matriarch — dive · swarm · screech

    private func stepBatMatriarch(_ boss: inout Boss, _ dt: Double, _ lap: Double) {
        switch boss.mode {
        case .patrol:
            let across: Double = sin(boss.heading) < 0 ? -.pi / 2 : .pi / 2
            if boss.x < 1.6 { boss.heading = -.pi / 2 } else if boss.x > Self.shaftWidth - 1.6 { boss.heading = .pi / 2 }
            else { boss.heading = across }
            move(&boss, speed: 3 * lap, dt)
            boss.y += (boss.arenaTop + 3.5 + sin(clock * 2) * 0.6 - boss.y) * min(1, dt * 3)
            if boss.timer <= 0 {
                switch nextPower(&boss) {
                case 0:
                    boss.mode = .windup; boss.timer = 0.8; announce("!", boss)
                case 1:
                    summonBats(around: boss)
                    boss.timer = patrolGap(boss, base: 1.8)
                default:
                    boss.mode = .windup; boss.timer = 0.9; announce("SCREECH!", boss, tint: Palette.batWing)
                }
            }
        case .windup:
            guard boss.timer <= 0 else { break }
            if boss.power == 0 {
                boss.mode = .attack
                boss.timer = 1.1
                boss.heading = headingToDrill(from: boss)
            } else {
                // A shockwave ring with one gap. Slip through the gap or outrun it.
                boss.mode = .attack
                boss.timer = 2.4
                boss.ring = 0.6
                boss.ringHit = false
                boss.ringGap = atan2(depth - boss.y, x - boss.x) + .pi * 0.6 * sin(clock * 1.7)
                if !reduceMotion { shake = max(shake, 0.4) }
                Haptics.bump()
            }
        case .attack:
            if boss.power == 2 {
                boss.y += (boss.arenaTop + 3.5 - boss.y) * min(1, dt * 3)
                if var ring = boss.ring {
                    ring += 7 * lap * dt
                    boss.ring = ring
                    let distance = hypot(x - boss.x, depth - boss.y)
                    if !boss.ringHit, abs(distance - ring) < 0.5 {
                        let angle = atan2(depth - boss.y, x - boss.x)
                        let off = abs(remainder(angle - boss.ringGap, 2 * .pi))
                        if off > Self.screechGap {
                            boss.ringHit = true
                            if invuln <= 0 && !inOverdrive {
                                hurt(amount: 1, away: CGPoint(x: x - boss.x, y: depth - boss.y),
                                     chunk: Palette.batWing, at: CGPoint(x: x, y: depth))
                            }
                        }
                    }
                    if ring > 15 || boss.timer <= 0 {
                        boss.ring = nil
                        boss.mode = .patrol
                        boss.timer = patrolGap(boss, base: 2.2)
                    }
                }
            } else {
                move(&boss, speed: 9 * lap, dt)
                if boss.y >= boss.arenaBottom - boss.radius - 0.05 || boss.timer <= 0 {
                    boss.mode = .recover
                    boss.timer = 1.8
                    boss.dazed = 1.6
                    if !reduceMotion { shake = max(shake, 0.5) }
                    burstParticles(count: reduceMotion ? 6 : 18, kind: .dust, color: currentLayer.pebble,
                                   at: CGPoint(x: boss.x, y: boss.y + 0.8), speed: 5)
                }
            }
        case .recover:
            if boss.dazed <= 0 {
                boss.heading = .pi
                move(&boss, speed: 4, dt)
                if boss.y <= boss.arenaTop + 3.6 {
                    boss.mode = .patrol
                    boss.timer = patrolGap(boss, base: 2.2)
                    boss.heading = .pi / 2
                }
            }
        }
    }

    private func summonBats(around boss: Boss) {
        let alive = enemies.filter { !$0.dead && $0.kind == .bat && $0.y > boss.arenaTop && $0.y < boss.arenaBottom }
        guard alive.count < 3 else { return }
        for side in [-1.0, 1.0] {
            let spot = CGPoint(x: min(max(boss.x + side * 2, 1.4), Self.shaftWidth - 1.4), y: boss.y + 1)
            enemies.append(Enemy(id: claimID(), kind: .bat, x: spot.x, y: spot.y,
                                 heading: side < 0 ? .pi / 2 : -.pi / 2, homeY: boss.arenaTop + 6,
                                 hardness: 0, speed: 4.4, phase: Double(claimID() % 7)))
            burstParticles(count: reduceMotion ? 3 : 8, kind: .smoke, color: Palette.batWing,
                           at: spot, speed: 2)
        }
        announce("SWARM!", boss, tint: Palette.batWing)
    }

    // MARK: Beetle Tank — charge · rock rain · mines

    /// Armoured from the front: only vulnerable dazed after slamming a wall, or
    /// hit from behind.
    private func stepBeetleTank(_ boss: inout Boss, _ dt: Double, _ lap: Double) {
        let row = boss.arenaBottom - 3
        boss.y += (min(max(depth, boss.arenaTop + 3), row) - boss.y) * min(1, dt * 0.8)
        switch boss.mode {
        case .patrol:
            boss.heading = x < boss.x ? .pi / 2 : -.pi / 2
            move(&boss, speed: 1.4 * lap, dt)
            if boss.timer <= 0 {
                switch nextPower(&boss) {
                case 0: boss.timer = 0.7; announce("!", boss)
                case 1: boss.timer = 0.7; announce("ROCK RAIN!", boss, tint: Palette.drillBit)
                default: boss.timer = 0.5; announce("MINES!", boss)
                }
                boss.mode = .windup
            }
        case .windup:
            if boss.power != 2 { boss.heading = x < boss.x ? .pi / 2 : -.pi / 2 }
            guard boss.timer <= 0 else { break }
            boss.mode = .attack
            boss.spawnTimer = 0
            boss.timer = boss.power == 0 ? 3 : (boss.power == 1 ? 1.5 : 1.6)
            if boss.power == 2 { boss.heading = boss.x < Self.shaftWidth / 2 ? -.pi / 2 : .pi / 2 }
        case .attack:
            switch boss.power {
            case 0:
                move(&boss, speed: 8 * lap, dt)
                let r = boss.radius
                if boss.x <= r * 0.6 + 0.05 || boss.x >= Self.shaftWidth - r * 0.6 - 0.05 || boss.timer <= 0 {
                    boss.mode = .recover
                    boss.dazed = 2.0
                    boss.timer = 2.0
                    announce("DAZED", boss, tint: Palette.window)
                    if !reduceMotion { shake = max(shake, 0.7) }
                    Haptics.thud()
                    burstParticles(count: reduceMotion ? 6 : 20, kind: .chunk, color: currentLayer.pebble,
                                   at: CGPoint(x: boss.x, y: boss.y), speed: 6)
                }
            case 1:
                if !reduceMotion { shake = max(shake, 0.15) }
                boss.spawnTimer -= dt
                if boss.spawnTimer <= 0 {
                    boss.spawnTimer = 0.28 / lap
                    shots.append(Shot(id: claimID(), x: fx.double(1...(Self.shaftWidth - 1)), y: boss.arenaTop + 0.3,
                                      vx: 0, vy: 11, life: 2.2, style: .boulder))
                }
                if boss.timer <= 0 { boss.mode = .recover; boss.timer = 0.8 }
            default:
                move(&boss, speed: 3.6 * lap, dt)
                boss.spawnTimer -= dt
                if boss.spawnTimer <= 0 {
                    boss.spawnTimer = 0.55
                    let id = claimID()
                    obstacles.append(Obstacle(id: id, kind: .geode, x: boss.x, y: boss.y - boss.radius * 0.2,
                                              w: 0.95, h: 0.95, hardness: Int.max, angle: clock, seed: UInt64(id) | 1))
                    boss.mines.append(BossMine(id: id, life: 5))
                }
                if boss.timer <= 0 { boss.mode = .recover; boss.timer = 0.8 }
            }
        case .recover:
            if boss.timer <= 0 { boss.mode = .patrol; boss.timer = patrolGap(boss, base: 1.6) }
        }
    }

    // MARK: Crystal Golem — fan · ring · seekers

    private func stepCrystalGolem(_ boss: inout Boss, _ dt: Double, _ lap: Double) {
        let wanted: Double = x < boss.x ? .pi / 2 : -.pi / 2
        switch boss.mode {
        case .windup:
            guard boss.timer <= 0 else { break }
            let origin = CGPoint(x: boss.x, y: boss.y - 0.4)
            switch boss.power {
            case 0:
                let aim = atan2(depth - origin.y, x - origin.x)
                let count = boss.hp * 2 <= boss.maxHP ? 5 : 3
                for k in 0..<count {
                    let spread = (Double(k) - Double(count - 1) / 2) * 0.32
                    fireShot(from: origin, direction: CGPoint(x: cos(aim + spread), y: sin(aim + spread)),
                             speed: Self.shotSpeed * lap)
                }
            case 1:
                for k in 0..<12 {
                    let angle = Double(k) / 12 * 2 * .pi + clock
                    fireShot(from: origin, direction: CGPoint(x: cos(angle), y: sin(angle)), speed: 4.5 * lap)
                }
            default:
                for side in [-1.0, 1.0] {
                    shots.append(Shot(id: claimID(), x: origin.x + side * 0.6, y: origin.y,
                                      vx: side * 3, vy: -2, life: 3.6, style: .homing))
                }
            }
            boss.mode = .patrol
            boss.timer = patrolGap(boss, base: max(1.3, 2.2 - 0.2 * Double(boss.lap)))
        default:
            boss.heading = wanted
            move(&boss, speed: 1.3 * lap, dt)
            if boss.timer <= 0 {
                switch nextPower(&boss) {
                case 0: boss.timer = 0.6
                case 1: boss.timer = 0.8; announce("SHATTER!", boss, tint: Palette.spitter)
                default: boss.timer = 0.8; announce("SEEKERS!", boss, tint: Palette.spitter)
                }
                boss.mode = .windup
            }
        }
    }

    // MARK: Magma Titan — geysers · fireballs · magma flood

    private func stepMagmaTitan(_ boss: inout Boss, _ dt: Double, _ lap: Double) {
        switch boss.mode {
        case .patrol:
            boss.heading = x < boss.x ? .pi / 2 : -.pi / 2
            move(&boss, speed: 1.2 * lap, dt)
            if boss.timer <= 0 {
                switch nextPower(&boss) {
                case 0:
                    // Lanes: the drill's, plus two spread from a slow clock.
                    let offset = 2.2 + sin(clock * 1.3) * 0.6
                    boss.geysers = [x, x - offset, x + offset].map { min(max($0, 0.9), Self.shaftWidth - 0.9) }
                    boss.timer = 1.0
                    announce("ERUPTION!", boss, tint: Palette.lava)
                case 1:
                    boss.timer = 0.7
                    announce("FIREBALLS!", boss, tint: Palette.lava)
                default:
                    boss.timer = 0.6
                    announce("MAGMA FLOOD!", boss, tint: Palette.lava)
                }
                boss.mode = .windup
            }
        case .windup:
            guard boss.timer <= 0 else { break }
            switch boss.power {
            case 0:
                boss.mode = .attack
                boss.timer = 0.8
                if !reduceMotion { shake = max(shake, 0.6) }
                Haptics.thud()
            case 1:
                let origin = CGPoint(x: boss.x, y: boss.y - 0.6)
                let aim = atan2(depth - origin.y, x - origin.x)
                for k in -3...3 {
                    let angle = aim + Double(k) * 0.24
                    fireShot(from: origin, direction: CGPoint(x: cos(angle), y: sin(angle)), speed: 5.2 * lap)
                }
                boss.mode = .patrol
                boss.timer = patrolGap(boss, base: 2.2)
            default:
                // Pools warm up (warning ring) before they burn.
                for offset in [0.0, -2.6, 2.6] {
                    let px = min(max(x + offset, 1.4), Self.shaftWidth - 1.4)
                    let py = min(max(depth + 0.6, boss.arenaTop + 1.5), boss.arenaBottom - 1.5)
                    lavaPools.append(LavaPool(id: claimID(), x: px, y: py, radius: 1.05,
                                              seed: UInt64(claimID()) | 1, life: 6, warmup: 0.9))
                }
                boss.mode = .patrol
                boss.timer = patrolGap(boss, base: 2.4)
            }
        case .attack:
            if invuln <= 0, !inOverdrive, !gear.lavaImmune,
               depth > boss.arenaTop, boss.geysers.contains(where: { abs($0 - x) < 0.75 }) {
                hurt(amount: 1, away: CGPoint(x: x - boss.x, y: -1), chunk: Palette.lava,
                     at: CGPoint(x: x, y: depth))
            }
            if boss.timer <= 0 {
                boss.mode = .patrol
                boss.geysers = []
                boss.timer = patrolGap(boss, base: max(1.6, 2.6 - 0.2 * Double(boss.lap)))
            }
        case .recover:
            boss.mode = .patrol
        }
    }

    // MARK: Abyss Angler — lunge · blackout · jelly swarm

    /// Circles in the gloom with its lure out front. Lunges at the drill;
    /// blacks the arena out so only the lure gives it away; when enraged,
    /// calls up jellies.
    private func stepAbyssAngler(_ boss: inout Boss, _ dt: Double, _ lap: Double) {
        switch boss.mode {
        case .patrol:
            let orbit = clock * 0.7
            let target = CGPoint(x: Self.shaftWidth / 2 + cos(orbit) * 2.8, y: boss.arenaMid + sin(orbit) * 3.6)
            turn(&boss, toward: atan2(-(target.x - boss.x), target.y - boss.y), rate: 2.4, dt)
            move(&boss, speed: 3.4 * lap, dt)
            if boss.timer <= 0 {
                switch nextPower(&boss) {
                case 0: boss.timer = 0.8; announce("!", boss)
                case 1: boss.timer = 0.6; announce("BLACKOUT!", boss, tint: Palette.abyssGlow)
                default: boss.timer = 0.7; announce("JELLY SWARM!", boss, tint: Palette.jelly)
                }
                boss.mode = .windup
            }
        case .windup:
            if boss.power == 0 { turn(&boss, toward: headingToDrill(from: boss), rate: 5, dt) }
            move(&boss, speed: 0.5, dt)
            guard boss.timer <= 0 else { break }
            switch boss.power {
            case 0:
                boss.mode = .attack; boss.timer = 0.9
            case 1:
                // Lights out, then it comes for you in the dark.
                boss.blackout = 4.5
                boss.power = 0
                boss.mode = .windup
                boss.timer = 1.4
            default:
                spawnJellies(around: boss)
                boss.mode = .recover; boss.timer = 0.8
            }
        case .attack:
            turn(&boss, toward: headingToDrill(from: boss), rate: 0.7, dt)
            move(&boss, speed: 10 * lap, dt)
            if boss.timer <= 0 { boss.mode = .recover; boss.timer = 1.1 }
        case .recover:
            move(&boss, speed: 1.5, dt)
            if boss.timer <= 0 { boss.mode = .patrol; boss.timer = patrolGap(boss, base: 2.4) }
        }
    }

    private func spawnJellies(around boss: Boss) {
        let alive = enemies.filter { !$0.dead && $0.kind == .jelly && $0.y > boss.arenaTop && $0.y < boss.arenaBottom }
        guard alive.count < 4 else { return }
        for k in 0..<3 {
            let angle = Double(k) / 3 * 2 * .pi + clock
            let spot = CGPoint(x: min(max(boss.x + cos(angle) * 2, 1.2), Self.shaftWidth - 1.2),
                               y: min(max(boss.y + sin(angle) * 2, boss.arenaTop + 1), boss.arenaBottom - 1))
            var jelly = Enemy(id: claimID(), kind: .jelly, x: spot.x, y: spot.y,
                              heading: angle, homeY: spot.y, hardness: 0, speed: 1.8, phase: Double(k))
            jelly.awake = true
            jelly.timer = 1.5 + Double(k) * 0.4
            enemies.append(jelly)
            burstParticles(count: reduceMotion ? 2 : 6, kind: .spark, color: Palette.jelly, at: spot, speed: 3)
        }
    }

    private func fireShot(from origin: CGPoint, direction: CGPoint, speed: Double) {
        shots.append(Shot(id: claimID(), x: origin.x, y: origin.y,
                          vx: direction.x * speed, vy: direction.y * speed, life: 3.5))
    }

    // MARK: - Contact

    private func resolveBossContact() {
        // While it flinches from a hit the boss is harmless as well as immune,
        // so following up aggressively is never punished.
        guard let boss, boss.engaged, !boss.defeated, boss.guardTime <= 0, !boss.burrowed else { return }
        let bit = bitPoint
        let r = boss.radius
        let bitHit = hypot(boss.x - bit.x, boss.y - bit.y) < bitReach + r
        let hullHit = hypot(boss.x - x, boss.y - depth) < Self.bodyRadius + r * 0.9

        if bitHit {
            if bossVulnerable(boss) || inOverdrive {
                damageBoss()
            } else {
                // Clank off the armour: knocked back, no harm done.
                popup("CLANK", at: CGPoint(x: boss.x, y: boss.y - r), tint: Palette.drillBit)
                burstParticles(count: reduceMotion ? 3 : 10, kind: .spark, color: Palette.drillBit,
                               at: bit, speed: 5)
                knockBack(from: CGPoint(x: boss.x, y: boss.y))
                self.boss?.guardTime = 0.4
                Haptics.bump()
            }
            return
        }
        if hullHit && invuln <= 0 && !inOverdrive {
            hurt(amount: 1, away: CGPoint(x: x - boss.x, y: depth - boss.y),
                 chunk: boss.kind.tint, at: CGPoint(x: boss.x, y: boss.y))
            return
        }
        // The Worm Queen's body: teeth while she lunges or erupts, otherwise a
        // solid wall that shoves the drill aside. Touching her tail while she
        // circles must not cost armour, or the fight is unwinnable early on.
        if boss.kind == .wormQueen, invuln <= 0, !inOverdrive {
            let biting = boss.mode == .attack
            for (k, segment) in boss.segments.enumerated() {
                let sr = r * (0.9 - 0.04 * Double(k))
                if hypot(segment.x - x, segment.y - depth) < Self.bodyRadius + sr
                    || hypot(segment.x - bit.x, segment.y - bit.y) < bitReach + sr {
                    if biting {
                        hurt(amount: 1, away: CGPoint(x: x - segment.x, y: depth - segment.y),
                             chunk: Palette.worm, at: segment)
                    } else {
                        knockBack(from: segment)
                    }
                    return
                }
            }
        }
    }

    /// A Crystal Core shard reaching the boss. Respects the hit guard and the
    /// Beetle Tank's armour, like the bit does.
    func shotHitsBoss(at point: CGPoint) -> Bool {
        guard let boss, boss.engaged, !boss.defeated, !boss.burrowed,
              hypot(boss.x - point.x, boss.y - point.y) < boss.radius + 0.2 else { return false }
        if boss.guardTime <= 0 && (bossVulnerable(boss) || inOverdrive) {
            damageBoss()
        } else {
            burstParticles(count: reduceMotion ? 2 : 6, kind: .spark, color: Palette.drillBit, at: point, speed: 3)
        }
        return true
    }

    private func bossVulnerable(_ boss: Boss) -> Bool {
        guard boss.kind == .beetleTank else { return true }
        if boss.dazed > 0 { return true }
        // From behind: the bit is on the side the beetle is moving away from.
        let facing = -sin(boss.heading)
        return (x - boss.x) * facing < 0
    }

    private func knockBack(from point: CGPoint) {
        guard hypot(x - point.x, depth - point.y) < 4 else { return }
        let dx = x - point.x, dy = depth - point.y
        let length = max(0.01, hypot(dx, dy))
        vx = dx / length * 5
        vy = dy / length * 5
        stun = max(stun, 0.25)
    }

    private func damageBoss() {
        guard var boss else { return }
        boss.hp -= 1
        boss.guardTime = Self.bossHitGuard
        boss.hitFlash = 1
        let point = CGPoint(x: boss.x, y: boss.y)
        knockBack(from: point)
        burstParticles(count: reduceMotion ? 6 : 18, kind: .chunk, color: boss.kind.tint, at: point, speed: 7)
        if !reduceMotion { shake = max(shake, 0.55) }
        Haptics.thud()
        bumpCombo(at: point)
        // A hit only knocks a lunge or dive off course. It must not reset the
        // power rotation, or steady hits stun-lock the boss and it never gets
        // past its first power.
        if (boss.kind == .wormQueen || boss.kind == .batMatriarch) && boss.mode == .attack && boss.power == 0 {
            boss.mode = .recover
            boss.timer = 0.8
            boss.heading = remainder(headingToDrill(from: boss) + .pi, 2 * .pi)
        }
        if boss.hp <= 0 {
            boss.defeated = true
            self.boss = boss
            defeatBoss(boss)
        } else {
            popup("\(boss.hp)/\(boss.maxHP)", at: CGPoint(x: boss.x, y: boss.y - boss.radius - 0.4),
                  tint: Palette.textPrimary, big: true)
            self.boss = boss
        }
    }

    private func defeatBoss(_ boss: Boss) {
        bossesDefeated += 1
        bossKindsDefeated.append(boss.kind)
        noteBossKill(boss.kind)
        let drop = ShipPart.drop(for: boss.kind)
        if !ownedParts.contains(drop) && !bossKindsDefeated.dropLast().contains(boss.kind) {
            popup("NEW PART: \(drop.title.uppercased())", at: CGPoint(x: Self.shaftWidth / 2, y: boss.y - 2),
                  tint: drop.tint, big: true)
        }
        let point = CGPoint(x: boss.x, y: boss.y)
        let reward = currentLayer.goldValue * (8 + 4 * boss.lap) / (boss.mini ? 2 : 1)
        coins += reward
        fuel = min(loadout.fuelCapacity, fuel + Self.bossRefuel)
        for mine in boss.mines { removeMine(mine.id) }
        armor = min(loadout.armor, armor + 1)
        treasureFlash = 1
        shout("\(boss.title) DOWN  +\(reward)", tint: Palette.gold)
        for _ in 0..<(reduceMotion ? 4 : 14) {
            launchToCounter(from: CGPoint(x: point.x + fx.double(-1...1), y: point.y + fx.double(-1...1)),
                            color: Palette.gold, big: fx.chance(0.2))
        }
        burstParticles(count: reduceMotion ? 12 : 50, kind: .chunk, color: boss.kind.tint, at: point, speed: 10)
        burstParticles(count: reduceMotion ? 6 : 30, kind: .spark, color: Palette.gold, at: point, speed: 8)
        for segment in boss.segments {
            burstParticles(count: reduceMotion ? 1 : 4, kind: .chunk, color: Palette.wormShadow, at: segment, speed: 5)
        }
        // The seal crumbles.
        for k in 0..<(reduceMotion ? 6 : 18) {
            burstParticles(count: 1, kind: .chunk, color: Palette.rock(hardness: 5),
                           at: CGPoint(x: Self.shaftWidth * Double(k) / 18, y: boss.arenaBottom), speed: 4)
        }
        // Clear any summoned critters, shards and flood pools still around.
        lavaPools.removeAll { $0.life != nil }
        for index in enemies.indices where enemies[index].y > boss.arenaTop && enemies[index].y < boss.arenaBottom {
            enemies[index].dead = true
        }
        shots.removeAll()
        if !reduceMotion { shake = 1 }
        Haptics.celebrate()
        pendingPerkDelay = 1.2
    }
}
