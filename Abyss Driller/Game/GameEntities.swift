import SwiftUI

// All positions are in world metres. `y` grows downward and equals depth.

enum ObstacleKind {
    case boulder   // chunky round rock — the common one
    case slab      // wide flat granite — blocks a lane
    case geode     // spiked crystal — never drillable, always hurts

    /// Base hardness before the depth bonus. Geodes are not rock.
    var baseHardness: Int {
        switch self {
        case .boulder: return 1
        case .slab: return 2
        case .geode: return Int.max
        }
    }

    var damage: Int {
        switch self {
        case .boulder, .slab: return 1
        case .geode: return 2
        }
    }
}

struct Obstacle: Identifiable {
    let id: Int
    let kind: ObstacleKind
    var x: Double
    var y: Double
    var w: Double
    var h: Double
    /// `Int.max` means "no drill will ever get through this".
    var hardness: Int
    var angle: Double
    var seed: UInt64
    var hitFlash: Double = 0
    var destroyed = false
    /// The hull came within near-miss range; pays out once it pulls clear.
    var skimmed = false
    /// Near miss already scored (or forfeited by a hit).
    var passed = false

    func isDrillable(power: Int) -> Bool { hardness <= power }

    /// Loose bounding box used for broad-phase checks and slab collision.
    var bounds: CGRect {
        CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)
    }
}

enum PickupKind {
    case gold
    case gem
    case fuel      // canister — tops the tank up, takes no hold space

    /// Cargo slots consumed.
    var slots: Int {
        switch self {
        case .gold: return 1
        case .gem: return 2
        case .fuel: return 0
        }
    }
}

struct Pickup: Identifiable {
    let id: Int
    let kind: PickupKind
    var x: Double
    var y: Double
    var value: Int
    var phase: Double        // bob/spin offset so a cluster is not in lockstep
    /// Nuggets laid out as one weaving trail share an id; sweeping the whole
    /// trail pays a bonus.
    var trail: Int? = nil
    var collected = false
    /// Briefly non-zero when the hold was full and the pickup was left behind.
    var deniedFlash: Double = 0
}

/// A cleared pocket of rock holding a chest, placed just past the player's best.
struct Chamber: Identifiable {
    let id: Int
    var x: Double
    var y: Double
    var radius: Double
    var reward: Int
    var opened = false
    var openT: Double = 0
}

/// One signature critter per biome; deeper biomes mix in the earlier ones.
enum EnemyKind {
    case worm      // Surface — wakes up and chases; the bit kills it outright
    case bat       // Shallow Caves — hovers, then telegraphs and dive-bombs
    case beetle    // Deep Caves — armoured, scuttles across; hardness like rock
    case spitter   // Crystal Caves — crawls and fires crystal shards
    case ember     // Magma Core — drifts in, swells, and bursts
    case jelly     // The Abyss — drifts close, crackles, releases a shock ring
    case angler    // The Abyss — hides behind an ore-like lure, then lunges
    case mole      // Surface — tunnels unseen, pops up and lunges
    case spider    // Shallow Caves — dangles on silk, drops on whatever passes below
    case centipede // Deep Caves — zig-zags across; armoured body, only the head is soft
    case slime     // Crystal Caves — hops in; splits in two when popped
    case slug      // Magma Core — crawls a row leaving short-lived lava
    case scarab    // Ancient Ruins — comes in packs of three that rush together, then scatter
    case wraith    // Ancient Ruins — drifts after the drill, flickering in and out of the world
    case frostWisp // Frozen Depths — drifts in, glows, bursts in a nova that chills the drill
    case iceUrchin // Frozen Depths — rooted in the ice, fires a ring of icicles
    case sporePuff // Spore Hollow — a mushroom that puffs out a lingering poison cloud
    case toad      // Spore Hollow — hops in, aims, and yanks the drill with its tongue
    case singularity // The Void — a tiny black hole that pulls the drill in
    case voidImp   // The Void — teleports beside the drill, pauses, then lunges

    var radius: Double {
        switch self {
        case .worm: return 0.42
        case .bat: return 0.4
        case .beetle: return 0.55
        case .spitter: return 0.5
        case .ember: return 0.38
        case .jelly: return 0.45
        case .angler: return 0.5
        case .mole: return 0.42
        case .spider: return 0.4
        case .centipede: return 0.36
        case .slime: return 0.5
        case .slug: return 0.45
        case .scarab: return 0.34
        case .wraith: return 0.48
        case .frostWisp: return 0.4
        case .iceUrchin: return 0.5
        case .sporePuff: return 0.48
        case .toad: return 0.5
        case .singularity: return 0.42
        case .voidImp: return 0.4
        }
    }
}

