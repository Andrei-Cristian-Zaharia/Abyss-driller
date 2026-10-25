import SwiftUI

enum Screen {
    case home
    case run
    case shop
    case garage
    case settings
    case fieldGuide
    case howToPlay
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
            Audio.shared.soundOn = settings.sound
            Audio.shared.musicOn = settings.music
            world?.steerSensitivity = settings.sensitivity
            world?.shakeScale = settings.screenShake ? 1 : 0
            AppLanguage.apply(settings.language)
        }
    }

    init(profile: PlayerProfile = ProfileStore.load(), settings: GameSettings = SettingsStore.load()) {
        self.profile = profile
        self.settings = settings
        Haptics.enabled = settings.haptics
        Audio.shared.soundOn = settings.sound
        Audio.shared.musicOn = settings.music
        AppLanguage.apply(settings.language)
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
                              bossesBeaten: daily ? [] : Set(BossKind.allCases.filter { profile.coresCollected($0) > 0 || profile.owns(ShipPart.drop(for: $0)) }),
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
        world.coresBefore = Dictionary(uniqueKeysWithValues: BossKind.allCases.map { ($0, profile.coresCollected($0)) })
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
        // Field Guide: unlock new pages and add this run's kills. Boss kills
        // also count as collected cores, so merge them before the unlock check.
        result.newEntries = result.bestiarySeen.subtracting(profile.bestiarySeen).sorted()
        if !result.newEntries.isEmpty { unreadGuide = true }
        profile.bestiarySeen.formUnion(result.bestiarySeen)
        profile.perksSeen.formUnion(result.perksSeen)
        for (key, kills) in result.bestiaryKills { profile.bestiaryKills[key, default: 0] += kills }
        // Every boss kill (full or mini, daily included) is one core: spendable
        // on upgrades, and counted towards unlocking that boss's part at 10.
        for kind in result.bossKindsDefeated { profile.bossCores[kind.key, default: 0] += 1 }
        for kind in BossKind.allCases where result.bossKindsDefeated.contains(kind) {
            let part = ShipPart.drop(for: kind)
            guard !profile.owns(part) else { continue }
            let collected = profile.coresCollected(kind)
            let thisRun = result.bossKindsDefeated.filter { $0 == kind }.count
            if collected >= ShipPart.coresToUnlock {
                // Just crossed 10: the part is now for sale in the Garage.
                if collected - thisRun < ShipPart.coresToUnlock { result.newParts.append(part) }
            } else {
                result.coreProgress.append((kind, profile.coresCollected(kind)))
            }
        }
        self.result = result
        profile.runsCompleted += 1
        runsSinceInterstitial += 1
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
        leaveResults { [weak self] in
            guard let self else { return }
            self.startRun(daily: self.pendingDailyRun)
        }
    }

    /// The results screen's Home button.
    func leaveResultsHome() {
        leaveResults { [weak self] in self?.goHome() }
    }

    /// Runs finished since the last interstitial (this launch only, so a
    /// fresh session always starts with a few ad-free runs).
    private var runsSinceInterstitial = 0

    /// The only interstitial: on the way out of the results screen, never
    /// during a run or before the payout is seen. Shown only when all hold:
    /// no Remove Ads, `interstitialFreeRuns` runs played ever, at least
    /// `interstitialEveryRuns` runs since the last one, and `interstitialGap`
    /// since any full-screen ad (a rewarded refill or upgrade counts).
    /// With no ad loaded it just carries on.
    private func leaveResults(then next: @escaping () -> Void) {
        guard !watchingAd else { return }   // a second tap while the ad opens
        let gapOK = ads.lastAdClosed.map { ContinuousClock.now - $0 >= AdConfig.interstitialGap } ?? true
        guard !adsRemoved, ads.isSupported,
              profile.runsCompleted >= AdConfig.interstitialFreeRuns,
              runsSinceInterstitial >= AdConfig.interstitialEveryRuns,
              gapOK
        else {
            next()
            return
        }
        runsSinceInterstitial = 0
        watchingAd = true
        ads.showInterstitial { [weak self] in
            self?.watchingAd = false
            next()
        }
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
            if !watched { self.toast = String(localized: "NO AD RIGHT NOW · REFILL ON US", bundle: .app, comment: "Toast: no ad loaded, fuel refill granted anyway") }
        }
    }

    func openFieldGuide() {
        unreadGuide = false
        screen = .fieldGuide
    }

    func abandonRun() {
        // Ended before the first touch: nothing was dug, so there is nothing to
        // score. Go straight home instead of showing an empty results screen.
        if world?.phase == .ready {
            goHome()
            return
        }
        world?.confirmEnd()
        isPaused = false
    }

    var todayDailyScore: Int? { profile.dailyScores[DailyChallenge.todayKey] }

    // MARK: - Testing

    /// Wipes all progress (gold, depth, upgrades, parts, cores, skins, daily
    /// scores) back to a fresh install. Settings are kept.
    /// A save arrived from the player's other device (iCloud). Adopt the
    /// merge only if it brings something new, or two devices would keep
    /// re-sending the same save to each other.
    func mergeCloudSave(_ cloud: PlayerProfile) {
        let merged = ProfileMerge.merge(profile, cloud)
        guard !ProfileMerge.sameProgress(merged, profile) else { return }
        profile = merged
    }

    func resetProgress() {
        ProfileStore.reset()
        profile = PlayerProfile()
        world = nil
        result = nil
        isPaused = false
        runPhase = .ready
        runOffersRefill = false
        pendingDailyRun = false
        toast = String(localized: "PROGRESS RESET", bundle: .app)
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
        toast = String(localized: "\(track.title) → LV \(profile.levels[track])", bundle: .app, comment: "Toast: Workshop upgrade bought; LV = level")
        Haptics.celebrate()
        Audio.shared.play(.buy)
        return true
    }

    // MARK: - Garage

    /// Boss parts can only be bought once their 10 cores are collected.
    func isForSale(_ part: ShipPart) -> Bool {
        guard !profile.owns(part), part.buyPrice != nil else { return false }
        guard let boss = part.droppedBy else { return true }
        return profile.coresCollected(boss) >= ShipPart.coresToUnlock
    }

    func canBuy(_ part: ShipPart) -> Bool {
        guard isForSale(part), let price = part.buyPrice else { return false }
        return profile.gold >= price
    }

    func buy(_ part: ShipPart) {
        guard canBuy(part), let price = part.buyPrice else {
            Haptics.bump()
            return
        }
        profile.gold -= price
        profile.ownedParts.insert(part.rawValue)
        profile.build[part.slot] = part
        toast = String(localized: "\(part.title.localizedUppercase) FITTED", bundle: .app, comment: "Toast: drill part bought and installed")
        Haptics.celebrate()
        Audio.shared.play(.buy)
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
        let mark = String(repeating: "I", count: profile.level(part))
        toast = String(localized: "\(part.title.localizedUppercase) → MK \(mark)", bundle: .app, comment: "Toast: part upgraded; MK + Roman numeral is the part's mark (I, II, III)")
        Haptics.celebrate()
        Audio.shared.play(.buy)
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
                self.toast = String(localized: "NO AD AVAILABLE · TRY AGAIN SOON", bundle: .app)
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
        toast = String(localized: "\(track.title) → LV \(profile.levels[track]) · FREE", bundle: .app, comment: "Toast: free Workshop upgrade from an ad; LV = level")
        Haptics.celebrate()
        Audio.shared.play(.buy)
    }

    // MARK: - Shop (StoreKit)

    /// Starts an App Store purchase. The item itself is granted by `deliver`
    /// once StoreKit has verified the transaction.
    func purchase(_ product: StoreProduct) {
        Task {
            switch await store.purchase(product) {
            case .purchased, .cancelled: break
            case .pending: toast = String(localized: "PURCHASE WAITING FOR APPROVAL", bundle: .app)
            case .failed: toast = String(localized: "PURCHASE DIDN'T GO THROUGH", bundle: .app)
            }
        }
    }

    func restorePurchases() {
        Task {
            toast = await store.restore() ? String(localized: "PURCHASES RESTORED", bundle: .app) : String(localized: "COULDN'T REACH THE APP STORE", bundle: .app)
        }
    }

    /// Grants a verified purchase. Non-consumables are replayed on every
    /// launch (restoring them after a reinstall), so those are idempotent.
    private func deliver(_ product: StoreProduct) {
        if let packID = product.goldPackID,
           let pack = ShopCatalog.goldPacks(levels: profile.levels).first(where: { $0.id == packID }) {
            profile.gold += pack.amount
            toast = String(localized: "+\(pack.amount) GOLD", bundle: .app, comment: "Toast: gold pack purchased")
            Haptics.celebrate()
            Audio.shared.play(.buy)
        } else if product == .doubleGold, !profile.doubleGold {
            profile.doubleGold = true
            toast = String(localized: "DOUBLE GOLD UNLOCKED", bundle: .app)
            Haptics.celebrate()
            Audio.shared.play(.buy)
        } else if product == .removeAds, !profile.adsRemoved {
            profile.adsRemoved = true
            toast = String(localized: "NO MORE ADS · REWARDS ARE INSTANT", bundle: .app)
            Haptics.celebrate()
            Audio.shared.play(.buy)
        } else if product == .megaBundle {
            deliverBundle()
        } else if let skinID = product.skinID, !profile.ownedSkins.contains(skinID) {
            profile.ownedSkins.insert(skinID)
            profile.selectedSkin = skinID
            toast = String(localized: "\(DrillSkin.skin(id: skinID).name.localizedUppercase) EQUIPPED", bundle: .app, comment: "Toast: paint job bought and applied")
            Haptics.celebrate()
            Audio.shared.play(.buy)
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
            toast = String(localized: "MEGA BUNDLE UNLOCKED", bundle: .app)
            Haptics.celebrate()
            Audio.shared.play(.buy)
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
