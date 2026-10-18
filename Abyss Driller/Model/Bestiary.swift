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
        BestiaryEntry(subject: .critter(.scarab), name: "Scarab", biome: 6,
                      lore: "Golden beetles that guard the ruins in threes. Where you see one, two more are close behind.",
                      tip: "The pack rushes together and weaves. Meet it bit-first, then pick off the stragglers as they scatter."),
        BestiaryEntry(subject: .critter(.wraith), name: "Tomb Wraith", biome: 6,
                      lore: "Something wrapped in linen that drifts through solid stone after anything that moves.",
                      tip: "It flickers. While it is faded you can't hit it, and it can't hit you. Strike when it turns solid."),
        BestiaryEntry(subject: .critter(.frostWisp), name: "Frost Wisp", biome: 7,
                      lore: "A breath of winter that got lost underground and drifts toward anything warm.",
                      tip: "It glows before it bursts. Pop it with the bit first, or the frost nova leaves you slow and sluggish."),
        BestiaryEntry(subject: .critter(.iceUrchin), name: "Ice Urchin", biome: 7,
                      lore: "Frozen to the spot for a thousand years, and still in a bad mood about it.",
                      tip: "Its spikes glow, then fly out in a ring. Each ring is turned a little, so look for the gap, or block with the bit."),
        BestiaryEntry(subject: .critter(.sporePuff), name: "Spore Puff", biome: 8,
                      lore: "A mushroom that has been holding its breath for a very long time.",
                      tip: "It swells up before it puffs. Pop it with the bit, or stay out of the green cloud: poison makes you leak fuel."),
        BestiaryEntry(subject: .critter(.toad), name: "Bog Toad", biome: 8,
                      lore: "Fat, patient and fond of shiny things. Its tongue is longer than it looks.",
                      tip: "When it stops and a line appears, step off the line. If the tongue catches you, it drags you in."),
        BestiaryEntry(subject: .critter(.singularity), name: "Singularity", biome: 9,
                      lore: "A pinhole in the world, small enough to fit in your pocket. Please don't.",
                      tip: "It drags you in, harder up close. Steer against it, or go bit-first and pop it before its core touches your hull."),
        BestiaryEntry(subject: .critter(.voidImp), name: "Void Imp", biome: 9,
                      lore: "A mischief of the deep dark that steps between places as easily as you step between rooms.",
                      tip: "It vanishes, then pops up beside you with a glowing ring. That pause is your chance: turn your bit toward it."),
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
        BestiaryEntry(subject: .boss(.stonePharaoh), name: "Stone Pharaoh", biome: 6,
                      lore: "The last king of a city that sank beneath the Abyss. It still guards its tomb.",
                      tip: "When a line marks your row, leave it before the eyes fire. In the sandstorm it is shielded: steer away.",
                      powers: ["Eye beam", "Scarab swarm", "Sandstorm"]),
        BestiaryEntry(subject: .boss(.frostWyrm), name: "Frost Wyrm", biome: 7,
                      lore: "An ice serpent coiled around the coldest place on Earth. Its breath freezes rock solid.",
                      tip: "Ram its head; the body only shoves. Stay off frost patches. Frost Runners or a Heat Shield beat the cold.",
                      powers: ["Ice breath", "Frost field", "Blizzard"]),
        BestiaryEntry(subject: .boss(.sporemother), name: "Sporemother", biome: 8,
                      lore: "Every mushroom in the hollow grew from her. She would like to grow one on you.",
                      tip: "Spores land where the shadows are. When a ring follows you, keep moving: roots burst up when it stops.",
                      powers: ["Spore volley", "Root snare", "Bloom"]),
        BestiaryEntry(subject: .boss(.starEater), name: "Star Eater", biome: 9,
                      lore: "At the very bottom of everything, something is swallowing the stars.",
                      tip: "Slip between the spiral arms or block them. Stay clear of the black hole. When it blinks, watch the ring: that's where it will be.",
                      powers: ["Starfall", "Black hole", "Blink strike"]),
    ]
}
