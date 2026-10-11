import SwiftUI

enum Screen {
    case home
    case run
    case shop
    case garage
    case settings
    case fieldGuide
}

@Observable
final class AppModel {
    var profile: PlayerProfile {
        didSet { ProfileStore.save(profile) }
    }
    var screen: Screen = .home
    var world: GameWorld?
    var result: RunResult?
    var isPaused = false
    /// Mirrors `GameWorld.phase` so the view has something observable to key
    /// its overlays off.
    var runPhase: RunPhase = .ready
    var runOffersRefill = false
    var pendingDailyRun = false
    /// Set briefly after a purchase or upgrade so the UI can acknowledge it.
    var toast: String?
    let ads = AdsManager()
    let store = StoreManager()
    /// New Field Guide pages since the player last opened it (red dot on home).
    var unreadGuide = false
    /// Workshop upgrade currently offered for a rewarded ad (shows the offer card).
    var upgradeOffer: UpgradeTrack?
    /// True when the offer follows a purchase that left the player short.
    var offerAfterPurchase = false
    /// Free ad upgrades per day: a free upgrade can be worth thousands of
    /// gold, so they are rationed.
    static let adUpgradesPerDay = 10
    /// True while a rewarded ad is being fetched or shown for the refill.
    var watchingAd = false

    var settings: GameSettings {
        didSet {
            SettingsStore.save(settings)
            Haptics.enabled = settings.haptics
            world?.steerSensitivity = settings.sensitivity
            world?.shakeScale = settings.screenShake ? 1 : 0
        }
    }

    init(profile: PlayerProfile = ProfileStore.load(), settings: GameSettings = SettingsStore.load()) {
        self.profile = profile
        self.settings = settings
        Haptics.enabled = settings.haptics
        store.deliver = { [weak self] product in self?.deliver(product) }
    }

    var selectedSkin: DrillSkin { profile.skin }

    // MARK: - Runs

    func startRun(daily: Bool = false) {
        let levels = daily ? Loadout.dailyLevels : profile.levels
        // The daily stays fair: everyone gets the standard rig and build.
        let loadout = daily ? Loadout.dailyStandard : profile.runLoadout
        let gear = daily ? Gear.standard : profile.gear
        let seed = daily ? DailyChallenge.todaySeed : UInt64.random(in: 1...UInt64.max)

        let world = GameWorld(loadout: loadout,
                              levels: levels,
                              skin: selectedSkin,
                              gear: gear,
                              ownedParts: Set(ShipPart.allCases.filter { profile.owns($0) }),
                              // The daily is fair: everyone meets the full bosses.
                              // Owning the drop is the permanent record (cores get spent).
                              bossesBeaten: daily ? [] : Set(BossKind.allCases.filter { profile.owns(ShipPart.drop(for: $0)) }),
                              knownBestiary: profile.bestiarySeen,
                              previousBest: daily ? 0 : Double(profile.bestDepth),
                              doubleGold: profile.doubleGold,
                              isDaily: daily,
                              seed: seed)
        // Both callbacks fire from inside `tick`, which runs during a SwiftUI
        // view update. Hop to the next turn so model mutation never lands
        // mid-update.
        world.steerSensitivity = settings.sensitivity
        world.shakeScale = settings.screenShake ? 1 : 0
        world.onEnd = { [weak self] result in
            Task { @MainActor in self?.completeRun(result) }
        }
        world.onPhaseChange = { [weak self] phase in
            Task { @MainActor in
                guard let self, self.world === world else { return }
                self.runPhase = phase
                self.runOffersRefill = world.offersRefill
            }
        }
        self.world = world
        self.result = nil
        self.isPaused = false
        self.runPhase = .ready
        self.runOffersRefill = false
        self.pendingDailyRun = daily
        self.screen = .run
    }

    private func completeRun(_ result: RunResult) {
        var result = result
        // Boss drops unlock the first time each boss falls, daily runs included.
        for kind in result.bossKindsDefeated {
            profile.bossCores[kind.key, default: 0] += 1
            let part = ShipPart.drop(for: kind)
            if !profile.owns(part) {
                profile.ownedParts.insert(part.rawValue)
                result.newParts.append(part)
            }
        }
        // Field Guide: unlock new pages and add this run's kills.
        result.newEntries = result.bestiarySeen.subtracting(profile.bestiarySeen).sorted()
        if !result.newEntries.isEmpty { unreadGuide = true }
        profile.bestiarySeen.formUnion(result.bestiarySeen)
        for (key, kills) in result.bestiaryKills { profile.bestiaryKills[key, default: 0] += kills }
        self.result = result
        profile.runsCompleted += 1
        profile.lifetimeGems += result.gems

        if result.isDaily {
            let key = DailyChallenge.todayKey
            profile.dailyScores[key] = max(profile.dailyScores[key] ?? 0, result.dailyScore)
        } else {
            profile.gold += result.payout
            profile.bestDepth = max(profile.bestDepth, result.depth)
        }
    }

