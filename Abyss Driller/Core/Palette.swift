import SwiftUI

extension Color {
    /// Flat palette colours are authored as 0xRRGGBB literals.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// The whole game draws from this list. Nothing else should invent a colour.
enum Palette {
    static let background = Color(hex: 0x101827)   // midnight navy
    static let panel = Color(hex: 0x1E293B)        // slate blue
    static let panelRaised = Color(hex: 0x27364E)  // slate blue, lifted
    static let panelSunken = Color(hex: 0x16202F)

    static let drillBody = Color(hex: 0xFFC83D)    // construction yellow
    static let drillShadow = Color(hex: 0xD99116)  // amber
    static let drillBit = Color(hex: 0xCBD5E1)     // silver
    static let drillBitShadow = Color(hex: 0x94A3B8)
    static let window = Color(hex: 0x45D6CF)       // turquoise
    static let exhaust = Color(hex: 0xF97316)      // small orange exhaust
    static let track = Color(hex: 0x2E3648)        // dark rubber belt
    static let trackBlock = Color(hex: 0x4B5770)   // tread blocks catching light
    static let trackWheel = Color(hex: 0x616E8A)   // sprockets and road wheels
    static let crate = Color(hex: 0x805238)        // cargo crate timber
    static let trackTread = Color(hex: 0x222A3B)

    static let mint = Color(hex: 0x34D399)         // primary buttons
    static let mintShadow = Color(hex: 0x1F9E73)
    static let gold = Color(hex: 0xFFD85A)         // gold collectibles
    static let goldShadow = Color(hex: 0xE0A82E)
    static let gem = Color(hex: 0xB794FF)          // rare gems
    static let gemShadow = Color(hex: 0x8B5CF6)
    static let hazard = Color(hex: 0xFF6B6B)       // hazards and damage
    static let hazardShadow = Color(hex: 0xD14B4B)

    static let worm = Color(hex: 0xF28CB1)         // burrowing worm
    static let wormShadow = Color(hex: 0xC25E86)
    static let wormBelly = Color(hex: 0xFBC4D6)
    static let beetle = Color(hex: 0x2B3245)       // armoured beetle shell
    static let beetleSheen = Color(hex: 0x6B7FA8)
    static let beetleEye = Color(hex: 0xFFB020)

    static let bat = Color(hex: 0x4A3B63)          // cave bat
    static let batWing = Color(hex: 0x6E5A90)
    static let spitter = Color(hex: 0xFFA94D)      // amber crystal spitter
    static let spitterShadow = Color(hex: 0xD9731F)

    static let lava = Color(hex: 0xFF7A2F)         // molten pools and the Titan
    static let lavaGlow = Color(hex: 0xFFC15A)
    static let lavaCrust = Color(hex: 0x6B2418)
    static let ember = Color(hex: 0xFFB347)        // ember sprite
    static let abyssGlow = Color(hex: 0x7CF5C8)    // bioluminescence in the Abyss
    static let jelly = Color(hex: 0x8FE3F0)        // abyss jelly bell
    static let jellyShadow = Color(hex: 0x3E9FB5)
    static let mole = Color(hex: 0x8A6145)         // surface mole
    static let moleNose = Color(hex: 0xF7A6B5)
    static let spider = Color(hex: 0x3B2E4F)       // cave spider
    static let centipede = Color(hex: 0xB0442F)    // centipede plates
    static let centipedeShade = Color(hex: 0x7A2A1E)
    static let slime = Color(hex: 0xE8A8FF)        // prism slime
    static let slimeShade = Color(hex: 0xB374D6)
    static let slug = Color(hex: 0xE8622A)         // fire slug
    static let slugSpot = Color(hex: 0xFFB15A)
    static let angler = Color(hex: 0x23404F)       // angler body
    static let anglerBelly = Color(hex: 0x3A6373)
    static let scarab = Color(hex: 0xF2B83A)        // ruins scarab shell
    static let scarabShadow = Color(hex: 0xA8711C)
    static let wraith = Color(hex: 0xE8E2C6)        // tomb wraith wrappings
    static let wraithShadow = Color(hex: 0xA79F80)
    static let jade = Color(hex: 0x6FE0A2)          // glow in the Ancient Ruins
    static let pharaoh = Color(hex: 0xE3B04B)       // the Stone Pharaoh's sandstone gold
    static let lapis = Color(hex: 0x3A62C9)         // its headdress stripes
    static let frost = Color(hex: 0x9FE4FF)         // chill, frost shards, frost patches
    static let frostShadow = Color(hex: 0x4C9CC8)
    static let wisp = Color(hex: 0xDDF6FF)          // frost wisp
    static let urchin = Color(hex: 0x5E7FCB)        // ice urchin body
    static let wyrm = Color(hex: 0x8ED6F0)          // frost wyrm scales
    static let wyrmShadow = Color(hex: 0x3F7FA8)
    static let spore = Color(hex: 0xB6F25A)         // poison clouds, spores, the Spore Hollow glow
    static let sporeShadow = Color(hex: 0x6E9E2A)
    static let mushroomCap = Color(hex: 0xC2463E)   // spore puff and Sporemother caps
    static let mushroomStem = Color(hex: 0xEADFC4)
    static let toad = Color(hex: 0x5E9E4A)          // bog toad
    static let toadBelly = Color(hex: 0xE8D27A)
    static let void = Color(hex: 0x2A1F4D)          // Star Eater body, singularity core
    static let voidGlow = Color(hex: 0xB48CFF)      // gravity rings, star bolts, the Void's glow
    static let starlight = Color(hex: 0xF2E9FF)
    static let imp = Color(hex: 0x7A4FD0)           // void imp

