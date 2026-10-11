import SwiftUI

struct GoldPack: Identifiable {
    let id: String
    let amount: Int
    let price: String
    let tag: String?
}

/// Fallback prices for the Shop, shown until StoreKit has loaded the real,
/// localised ones (`StoreManager.price`). They match App Store Connect.
enum ShopCatalog {
    /// Pack sizes grow with the player's Workshop progress so a pack always
    /// means something: the small pack is about three next upgrades, the
    /// others are ×5 and ×10 of it. Always a multiple of 500, so a fresh
    /// profile sees 3,000 / 15,000 / 30,000.
    static func goldPacks(levels: UpgradeLevels) -> [GoldPack] {
        let nextPrices = UpgradeTrack.allCases.map { Double($0.price(atLevel: levels[$0]) ?? 0) }
        let average = nextPrices.reduce(0, +) / Double(nextPrices.count)
        let base = max(1_000, Int((average / 500).rounded(.up)) * 500) * 3
        return [
            GoldPack(id: "gold.small", amount: base, price: "$0.99", tag: nil),
            GoldPack(id: "gold.medium", amount: base * 5, price: "$1.99", tag: "POPULAR"),
            GoldPack(id: "gold.large", amount: base * 10, price: "$3.99", tag: "BEST VALUE")
        ]
    }

    static let doubleGoldPrice = "$2.99"
    static let removeAdsPrice = "$2.99"
    static let megaBundlePrice = "$5.99"
    /// The paint job included in the Mega Bundle.
    static let bundleSkinID = "magma"
    /// What the bundle's items cost separately, for the "save" label.
    static let bundleWorth = "$12.96"
}