    func drillAgain() {
        startRun(daily: pendingDailyRun)
    }

    func goHome() {
        world = nil
        result = nil
        isPaused = false
        runPhase = .ready
        runOffersRefill = false
        screen = .home
    }

    /// Bought "Remove Ads" (alone or in the Mega Bundle): every ad reward is
    /// granted at once, with no video.
    var adsRemoved: Bool { profile.adsRemoved }

    /// The refill button: show a rewarded ad, then refuel. If no ad can be
    /// shown, the refill is granted anyway — the player asked for it and it
    /// is not their fault there was nothing to show.
    func watchAdForRefill() {
        guard let world, world.offersRefill, !watchingAd else { return }
        if adsRemoved {
            world.refuelAndResume()
            return
        }
        watchingAd = true
        ads.showRewarded { [weak self] watched in
            guard let self else { return }
            self.watchingAd = false
            world.refuelAndResume()
            if !watched { self.toast = "NO AD RIGHT NOW · REFILL ON US" }
        }
    }

    func openFieldGuide() {
        unreadGuide = false
        screen = .fieldGuide
    }

    func abandonRun() {
        world?.confirmEnd()
        isPaused = false
    }

    var todayDailyScore: Int? { profile.dailyScores[DailyChallenge.todayKey] }

    // MARK: - Testing

    /// Wipes all progress (gold, depth, upgrades, parts, cores, skins, daily
    /// scores) back to a fresh install. Settings are kept.
    func resetProgress() {
        ProfileStore.reset()
        profile = PlayerProfile()
        world = nil
        result = nil
        isPaused = false
        runPhase = .ready
        runOffersRefill = false
        pendingDailyRun = false
        toast = "PROGRESS RESET"
        Haptics.thud()
    }

    // MARK: - Upgrades

    func canBuy(_ track: UpgradeTrack) -> Bool {
        guard let price = track.price(atLevel: profile.levels[track]) else { return false }
        return profile.gold >= price
    }

    @discardableResult
    func buy(_ track: UpgradeTrack) -> Bool {
        guard let price = track.price(atLevel: profile.levels[track]), profile.gold >= price else {
            return false
        }
        profile.gold -= price
        profile.levels[track] += 1
        toast = "\(track.title) → LV \(profile.levels[track])"
        Haptics.celebrate()
        return true
    }

    // MARK: - Garage

    func canBuy(_ part: ShipPart) -> Bool {
        guard let price = part.price, !profile.owns(part) else { return false }
        return profile.gold >= price
    }

    func buy(_ part: ShipPart) {
        guard let price = part.price, !profile.owns(part), profile.gold >= price else {
            Haptics.bump()
            return
        }
        profile.gold -= price
        profile.ownedParts.insert(part.rawValue)
        profile.build[part.slot] = part
        toast = "\(part.title.uppercased()) FITTED"
        Haptics.celebrate()
    }

    func upgradeCost(_ part: ShipPart) -> (gold: Int, cores: Int)? {
        guard profile.owns(part) else { return nil }
        return part.upgradeCost(to: profile.level(part) + 1)
    }

    func canUpgrade(_ part: ShipPart) -> Bool {
        guard let cost = upgradeCost(part) else { return false }
        let cores = part.droppedBy.map { profile.cores($0) } ?? 0
        return profile.gold >= cost.gold && cores >= cost.cores
    }

    func upgrade(_ part: ShipPart) {
        guard canUpgrade(part), let cost = upgradeCost(part) else {
            Haptics.bump()
            return
        }
        profile.gold -= cost.gold
        if let boss = part.droppedBy { profile.bossCores[boss.key, default: 0] -= cost.cores }
        profile.partLevels[part.rawValue] = profile.level(part) + 1
        toast = "\(part.title.uppercased()) → MK \(String(repeating: "I", count: profile.level(part)))"
        Haptics.celebrate()
    }

    func equip(_ part: ShipPart) {
        guard profile.owns(part) else { return }
        profile.build[part.slot] = part
        Haptics.tap()
    }

    // MARK: - Ad upgrades

    var adUpgradesLeft: Int {
        profile.adUpgradeDay == DailyChallenge.todayKey
            ? max(0, Self.adUpgradesPerDay - profile.adUpgradesToday)
            : Self.adUpgradesPerDay
    }

    /// An upgrade the player can't afford can be had for a rewarded ad.
    func canOfferAdUpgrade(_ track: UpgradeTrack) -> Bool {
        (ads.isSupported || adsRemoved) && adUpgradesLeft > 0 && track.price(atLevel: profile.levels[track]) != nil && !canBuy(track)
    }

