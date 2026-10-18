import Foundation

/// iCloud key-value storage for the save file, so progress follows the player
/// to a new device or survives a reinstall. Apple keeps it in the player's own
/// iCloud account; nothing goes to us. The game works the same offline, or
/// when iCloud is off: the local copy in `UserDefaults` is always written too.
enum CloudSave {
    private static let key = "drilldown.profile.v1"
    private static var store: NSUbiquitousKeyValueStore { .default }

    static func load() -> PlayerProfile? {
        ProfileStore.decode(store.data(forKey: key))
    }

    static func save(_ data: Data) {
        // Key-value storage allows 1 MB in total; a save is a few KB.
        guard data.count < 900_000 else { return }
        store.set(data, forKey: key)
    }

    static func reset() {
        store.removeObject(forKey: key)
        store.synchronize()
    }

    /// Starts listening for saves pushed from the player's other devices.
    /// `onChange` gets the cloud copy; the caller merges it in.
    static func observe(_ onChange: @escaping @MainActor (PlayerProfile) -> Void) {
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: NSUbiquitousKeyValueStore.default, queue: .main) { note in
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            guard keys.contains(key), let cloud = load() else { return }
            Task { @MainActor in onChange(cloud) }
        }
        store.synchronize()
    }
}

/// Combines two saves of the same player (two devices, or a reinstall).
/// Anything earned is never lost: unlocks are unioned, records and levels
/// take the higher value, and purchases stay owned. Spendable gold and cores,
/// and choices such as the equipped build, come from the more recent save,
/// so spending on one device is not undone by the other.
enum ProfileMerge {
    static func merge(_ a: PlayerProfile, _ b: PlayerProfile) -> PlayerProfile {
        let newer = a.savedAt >= b.savedAt ? a : b
        let older = a.savedAt >= b.savedAt ? b : a
        var m = newer

        m.bestDepth = max(a.bestDepth, b.bestDepth)
        m.runsCompleted = max(a.runsCompleted, b.runsCompleted)
        m.lifetimeGems = max(a.lifetimeGems, b.lifetimeGems)
        for track in UpgradeTrack.allCases {
            m.levels[track] = max(a.levels[track], b.levels[track])
        }
        m.partLevels = a.partLevels.merging(b.partLevels, uniquingKeysWith: max)
        m.dailyScores = a.dailyScores.merging(b.dailyScores, uniquingKeysWith: max)
        m.bestiaryKills = a.bestiaryKills.merging(b.bestiaryKills, uniquingKeysWith: max)

        m.ownedParts = a.ownedParts.union(b.ownedParts)
        m.ownedSkins = a.ownedSkins.union(b.ownedSkins)
        m.bestiarySeen = a.bestiarySeen.union(b.bestiarySeen)
        m.perksSeen = a.perksSeen.union(b.perksSeen)

        m.adsRemoved = a.adsRemoved || b.adsRemoved
        m.doubleGold = a.doubleGold || b.doubleGold
        m.bundleGoldGranted = a.bundleGoldGranted || b.bundleGoldGranted

        // The newer save's choices only if they are still valid after the merge.
        if !m.ownedSkins.contains(m.selectedSkin) { m.selectedSkin = older.selectedSkin }
        m.savedAt = max(a.savedAt, b.savedAt)
        return m
    }

    /// Same progress, ignoring when each was saved.
    static func sameProgress(_ a: PlayerProfile, _ b: PlayerProfile) -> Bool {
        var a = a, b = b
        a.savedAt = .distantPast
        b.savedAt = .distantPast
        return a == b
    }
}
