import SwiftUI

/// One page of the Field Guide: a critter or a boss. Pages unlock the first
/// time the player meets the creature; kills are counted per page.
struct BestiaryEntry: Identifiable {
    enum Subject {
        case critter(EnemyKind)
        case boss(BossKind)
    }

    let subject: Subject
    let name: String
    /// Index into `Strata.layers` of the biome it belongs to.
    let biome: Int
    let lore: String
    let tip: String
    /// Boss powers in the order they appear (the last joins when enraged).
    var powers: [String] = []

    var id: String { Self.key(subject) }
    var isBoss: Bool { if case .boss = subject { return true } else { return false } }
    var bossDrop: ShipPart? { if case .boss(let kind) = subject { return ShipPart.drop(for: kind) } else { return nil } }

    /// Stable save key: the enemy kind, or "boss." + the boss key.
    static func key(_ subject: Subject) -> String {
        switch subject {
        case .critter(let kind): return String(describing: kind)
        case .boss(let kind): return "boss." + kind.key
        }
    }

    /// Rebuilt by `reloadNames` when the in-app language changes.
    static private(set) var all: [BestiaryEntry] = critters + bosses

    static func reloadNames() {
        critters = makeCritters()
        bosses = makeBosses()
        all = critters + bosses
    }

    static private(set) var critters: [BestiaryEntry] = makeCritters()

