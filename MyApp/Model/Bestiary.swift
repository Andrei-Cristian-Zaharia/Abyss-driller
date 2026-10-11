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

    static let all: [BestiaryEntry] = critters + bosses

    static let critters: [BestiaryEntry] = [
        BestiaryEntry(subject: .critter(.worm), name: "Worm", biome: 0,
                      lore: "Sleeps in the topsoil until a drill rumbles past, then wakes up hungry and gives chase.",
                      tip: "Its head is soft: turn your bit into it. Let it touch your hull and you lose armour."),
        BestiaryEntry(subject: .critter(.mole), name: "Mole", biome: 0,
                      lore: "Tunnels just under the surface. You only see the dirt it pushes up.",
                      tip: "You can't hit the mound. Wait for it to shake and pop up, then bonk it while it's above ground."),
        BestiaryEntry(subject: .critter(.bat), name: "Bat", biome: 1,
                      lore: "Hangs in the shallow caves, bobbing along its favourite tunnel.",
                      tip: "When it freezes and shivers, it is about to dive. Step aside: it cannot turn mid-dive."),
        BestiaryEntry(subject: .critter(.spider), name: "Cave Spider", biome: 1,
                      lore: "Hangs on a silk line from the cave roof, waiting for something to pass underneath.",
                      tip: "It drops straight down. Don't pass directly below it, or drill up into it as it climbs back."),
        BestiaryEntry(subject: .critter(.beetle), name: "Beetle", biome: 2,
                      lore: "An armoured scuttler that patrols one row of the deep caves, back and forth, forever.",
                      tip: "A coral rim means your bit can't crack it yet. Upgrade Power, or just go round."),
        BestiaryEntry(subject: .critter(.centipede), name: "Centipede", biome: 2,
                      lore: "A hundred legs, a dozen armour plates, and no idea where it's going.",
                      tip: "Its body hurts and turns your bit aside. Only the head is soft, so meet it head-on."),
        BestiaryEntry(subject: .critter(.spitter), name: "Crystal Spitter", biome: 3,
                      lore: "Grows amber crystals on its back and flings them at anything that moves.",
                      tip: "It roots and glows before it fires. Block the shard with your bit for combo; rock stops it too."),
        BestiaryEntry(subject: .critter(.slime), name: "Prism Slime", biome: 3,
                      lore: "Living crystal goo that hops toward anything shiny. Your drill is very shiny.",
                      tip: "Popping a big one splits it into two little ones. Be ready to pop those too."),
        BestiaryEntry(subject: .critter(.ember), name: "Ember", biome: 4,
                      lore: "A spark that broke off the Magma Core and drifts toward heat, like your engine.",
                      tip: "It swells before it bursts. Pop it with the bit first and it's just gold."),
        BestiaryEntry(subject: .critter(.slug), name: "Fire Slug", biome: 4,
                      lore: "Slow, sticky and very hot. It leaves a trail of lava wherever it crawls.",
                      tip: "Mind the puddles it leaves behind. A Heat Shield makes them harmless."),
        BestiaryEntry(subject: .critter(.jelly), name: "Jelly", biome: 5,
                      lore: "Pulses slowly through the dark water-rock of the Abyss, humming with charge.",
                      tip: "When it crackles, a shock is coming. Pop it, or get outside the ring."),
        BestiaryEntry(subject: .critter(.angler), name: "Angler", biome: 5,
                      lore: "Lies perfectly still with a glowing lure that looks exactly like pearl ore.",
                      tip: "If a pearl seems too easy, it is. Come in from the side, or bait the lunge and dodge."),
    ]

    static let bosses: [BestiaryEntry] = [
        BestiaryEntry(subject: .boss(.wormQueen), name: "Worm Queen", biome: 0,
                      lore: "Mother of every worm in the topsoil. She guards the way down to the caves.",
                      tip: "Ram her head. Her body only bites while she is lunging or erupting.",
                      powers: ["Lunge", "Burrow", "Brood"]),
        BestiaryEntry(subject: .boss(.batMatriarch), name: "Bat Matriarch", biome: 1,
                      lore: "Rules the shallow caves from the ceiling, with a swarm always on call.",
                      tip: "A missed dive leaves her dazed on the floor. For the screech, find the gap in the ring.",
                      powers: ["Dive-bomb", "Swarm", "Screech"]),
        BestiaryEntry(subject: .boss(.beetleTank), name: "Beetle Tank", biome: 2,
                      lore: "A beetle the size of a truck, with a front plate no drill has ever cracked.",
                      tip: "Hit it from behind, or right after it slams into a wall and is dazed.",
                      powers: ["Charge", "Rock rain", "Mines"]),
        BestiaryEntry(subject: .boss(.crystalGolem), name: "Crystal Golem", biome: 3,
                      lore: "The crystal caves, given legs and a temper.",
                      tip: "Keep your bit toward it: it blocks shards and lands hits in the same move.",
                      powers: ["Shard fan", "Shard ring", "Seekers"]),
        BestiaryEntry(subject: .boss(.magmaTitan), name: "Magma Titan", biome: 4,
                      lore: "Wades through molten rock at the bottom of the Magma Core.",
                      tip: "Watch for the marked lanes and step out before they erupt. Heat Shield makes you immune.",
                      powers: ["Geysers", "Fireballs", "Magma flood"]),
        BestiaryEntry(subject: .boss(.abyssAngler), name: "Abyss Angler", biome: 5,
                      lore: "The deepest thing anyone has ever found. Its lure is the last light in the Abyss.",
                      tip: "In the blackout, follow the lure. The Abyss Lantern lets you see through the dark.",
                      powers: ["Lunge", "Blackout", "Jelly swarm"]),
    ]
}
