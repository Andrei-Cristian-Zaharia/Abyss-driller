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

    static let classic = DrillSkin(
        id: "classic", name: "Site Standard", price: "Owned",
        body: Palette.drillBody, shadow: Palette.drillShadow,
        window: Palette.window, bit: Palette.drillBit)

    static let all: [DrillSkin] = [
        classic,
        DrillSkin(id: "copper", name: "Copper Baron", price: "$1.99",
                  body: Color(hex: 0xE08D4F), shadow: Color(hex: 0xA85F2E),
                  window: Palette.gold, bit: Color(hex: 0xE2CBA8)),
        DrillSkin(id: "glacier", name: "Glacier Rig", price: "$1.99",
                  body: Color(hex: 0x9FD7F2), shadow: Color(hex: 0x5E9CC4),
                  window: Palette.textPrimary, bit: Palette.drillBit),
        DrillSkin(id: "magma", name: "Magma Core", price: "$2.99",
                  body: Color(hex: 0xFF8A5B), shadow: Color(hex: 0xC2452F),
                  window: Palette.gold, bit: Color(hex: 0xD8C3C0))
    ]

    static func skin(id: String) -> DrillSkin {
        all.first { $0.id == id } ?? classic
    }
}