    /// Line work: one warm near-black for every outline in the world, so the
    /// art reads as drawn by one hand.
    static let ink = Color(hex: 0x1B1424)
    /// Paper-ish highlight used for hand-placed shine chips (not pure white).
    static let shine = Color(hex: 0xFFF6E0)
    /// Field Guide pages.
    static let paper = Color(hex: 0xEFE2C4)
    static let paperShade = Color(hex: 0xD9C8A2)

    static let textPrimary = Color(hex: 0xF8FAFC)  // warm white
    static let textSecondary = Color(hex: 0xA8B3C7) // pale slate

    /// Lit face of a rock — the light in this world comes from the top left.
    static func rockLight(hardness: Int) -> Color {
        switch min(max(hardness, 1), 5) {
        case 1: return Color(hex: 0x939CAD)
        case 2: return Color(hex: 0x828C9F)
        case 3: return Color(hex: 0x737D92)
        case 4: return Color(hex: 0x666F84)
        default: return Color(hex: 0x5B6377)
        }
    }

    /// Rock gets darker as it gets harder — hardness is readable at a glance.
    static func rock(hardness: Int) -> Color {
        switch min(max(hardness, 1), 5) {
        case 1: return Color(hex: 0x7C8699)
        case 2: return Color(hex: 0x6B758A)
        case 3: return Color(hex: 0x5C657A)
        case 4: return Color(hex: 0x50596C)
        default: return Color(hex: 0x464E60)
        }
    }

    static func rockShade(hardness: Int) -> Color {
        switch min(max(hardness, 1), 5) {
        case 1: return Color(hex: 0x646E83)
        case 2: return Color(hex: 0x555E72)
        case 3: return Color(hex: 0x474F62)
        case 4: return Color(hex: 0x3D4455)
        default: return Color(hex: 0x353B4A)
        }
    }
}

/// The metal a layer's ore nuggets are made of. Ore fills the hold and is
/// sold at the surface; deeper ore is worth more per slot.
struct Ore {
    let name: String
    let color: Color
    let shadow: Color
}

/// One band of earth. The run walks down through these in order.
struct StrataLayer {
    let name: String
    /// Boss banner line: "Guardian of the …", whole so each language words it.
    let guardian: String
    let startDepth: Double
    let soil: Color
    let soilDeep: Color
    let pebble: Color
    let crystal: Color?
    /// Multiplier applied to treasure value found in this layer.
    let goldValue: Int
    let gemValue: Int
    /// Mineral threads running through this layer's rock.
    let vein: Color
    /// Lit edge of a bedding plane.
    let bedding: Color
    let ore: Ore
}

enum Strata {
    /// Indexes of layers with their own decor. Generation keys off these,
    /// never off the (localized) names.
    static let ruins = 6
    static let frozen = 7
    static let spore = 8
    static let void = 9

    /// Rebuilt by `reloadNames` when the in-app language changes.
    static private(set) var layers: [StrataLayer] = makeLayers()

    static func reloadNames() { layers = makeLayers() }

