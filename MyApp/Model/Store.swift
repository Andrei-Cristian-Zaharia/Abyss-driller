import StoreKit
import SwiftUI

/// Every product the Supply Depot sells. IDs must match App Store Connect
/// (and `Config/AbyssDriller.storekit` for local testing) exactly.
enum StoreProduct: String, CaseIterable {
    case goldSmall = "com.andreizaharia.abyssdriller.gold.small"
    case goldMedium = "com.andreizaharia.abyssdriller.gold.medium"
    case goldLarge = "com.andreizaharia.abyssdriller.gold.large"
    case doubleGold = "com.andreizaharia.abyssdriller.doublegold"
    case removeAds = "com.andreizaharia.abyssdriller.removeads"
    /// Double Gold + Remove Ads + a huge gold pack + the Magma Core paint.
    case megaBundle = "com.andreizaharia.abyssdriller.megabundle"
    case skinCopper = "com.andreizaharia.abyssdriller.skin.copper"
    case skinGlacier = "com.andreizaharia.abyssdriller.skin.glacier"
    case skinMagma = "com.andreizaharia.abyssdriller.skin.magma"

    var isConsumable: Bool { self == .goldSmall || self == .goldMedium || self == .goldLarge }

    /// The `GoldPack.id` this product delivers, if it is gold.
    var goldPackID: String? {
        switch self {
        case .goldSmall: return "gold.small"
        case .goldMedium: return "gold.medium"
        case .goldLarge: return "gold.large"
        default: return nil
        }
    }

    /// The `DrillSkin.id` this product unlocks, if it is a skin.
    var skinID: String? {
        switch self {
        case .skinCopper: return "copper"
        case .skinGlacier: return "glacier"
        case .skinMagma: return "magma"
        default: return nil
        }
    }

    static func forGoldPack(_ id: String) -> StoreProduct? { allCases.first { $0.goldPackID == id } }
    static func forSkin(_ id: String) -> StoreProduct? { allCases.first { $0.skinID == id } }
}

/// StoreKit 2: loads products, runs purchases, and delivers what was bought.
/// Delivery happens only for verified transactions, and the transaction is
/// finished only after the app has granted the item, so an interrupted or
/// "Ask to Buy" purchase is delivered later through `Transaction.updates`.
@Observable
final class StoreManager {
    enum Outcome { case purchased, pending, cancelled, failed }

    private(set) var products: [StoreProduct: Product] = [:]
    /// The product currently being bought (its button shows a spinner).
    private(set) var purchasing: StoreProduct?
    /// Grants a product. Set by `AppModel`; must be idempotent for
    /// non-consumables (entitlements are replayed on every launch).
    var deliver: ((StoreProduct) -> Void)?

    private var updatesTask: Task<Void, Never>?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        // Purchases finished outside the app or after an interruption.
        updatesTask = Task {
            for await update in Transaction.updates {
                await handle(update)
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    func loadProducts() async {
        guard let loaded = try? await Product.products(for: StoreProduct.allCases.map(\.rawValue)) else { return }
        for product in loaded {
            if let id = StoreProduct(rawValue: product.id) { products[id] = product }
        }
    }

    /// True once every product has come back from the App Store.
    var hasAllProducts: Bool { products.count == StoreProduct.allCases.count }

    /// The App Store's localised price, or the placeholder until it loads.
    func price(_ id: StoreProduct, fallback: String) -> String {
        products[id]?.displayPrice ?? fallback
    }

    func purchase(_ id: StoreProduct) async -> Outcome {
        guard purchasing == nil else { return .cancelled }
        if products[id] == nil { await loadProducts() }
        guard let product = products[id] else { return .failed }
        purchasing = id
        defer { purchasing = nil }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                return await handle(verification) ? .purchased : .failed
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed
            }
        } catch {
            return .failed
        }
    }

    /// "Restore Purchases": re-syncs with the App Store and re-grants every
    /// non-consumable the account owns.
    func restore() async -> Bool {
        do {
            try await AppStore.sync()
        } catch {
            return false
        }
        await refreshEntitlements()
        return true
    }

    /// Re-grants owned non-consumables (fresh install, new device).
    func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil,
                  let id = StoreProduct(rawValue: transaction.productID),
                  !id.isConsumable else { continue }
            deliver?(id)
        }
    }

    @discardableResult
    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async -> Bool {
        // Never grant anything StoreKit could not verify.
        guard case .verified(let transaction) = result,
              let id = StoreProduct(rawValue: transaction.productID) else { return false }
        if transaction.revocationDate == nil { deliver?(id) }
        await transaction.finish()
        return true
    }
}
