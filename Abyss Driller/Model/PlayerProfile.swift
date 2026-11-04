import Foundation

struct PlayerProfile: Codable, Equatable {
    var gold: Int = 0
    var bestDepth: Int = 0
    var levels = UpgradeLevels()
    var ownedSkins: Set<String> = [DrillSkin.classic.id]
    var selectedSkin: String = DrillSkin.classic.id
    var doubleGold: Bool = false
    var runsCompleted: Int = 0
    var lifetimeGems: Int = 0
    /// Best daily-challenge score keyed by "yyyy-MM-dd".
    var dailyScores: [String: Int] = [:]
    /// Garage parts owned (raw `ShipPart` values) and what is bolted on.
    var ownedParts: Set<String> = Set(ShipPart.allCases.filter(\.isStarter).map(\.rawValue))
    var build = ShipBuild.standard
    /// Mk level per part (raw value → 1...3); missing means Mk I.
    var partLevels: [String: Int] = [:]
    /// Boss cores (keyed by `BossKind.key`), one per kill; spent on upgrades.
    var bossCores: [String: Int] = [:]
    /// Field Guide: pages unlocked (`BestiaryEntry.key`) and kills per page.
    var bestiarySeen: Set<String> = []
    var bestiaryKills: [String: Int] = [:]
    /// Free upgrades earned from ads, counted per day ("yyyy-MM-dd").
    var adUpgradeDay = ""
    var adUpgradesToday = 0
    /// "Remove Ads" (alone or in the Mega Bundle): ad rewards are granted
    /// straight away, with no video.
    var adsRemoved = false
    /// The Mega Bundle's gold is granted once; the bundle itself is replayed
    /// from StoreKit entitlements on every launch.
    var bundleGoldGranted = false
    /// When this save was last written (iCloud sync keeps the newer one's
    /// spendable gold and cores).
    var savedAt = Date.distantPast
    /// Perks the player has been offered at least once (How to Play shows these).
    var perksSeen: Set<String> = []

    init() {}

    /// Every field is optional on the way in. A synthesized decoder fails on
    /// any key it has not seen before, and `ProfileStore.load` treats failure
    /// as "no save" — so adding a field would silently wipe progress.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gold = try c.decodeIfPresent(Int.self, forKey: .gold) ?? 0
        bestDepth = try c.decodeIfPresent(Int.self, forKey: .bestDepth) ?? 0
        levels = try c.decodeIfPresent(UpgradeLevels.self, forKey: .levels) ?? UpgradeLevels()
        ownedSkins = try c.decodeIfPresent(Set<String>.self, forKey: .ownedSkins) ?? [DrillSkin.classic.id]
        selectedSkin = try c.decodeIfPresent(String.self, forKey: .selectedSkin) ?? DrillSkin.classic.id
        doubleGold = try c.decodeIfPresent(Bool.self, forKey: .doubleGold) ?? false
        runsCompleted = try c.decodeIfPresent(Int.self, forKey: .runsCompleted) ?? 0
        lifetimeGems = try c.decodeIfPresent(Int.self, forKey: .lifetimeGems) ?? 0
        dailyScores = try c.decodeIfPresent([String: Int].self, forKey: .dailyScores) ?? [:]
        ownedParts = (try? c.decodeIfPresent(Set<String>.self, forKey: .ownedParts)) ?? nil
            ?? Set(ShipPart.allCases.filter(\.isStarter).map(\.rawValue))
        build = (try? c.decodeIfPresent(ShipBuild.self, forKey: .build)) ?? nil ?? .standard
        partLevels = try c.decodeIfPresent([String: Int].self, forKey: .partLevels) ?? [:]
        bossCores = try c.decodeIfPresent([String: Int].self, forKey: .bossCores) ?? [:]
        bestiarySeen = try c.decodeIfPresent(Set<String>.self, forKey: .bestiarySeen) ?? []
        bestiaryKills = try c.decodeIfPresent([String: Int].self, forKey: .bestiaryKills) ?? [:]
        adUpgradeDay = try c.decodeIfPresent(String.self, forKey: .adUpgradeDay) ?? ""
        adUpgradesToday = try c.decodeIfPresent(Int.self, forKey: .adUpgradesToday) ?? 0
        adsRemoved = try c.decodeIfPresent(Bool.self, forKey: .adsRemoved) ?? false
        bundleGoldGranted = try c.decodeIfPresent(Bool.self, forKey: .bundleGoldGranted) ?? false
        savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt) ?? .distantPast
        perksSeen = try c.decodeIfPresent(Set<String>.self, forKey: .perksSeen) ?? []
    }

    func level(_ part: ShipPart) -> Int { max(1, partLevels[part.rawValue] ?? 1) }
    func cores(_ boss: BossKind) -> Int { bossCores[boss.key] ?? 0 }
    /// Lifetime kills of a boss (full and mini): the cores ever collected
    /// from it, which is what unlocks its part.
    func coresCollected(_ boss: BossKind) -> Int { bestiaryKills[BestiaryEntry.key(.boss(boss))] ?? 0 }

    var gear: Gear {
        Gear(build: build,
             levels: Dictionary(uniqueKeysWithValues: build.parts.map { ($0, level($0)) }))
    }

    func owns(_ part: ShipPart) -> Bool { part.isStarter || ownedParts.contains(part.rawValue) }

    /// The rig a normal run uses: upgrades plus the equipped parts.
    var runLoadout: Loadout { gear.apply(to: loadout) }

    var loadout: Loadout { Loadout.resolve(levels) }
    var skin: DrillSkin { DrillSkin.skin(id: selectedSkin) }

    func canAfford(_ track: UpgradeTrack) -> Bool {
        guard let price = track.price(atLevel: levels[track]) else { return false }
        return gold >= price
    }
}

enum ProfileStore {
    private static let key = "drilldown.profile.v1"

    /// The local save, merged with the iCloud copy if there is one.
    static func load() -> PlayerProfile {
        #if DEBUG
        // Director mode plays on a throwaway profile (see `save`).
        if Director.shared.isActive { return PlayerProfile() }
        #endif
        let local = decode(UserDefaults.standard.data(forKey: key))
        let cloud = CloudSave.load()
        switch (local, cloud) {
        case let (local?, cloud?): return ProfileMerge.merge(local, cloud)
        case let (local?, nil): return local
        case let (nil, cloud?): return cloud
        case (nil, nil): return PlayerProfile()
        }
    }

    static func save(_ profile: PlayerProfile) {
        #if DEBUG
        // Scenario cheats must never reach the real (iCloud-synced) save.
        if Director.shared.isActive { return }
        #endif
        var stamped = profile
        stamped.savedAt = Date()
        guard let data = try? JSONEncoder().encode(stamped) else { return }
        UserDefaults.standard.set(data, forKey: key)
        CloudSave.save(data)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
        CloudSave.reset()
    }

    static func decode(_ data: Data?) -> PlayerProfile? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(PlayerProfile.self, from: data)
    }
}

enum DailyChallenge {
    static var todayKey: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    static var todaySeed: UInt64 { stableSeed("daily-" + todayKey) }

    static var label: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: Date()).localizedUppercase
    }

    static func score(depth: Int, gold: Int) -> Int { depth + gold }
}