    private static func makeCritters() -> [BestiaryEntry] { [
        BestiaryEntry(subject: .critter(.worm), name: String(localized: "Worm", bundle: .app, comment: "Field Guide creature name"), biome: 0,
                      lore: String(localized: "Sleeps in the topsoil until a drill rumbles past, then wakes up hungry and gives chase.", bundle: .app),
                      tip: String(localized: "Its head is soft: turn your bit into it. Let it touch your hull and you lose armour.", bundle: .app)),
        BestiaryEntry(subject: .critter(.mole), name: String(localized: "Mole", bundle: .app, comment: "Field Guide creature name"), biome: 0,
                      lore: String(localized: "Tunnels just under the surface. You only see the dirt it pushes up.", bundle: .app),
                      tip: String(localized: "You can't hit the mound. Wait for it to shake and pop up, then bonk it while it's above ground.", bundle: .app)),
        BestiaryEntry(subject: .critter(.bat), name: String(localized: "Bat", bundle: .app, comment: "Field Guide creature name"), biome: 1,
                      lore: String(localized: "Hangs in the shallow caves, bobbing along its favourite tunnel.", bundle: .app),
                      tip: String(localized: "When it freezes and shivers, it is about to dive. Step aside: it cannot turn mid-dive.", bundle: .app)),
        BestiaryEntry(subject: .critter(.spider), name: String(localized: "Cave Spider", bundle: .app, comment: "Field Guide creature name"), biome: 1,
                      lore: String(localized: "Hangs on a silk line from the cave roof, waiting for something to pass underneath.", bundle: .app),
                      tip: String(localized: "It drops straight down. Don't pass directly below it, or drill up into it as it climbs back.", bundle: .app)),
        BestiaryEntry(subject: .critter(.beetle), name: String(localized: "Beetle", bundle: .app, comment: "Field Guide creature name"), biome: 2,
                      lore: String(localized: "An armoured scuttler that patrols one row of the deep caves, back and forth, forever.", bundle: .app),
                      tip: String(localized: "A coral rim means your bit can't crack it yet. Upgrade Power, or just go round.", bundle: .app)),
        BestiaryEntry(subject: .critter(.centipede), name: String(localized: "Centipede", bundle: .app, comment: "Field Guide creature name"), biome: 2,
                      lore: String(localized: "A hundred legs, a dozen armour plates, and no idea where it's going.", bundle: .app),
                      tip: String(localized: "Its body hurts and turns your bit aside. Only the head is soft, so meet it head-on.", bundle: .app)),
        BestiaryEntry(subject: .critter(.spitter), name: String(localized: "Crystal Spitter", bundle: .app, comment: "Field Guide creature name"), biome: 3,
                      lore: String(localized: "Grows amber crystals on its back and flings them at anything that moves.", bundle: .app),
                      tip: String(localized: "It roots and glows before it fires. Block the shard with your bit for combo; rock stops it too.", bundle: .app)),
        BestiaryEntry(subject: .critter(.slime), name: String(localized: "Prism Slime", bundle: .app, comment: "Field Guide creature name"), biome: 3,
                      lore: String(localized: "Living crystal goo that hops toward anything shiny. Your drill is very shiny.", bundle: .app),
                      tip: String(localized: "Popping a big one splits it into two little ones. Be ready to pop those too.", bundle: .app)),
        BestiaryEntry(subject: .critter(.ember), name: String(localized: "Ember", bundle: .app, comment: "Field Guide creature name"), biome: 4,
                      lore: String(localized: "A spark that broke off the Magma Core and drifts toward heat, like your engine.", bundle: .app),
                      tip: String(localized: "It swells before it bursts. Pop it with the bit first and it's just gold.", bundle: .app)),
        BestiaryEntry(subject: .critter(.slug), name: String(localized: "Fire Slug", bundle: .app, comment: "Field Guide creature name"), biome: 4,
                      lore: String(localized: "Slow, sticky and very hot. It leaves a trail of lava wherever it crawls.", bundle: .app),
                      tip: String(localized: "Mind the puddles it leaves behind. A Heat Shield makes them harmless.", bundle: .app)),
        BestiaryEntry(subject: .critter(.jelly), name: String(localized: "Jelly", bundle: .app, comment: "Field Guide creature name"), biome: 5,
                      lore: String(localized: "Pulses slowly through the dark water-rock of the Abyss, humming with charge.", bundle: .app),
                      tip: String(localized: "When it crackles, a shock is coming. Pop it, or get outside the ring.", bundle: .app)),
        BestiaryEntry(subject: .critter(.angler), name: String(localized: "Angler", bundle: .app, comment: "Field Guide creature name"), biome: 5,
                      lore: String(localized: "Lies perfectly still with a glowing lure that looks exactly like pearl ore.", bundle: .app),
                      tip: String(localized: "If a pearl seems too easy, it is. Come in from the side, or bait the lunge and dodge.", bundle: .app)),
        BestiaryEntry(subject: .critter(.scarab), name: String(localized: "Scarab", bundle: .app, comment: "Field Guide creature name"), biome: 6,
                      lore: String(localized: "Golden beetles that guard the ruins in threes. Where you see one, two more are close behind.", bundle: .app),
                      tip: String(localized: "The pack rushes together and weaves. Meet it bit-first, then pick off the stragglers as they scatter.", bundle: .app)),
        BestiaryEntry(subject: .critter(.wraith), name: String(localized: "Tomb Wraith", bundle: .app, comment: "Field Guide creature name"), biome: 6,
                      lore: String(localized: "Something wrapped in linen that drifts through solid stone after anything that moves.", bundle: .app),
                      tip: String(localized: "It flickers. While it is faded you can't hit it, and it can't hit you. Strike when it turns solid.", bundle: .app)),
        BestiaryEntry(subject: .critter(.frostWisp), name: String(localized: "Frost Wisp", bundle: .app, comment: "Field Guide creature name"), biome: 7,
                      lore: String(localized: "A breath of winter that got lost underground and drifts toward anything warm.", bundle: .app),
                      tip: String(localized: "It glows before it bursts. Pop it with the bit first, or the frost nova leaves you slow and sluggish.", bundle: .app)),
        BestiaryEntry(subject: .critter(.iceUrchin), name: String(localized: "Ice Urchin", bundle: .app, comment: "Field Guide creature name"), biome: 7,
                      lore: String(localized: "Frozen to the spot for a thousand years, and still in a bad mood about it.", bundle: .app),
                      tip: String(localized: "Its spikes glow, then fly out in a ring. Each ring is turned a little, so look for the gap, or block with the bit.", bundle: .app)),
        BestiaryEntry(subject: .critter(.sporePuff), name: String(localized: "Spore Puff", bundle: .app, comment: "Field Guide creature name"), biome: 8,
                      lore: String(localized: "A mushroom that has been holding its breath for a very long time.", bundle: .app),
                      tip: String(localized: "It swells up before it puffs. Pop it with the bit, or stay out of the green cloud: poison makes you leak fuel.", bundle: .app)),
        BestiaryEntry(subject: .critter(.toad), name: String(localized: "Bog Toad", bundle: .app, comment: "Field Guide creature name"), biome: 8,
                      lore: String(localized: "Fat, patient and fond of shiny things. Its tongue is longer than it looks.", bundle: .app),
                      tip: String(localized: "When it stops and a line appears, step off the line. If the tongue catches you, it drags you in.", bundle: .app)),
        BestiaryEntry(subject: .critter(.singularity), name: String(localized: "Singularity", bundle: .app, comment: "Field Guide creature name"), biome: 9,
                      lore: String(localized: "A pinhole in the world, small enough to fit in your pocket. Please don't.", bundle: .app),
                      tip: String(localized: "It drags you in, harder up close. Steer against it, or go bit-first and pop it before its core touches your hull.", bundle: .app)),
        BestiaryEntry(subject: .critter(.voidImp), name: String(localized: "Void Imp", bundle: .app, comment: "Field Guide creature name"), biome: 9,
                      lore: String(localized: "A mischief of the deep dark that steps between places as easily as you step between rooms.", bundle: .app),
                      tip: String(localized: "It vanishes, then pops up beside you with a glowing ring. That pause is your chance: turn your bit toward it.", bundle: .app)),
    ] }