enum EnemyMode { case patrol, windup, attack, recover }

/// Burrowing critters. They move through soil and rock alike. Hitting one with
/// the bit kills it (if Power beats its hardness); touching the hull hurts.
struct Enemy: Identifiable {
    let id: Int
    let kind: EnemyKind
    var x: Double
    var y: Double
    /// Same convention as the drill: 0 points down, direction is (-sin, cos).
    var heading: Double
    /// Patrol row the critter drifts back to when it is not chasing.
    var homeY: Double
    var hardness: Int
    var speed: Double
    var phase: Double
    var awake = false
    var chasing = false
    var mode: EnemyMode = .patrol
    /// Counts down the current mode (windup, dive, cooldown between shots).
    var timer = 0.0
    /// Multiplies `speed` — a bat diving or a spitter rooted to fire.
    var pace = 1.0
    var stun = 0.0
    var hitFlash = 0.0
    var dead = false
    /// Worm body, head first. Each segment trails the one before it.
    var segments: [CGPoint] = []
    /// A slime that already split: smaller, and does not split again.
    var small = false

    func isKillable(power: Int) -> Bool { hardness <= power }

    /// Collision and drawing radius (split slimes are smaller).
    var radius: Double { kind.radius * (small ? 0.6 : 1) }

    /// Moles are only touchable while above ground (popping up or lingering);
    /// a wraith only while it is solid (`.recover` is its faded phase).
    var surfaced: Bool {
        switch kind {
        case .mole: return mode == .attack || mode == .recover
        case .wraith: return mode != .recover
        default: return true
        }
    }
}

enum ShotStyle {
    case crystal    // a spitter's (or the Golem's) shard
    case friendly   // the player's Crystal Core
    case boulder    // a cave-in rock falling from above
    case homing     // the Crystal Golem's seeker: steers after the drill
    case frost      // an icicle shard: like a crystal, and it chills on a hit
    case icicle     // the Frost Wyrm's blizzard: falls like a boulder, smashed by the bit
    case spore      // the Sporemother's lobbed spore: no contact, bursts into a cloud where it lands
    case star       // the Star Eater's spiral bolt: like a crystal shard
}

/// Projectiles. Crystal shards are blocked by the bit and stopped by rock;
/// boulders are smashed by the bit; friendly shards hunt critters and rock.
struct Shot: Identifiable {
    let id: Int
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var life: Double
    var style: ShotStyle = .crystal

    var friendly: Bool { style == .friendly }
}

/// A molten pocket in the Magma Core. Not solid: it burns on contact.
struct LavaPool: Identifiable {
    let id: Int
    var x: Double
    var y: Double
    var radius: Double
    var seed: UInt64
    /// Boss-made pools expire; terrain pools are permanent (nil).
    var life: Double? = nil
    /// Seconds of warning before a new pool starts to burn.
    var warmup = 0.0
    /// A Frost Wyrm frost patch: chills instead of burning (Heat Shield melts it).
    var frost = false
    /// A poison cloud (spore puffs, the Sporemother): poisons instead of burning.
    var poison = false
}

/// Non-interactive background rock, and turquoise crystals in the deep layer.
struct Decor: Identifiable {
    enum Kind { case pebble, crystal, vein, blotch, ruin, drift, shroom, star }
    let id: Int
    let kind: Kind
    var x: Double
    var y: Double
    var size: Double
    var angle: Double
    var seed: UInt64
}

enum ParticleKind { case dust, chunk, spark, smoke }

struct Particle {
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var life: Double
    var maxLife: Double
    var size: Double
    var angle: Double
    var spin: Double
    var color: Color
    var kind: ParticleKind
}

/// Collected treasure flying to the HUD counter. Lives in screen points,
/// because that is where it has to land.
struct FlyingValue: Identifiable {
    let id: Int
    var from: CGPoint
    var control: CGPoint
    var to: CGPoint
    var t: Double = 0
    var color: Color
    var big = false
}

/// Small world-space text that pops off the drill ("+12", "CLOSE!").
struct Popup: Identifiable {
    let id: Int
    var x: Double
    var y: Double
    var text: String
    var tint: Color
    var big = false
    var t: Double = 0
}

/// Short-lived banner over the play area ("NEW RECORD", "TREASURE!").
struct Shout: Identifiable {
    let id: Int
    var text: String
    var tint: Color
    var t: Double = 0
}
