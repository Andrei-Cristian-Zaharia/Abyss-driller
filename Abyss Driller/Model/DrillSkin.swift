import SwiftUI

/// Cosmetic only — a skin never changes a stat.
struct DrillSkin: Identifiable, Hashable {
    let id: String
    let name: String
    let price: String
    let body: Color
    let shadow: Color
    let window: Color
    let bit: Color

    /// Rebuilt by `reloadNames` when the in-app language changes.
    static private(set) var classic = makeClassic()
    static private(set) var all: [DrillSkin] = makeAll()

    static func reloadNames() {
        classic = makeClassic()
        all = makeAll()
    }

    private static func makeClassic() -> DrillSkin { DrillSkin(
        id: "classic", name: String(localized: "Site Standard", bundle: .app, comment: "Drill paint job name"), price: String(localized: "Owned", bundle: .app, comment: "Shop: the free paint job is already owned"),
        body: Palette.drillBody, shadow: Palette.drillShadow,
        window: Palette.window, bit: Palette.drillBit) }

    private static func makeAll() -> [DrillSkin] { [
        classic,
        DrillSkin(id: "copper", name: String(localized: "Copper Baron", bundle: .app, comment: "Drill paint job name"), price: "$1.99",
                  body: Color(hex: 0xE08D4F), shadow: Color(hex: 0xA85F2E),
                  window: Palette.gold, bit: Color(hex: 0xE2CBA8)),
        DrillSkin(id: "glacier", name: String(localized: "Glacier Rig", bundle: .app, comment: "Drill paint job name"), price: "$1.99",
                  body: Color(hex: 0x9FD7F2), shadow: Color(hex: 0x5E9CC4),
                  window: Palette.textPrimary, bit: Palette.drillBit),
        DrillSkin(id: "magma", name: String(localized: "Magma Core", bundle: .app, comment: "Drill paint job name"), price: "$2.99",
                  body: Color(hex: 0xFF8A5B), shadow: Color(hex: 0xC2452F),
                  window: Palette.gold, bit: Color(hex: 0xD8C3C0))
    ] }

    static func skin(id: String) -> DrillSkin {
        all.first { $0.id == id } ?? classic
    }
}