    static private(set) var bosses: [BestiaryEntry] = makeBosses()

    private static func makeBosses() -> [BestiaryEntry] { [
        BestiaryEntry(subject: .boss(.wormQueen), name: String(localized: "Worm Queen", bundle: .app, comment: "Field Guide creature name"), biome: 0,
                      lore: String(localized: "Mother of every worm in the topsoil. She guards the way down to the caves.", bundle: .app),
                      tip: String(localized: "Ram her head. Her body only bites while she is lunging or erupting.", bundle: .app),
                      powers: [String(localized: "Lunge", bundle: .app, comment: "Boss attack name"), String(localized: "Burrow", bundle: .app, comment: "Boss attack name"), String(localized: "Brood", bundle: .app, comment: "Boss attack name")]),
        BestiaryEntry(subject: .boss(.batMatriarch), name: String(localized: "Bat Matriarch", bundle: .app, comment: "Field Guide creature name"), biome: 1,
                      lore: String(localized: "Rules the shallow caves from the ceiling, with a swarm always on call.", bundle: .app),
                      tip: String(localized: "A missed dive leaves her dazed on the floor. For the screech, find the gap in the ring.", bundle: .app),
                      powers: [String(localized: "Dive-bomb", bundle: .app, comment: "Boss attack name"), String(localized: "Swarm", bundle: .app, comment: "Boss attack name"), String(localized: "Screech", bundle: .app, comment: "Boss attack name")]),
        BestiaryEntry(subject: .boss(.beetleTank), name: String(localized: "Beetle Tank", bundle: .app, comment: "Field Guide creature name"), biome: 2,
                      lore: String(localized: "A beetle the size of a truck, with a front plate no drill has ever cracked.", bundle: .app),
                      tip: String(localized: "Hit it from behind, or right after it slams into a wall and is dazed.", bundle: .app),
                      powers: [String(localized: "Charge", bundle: .app, comment: "Boss attack name"), String(localized: "Rock rain", bundle: .app, comment: "Boss attack name"), String(localized: "Mines", bundle: .app, comment: "Boss attack name")]),
        BestiaryEntry(subject: .boss(.crystalGolem), name: String(localized: "Crystal Golem", bundle: .app, comment: "Field Guide creature name"), biome: 3,
                      lore: String(localized: "The crystal caves, given legs and a temper.", bundle: .app),
                      tip: String(localized: "Keep your bit toward it: it blocks shards and lands hits in the same move.", bundle: .app),
                      powers: [String(localized: "Shard fan", bundle: .app, comment: "Boss attack name"), String(localized: "Shard ring", bundle: .app, comment: "Boss attack name"), String(localized: "Seekers", bundle: .app, comment: "Boss attack name")]),
        BestiaryEntry(subject: .boss(.magmaTitan), name: String(localized: "Magma Titan", bundle: .app, comment: "Field Guide creature name"), biome: 4,
                      lore: String(localized: "Wades through molten rock at the bottom of the Magma Core.", bundle: .app),
                      tip: String(localized: "Watch for the marked lanes and step out before they erupt. Heat Shield makes you immune.", bundle: .app),
                      powers: [String(localized: "Geysers", bundle: .app, comment: "Boss attack name"), String(localized: "Fireballs", bundle: .app, comment: "Boss attack name"), String(localized: "Magma flood", bundle: .app, comment: "Boss attack name")]),
        BestiaryEntry(subject: .boss(.abyssAngler), name: String(localized: "Abyss Angler", bundle: .app, comment: "Field Guide creature name"), biome: 5,
                      lore: String(localized: "The deepest thing anyone has ever found. Its lure is the last light in the Abyss.", bundle: .app),
                      tip: String(localized: "In the blackout, follow the lure. The Abyss Lantern lets you see through the dark.", bundle: .app),
                      powers: [String(localized: "Lunge", bundle: .app, comment: "Boss attack name"), String(localized: "Blackout", bundle: .app, comment: "Boss attack name"), String(localized: "Jelly swarm", bundle: .app, comment: "Boss attack name")]),
        BestiaryEntry(subject: .boss(.stonePharaoh), name: String(localized: "Stone Pharaoh", bundle: .app, comment: "Field Guide creature name"), biome: 6,
                      lore: String(localized: "The last king of a city that sank beneath the Abyss. It still guards its tomb.", bundle: .app),
                      tip: String(localized: "When a line marks your row, leave it before the eyes fire. In the sandstorm it is shielded: steer away.", bundle: .app),
                      powers: [String(localized: "Eye beam", bundle: .app, comment: "Boss attack name"), String(localized: "Scarab swarm", bundle: .app, comment: "Boss attack name"), String(localized: "Sandstorm", bundle: .app, comment: "Boss attack name")]),
        BestiaryEntry(subject: .boss(.frostWyrm), name: String(localized: "Frost Wyrm", bundle: .app, comment: "Field Guide creature name"), biome: 7,
                      lore: String(localized: "An ice serpent coiled around the coldest place on Earth. Its breath freezes rock solid.", bundle: .app),
                      tip: String(localized: "Ram its head; the body only shoves. Stay off frost patches. Frost Runners or a Heat Shield beat the cold.", bundle: .app),
                      powers: [String(localized: "Ice breath", bundle: .app, comment: "Boss attack name"), String(localized: "Frost field", bundle: .app, comment: "Boss attack name"), String(localized: "Blizzard", bundle: .app, comment: "Boss attack name")]),
        BestiaryEntry(subject: .boss(.sporemother), name: String(localized: "Sporemother", bundle: .app, comment: "Field Guide creature name"), biome: 8,
                      lore: String(localized: "Every mushroom in the hollow grew from her. She would like to grow one on you.", bundle: .app),
                      tip: String(localized: "Spores land where the shadows are. When a ring follows you, keep moving: roots burst up when it stops.", bundle: .app),
                      powers: [String(localized: "Spore volley", bundle: .app, comment: "Boss attack name"), String(localized: "Root snare", bundle: .app, comment: "Boss attack name"), String(localized: "Bloom", bundle: .app, comment: "Boss attack name")]),
        BestiaryEntry(subject: .boss(.starEater), name: String(localized: "Star Eater", bundle: .app, comment: "Field Guide creature name"), biome: 9,
                      lore: String(localized: "At the very bottom of everything, something is swallowing the stars.", bundle: .app),
                      tip: String(localized: "Slip between the spiral arms or block them. Stay clear of the black hole. When it blinks, watch the ring: that's where it will be.", bundle: .app),
                      powers: [String(localized: "Starfall", bundle: .app, comment: "Boss attack name"), String(localized: "Black hole", bundle: .app, comment: "Boss attack name"), String(localized: "Blink strike", bundle: .app, comment: "Boss attack name")]),
    ] }
}