    private static func makeLayers() -> [StrataLayer] {
        [
            StrataLayer(name: String(localized: "SURFACE", bundle: .app, comment: "Biome name"),
                        guardian: String(localized: "Guardian of the Surface", bundle: .app, comment: "Boss intro banner: the biome this boss guards"),
                        startDepth: 0,
                        soil: Color(hex: 0x805238),
                        soilDeep: Color(hex: 0x6B4229),
                        pebble: Color(hex: 0x94634A),
                        crystal: nil,
                        goldValue: 6, gemValue: 28,
                        vein: Color(hex: 0x9C7A4A), bedding: Color(hex: 0x9A6A4C),
                        ore: Ore(name: String(localized: "COPPER", bundle: .app, comment: "Ore metal name"), color: Color(hex: 0xE58C55), shadow: Color(hex: 0xA85A2E))),
            StrataLayer(name: String(localized: "SHALLOW CAVES", bundle: .app, comment: "Biome name"),
                        guardian: String(localized: "Guardian of the Shallow Caves", bundle: .app, comment: "Boss intro banner: the biome this boss guards"),
                        startDepth: 90,
                        soil: Color(hex: 0x674137),
                        soilDeep: Color(hex: 0x54342C),
                        pebble: Color(hex: 0x7C5046),
                        crystal: nil,
                        goldValue: 8, gemValue: 38,
                        vein: Color(hex: 0x8A6A52), bedding: Color(hex: 0x81564A),
                        ore: Ore(name: String(localized: "SILVER", bundle: .app, comment: "Ore metal name"), color: Color(hex: 0xDCE3EC), shadow: Color(hex: 0x98A4B6))),
            StrataLayer(name: String(localized: "DEEP CAVES", bundle: .app, comment: "Biome name"),
                        guardian: String(localized: "Guardian of the Deep Caves", bundle: .app, comment: "Boss intro banner: the biome this boss guards"),
                        startDepth: 200,
                        soil: Color(hex: 0x403451),
                        soilDeep: Color(hex: 0x332941),
                        pebble: Color(hex: 0x4F4164),
                        crystal: nil,
                        goldValue: 11, gemValue: 50,
                        vein: Color(hex: 0x6E5A86), bedding: Color(hex: 0x554770),
                        ore: Ore(name: String(localized: "GOLD", bundle: .app, comment: "Ore metal name"), color: Palette.gold, shadow: Palette.goldShadow)),
            StrataLayer(name: String(localized: "CRYSTAL CAVES", bundle: .app, comment: "Biome name"),
                        guardian: String(localized: "Guardian of the Crystal Caves", bundle: .app, comment: "Boss intro banner: the biome this boss guards"),
                        startDepth: 330,
                        soil: Color(hex: 0x233B58),
                        soilDeep: Color(hex: 0x1A2D45),
                        pebble: Color(hex: 0x2D4A6D),
                        crystal: Color(hex: 0x45D6CF),
                        goldValue: 14, gemValue: 65,
                        vein: Color(hex: 0x2F6F86), bedding: Color(hex: 0x325C85),
                        ore: Ore(name: String(localized: "PLATINUM", bundle: .app, comment: "Ore metal name"), color: Color(hex: 0xCFF3F0), shadow: Color(hex: 0x7FBFC0))),
            StrataLayer(name: String(localized: "MAGMA CORE", bundle: .app, comment: "Biome name"),
                        guardian: String(localized: "Guardian of the Magma Core", bundle: .app, comment: "Boss intro banner: the biome this boss guards"),
                        startDepth: 480,
                        soil: Color(hex: 0x4A2321),
                        soilDeep: Color(hex: 0x381818),
                        pebble: Color(hex: 0x5E2E28),
                        crystal: nil,
                        goldValue: 18, gemValue: 85,
                        vein: Color(hex: 0xB4532A), bedding: Color(hex: 0x6E3326),
                        ore: Ore(name: String(localized: "MYTHRIL", bundle: .app, comment: "Ore metal name"), color: Color(hex: 0x9FC2FF), shadow: Color(hex: 0x5B7FD6))),
            StrataLayer(name: String(localized: "THE ABYSS", bundle: .app, comment: "Biome name"),
                        guardian: String(localized: "Guardian of the Abyss", bundle: .app, comment: "Boss intro banner: the biome this boss guards"),
                        startDepth: 630,
                        soil: Color(hex: 0x10282B),
                        soilDeep: Color(hex: 0x0A1B1E),
                        pebble: Color(hex: 0x1C3C40),
                        crystal: Color(hex: 0x7CF5C8),      // glowing fungus clusters
                        goldValue: 22, gemValue: 100,
                        vein: Color(hex: 0x2C7A73), bedding: Color(hex: 0x1E4A4D),
                        ore: Ore(name: String(localized: "PEARL", bundle: .app, comment: "Ore metal name"), color: Color(hex: 0xFFD6EF), shadow: Color(hex: 0xC98AB4))),
            StrataLayer(name: String(localized: "ANCIENT RUINS", bundle: .app, comment: "Biome name"),
                        guardian: String(localized: "Guardian of the Ancient Ruins", bundle: .app, comment: "Boss intro banner: the biome this boss guards"),
                        startDepth: 780,
                        soil: Color(hex: 0x5A4830),
                        soilDeep: Color(hex: 0x463722),
                        pebble: Color(hex: 0x6E5A3A),
                        crystal: Color(hex: 0xF2C14E),      // gold glyph shards
                        goldValue: 27, gemValue: 120,
                        vein: Color(hex: 0xC9A24A), bedding: Color(hex: 0x7A6440),
                        ore: Ore(name: String(localized: "JADE", bundle: .app, comment: "Ore metal name"), color: Color(hex: 0x7FE0A8), shadow: Color(hex: 0x3E9E6E))),
            StrataLayer(name: String(localized: "FROZEN DEPTHS", bundle: .app, comment: "Biome name"),
                        guardian: String(localized: "Guardian of the Frozen Depths", bundle: .app, comment: "Boss intro banner: the biome this boss guards"),
                        startDepth: 930,
                        soil: Color(hex: 0x46607A),
                        soilDeep: Color(hex: 0x384E64),
                        pebble: Color(hex: 0x6B87A1),
                        crystal: Color(hex: 0xCFEFFF),      // icicle clusters
                        goldValue: 32, gemValue: 140,
                        vein: Color(hex: 0xA9DDF5), bedding: Color(hex: 0x5C7D99),
                        ore: Ore(name: String(localized: "SAPPHIRE", bundle: .app, comment: "Ore metal name"), color: Color(hex: 0x5FA8FF), shadow: Color(hex: 0x2F64C2))),
            StrataLayer(name: String(localized: "SPORE HOLLOW", bundle: .app, comment: "Biome name"),
                        guardian: String(localized: "Guardian of the Spore Hollow", bundle: .app, comment: "Boss intro banner: the biome this boss guards"),
                        startDepth: 1080,
                        soil: Color(hex: 0x2F4A2E),
                        soilDeep: Color(hex: 0x243A24),
                        pebble: Color(hex: 0x40613D),
                        crystal: Color(hex: 0xB6F25A),      // glowing spore shards
                        goldValue: 38, gemValue: 165,
                        vein: Color(hex: 0x8FCB4A), bedding: Color(hex: 0x3C5E39),
                        ore: Ore(name: String(localized: "RADIUM", bundle: .app, comment: "Ore metal name"), color: Color(hex: 0xD4FF6A), shadow: Color(hex: 0x86B52E))),
            StrataLayer(name: String(localized: "THE VOID", bundle: .app, comment: "Biome name"),
                        guardian: String(localized: "Guardian of the Void", bundle: .app, comment: "Boss intro banner: the biome this boss guards"),
                        startDepth: 1230,
                        soil: Color(hex: 0x1C1730),
                        soilDeep: Color(hex: 0x141024),
                        pebble: Color(hex: 0x2B2447),
                        crystal: Color(hex: 0xC9B3FF),      // star shards
                        goldValue: 45, gemValue: 195,
                        vein: Color(hex: 0x7A5FC8), bedding: Color(hex: 0x30285A),
                        ore: Ore(name: String(localized: "STARDUST", bundle: .app, comment: "Ore metal name"), color: Color(hex: 0xE9D6FF), shadow: Color(hex: 0x9D7BE0)))
        ]
    }

    static func index(for depth: Double) -> Int {
        var result = 0
        for (i, layer) in layers.enumerated() where depth >= layer.startDepth {
            result = i
        }
        return result
    }

    static func layer(for depth: Double) -> StrataLayer { layers[index(for: depth)] }

    /// Depth at which the next layer begins, or nil in the last layer.
    static func nextBoundary(after depth: Double) -> Double? {
        let i = index(for: depth)
        guard i + 1 < layers.count else { return nil }
        return layers[i + 1].startDepth
    }
}