    /// Workshop card tap: buy if affordable. If that leaves the next level out
    /// of reach, or the player couldn't afford it at all, offer it for an ad.
    func tapUpgrade(_ track: UpgradeTrack) {
        if buy(track) {
            if canOfferAdUpgrade(track) {
                offerAfterPurchase = true
                upgradeOffer = track
            }
        } else if canOfferAdUpgrade(track) {
            offerAfterPurchase = false
            upgradeOffer = track
            Haptics.tap()
        } else {
            Haptics.bump()
        }
    }

    /// Watch the ad, then grant one free level. Unlike the fuel refill, an
    /// upgrade is only granted for an ad actually watched.
    func watchAdForUpgrade() {
        guard let track = upgradeOffer, canOfferAdUpgrade(track), !watchingAd else { return }
        if adsRemoved {
            grantFreeUpgrade(track)
            return
        }
        watchingAd = true
        ads.showRewarded { [weak self] watched in
            guard let self else { return }
            self.watchingAd = false
            guard watched else {
                self.toast = "NO AD AVAILABLE · TRY AGAIN SOON"
                return
            }
            self.grantFreeUpgrade(track)
        }
    }

    /// One free Workshop level, counted against the daily allowance.
    private func grantFreeUpgrade(_ track: UpgradeTrack) {
        let today = DailyChallenge.todayKey
        if profile.adUpgradeDay != today {
            profile.adUpgradeDay = today
            profile.adUpgradesToday = 0
        }
        profile.adUpgradesToday += 1
        profile.levels[track] += 1
        upgradeOffer = nil
        toast = "\(track.title) → LV \(profile.levels[track]) · FREE"
        Haptics.celebrate()
    }

    // MARK: - Shop (StoreKit)

    /// Starts an App Store purchase. The item itself is granted by `deliver`
    /// once StoreKit has verified the transaction.
    func purchase(_ product: StoreProduct) {
        Task {
            switch await store.purchase(product) {
            case .purchased, .cancelled: break
            case .pending: toast = "PURCHASE WAITING FOR APPROVAL"
            case .failed: toast = "PURCHASE DIDN'T GO THROUGH"
            }
        }
    }

    func restorePurchases() {
        Task {
            toast = await store.restore() ? "PURCHASES RESTORED" : "COULDN'T REACH THE APP STORE"
        }
    }

    /// Grants a verified purchase. Non-consumables are replayed on every
    /// launch (restoring them after a reinstall), so those are idempotent.
    private func deliver(_ product: StoreProduct) {
        if let packID = product.goldPackID,
           let pack = ShopCatalog.goldPacks(levels: profile.levels).first(where: { $0.id == packID }) {
            profile.gold += pack.amount
            toast = "+\(pack.amount) GOLD"
            Haptics.celebrate()
        } else if product == .doubleGold, !profile.doubleGold {
            profile.doubleGold = true
            toast = "DOUBLE GOLD UNLOCKED"
            Haptics.celebrate()
        } else if product == .removeAds, !profile.adsRemoved {
            profile.adsRemoved = true
            toast = "NO MORE ADS · REWARDS ARE INSTANT"
            Haptics.celebrate()
        } else if product == .megaBundle {
            deliverBundle()
        } else if let skinID = product.skinID, !profile.ownedSkins.contains(skinID) {
            profile.ownedSkins.insert(skinID)
            profile.selectedSkin = skinID
            toast = "\(DrillSkin.skin(id: skinID).name.uppercased()) EQUIPPED"
            Haptics.celebrate()
        }
    }

    /// Mega Bundle: each part is granted only if missing, and the gold only
    /// once, because the bundle is replayed from entitlements every launch.
    private func deliverBundle() {
        var granted = false
        if !profile.doubleGold { profile.doubleGold = true; granted = true }
        if !profile.adsRemoved { profile.adsRemoved = true; granted = true }
        if !profile.ownedSkins.contains(ShopCatalog.bundleSkinID) {
            profile.ownedSkins.insert(ShopCatalog.bundleSkinID)
            profile.selectedSkin = ShopCatalog.bundleSkinID
            granted = true
        }
        if !profile.bundleGoldGranted, let pack = ShopCatalog.goldPacks(levels: profile.levels).last {
            profile.gold += pack.amount
            profile.bundleGoldGranted = true
            granted = true
        }
        if granted {
            toast = "MEGA BUNDLE UNLOCKED"
            Haptics.celebrate()
        }
    }

    /// Everything in the Mega Bundle is already owned (the card is hidden).
    var ownsBundle: Bool {
        profile.bundleGoldGranted || (profile.doubleGold && profile.adsRemoved && profile.ownedSkins.contains(ShopCatalog.bundleSkinID))
    }

    func selectSkin(_ skin: DrillSkin) {
        guard profile.ownedSkins.contains(skin.id) else { return }
        profile.selectedSkin = skin.id
        Haptics.tap()
    }

    func owns(_ skin: DrillSkin) -> Bool { profile.ownedSkins.contains(skin.id) }
}
