import Foundation

/// Player preferences. Stored apart from `PlayerProfile` so resetting progress
/// never resets controls, and decoded field-by-field for the same reason the
/// profile is (an unknown key must not throw the whole thing away).
struct GameSettings: Codable, Equatable {
    /// Multiplies how fast the drill turns. 1 is the tuned default.
    var sensitivity: Double = 1.0
    /// Points the thumb must move before the drill turns at all.
    var deadZone: Double = 20
    var haptics = true
    var screenShake = true
    var showJoystick = true

    static let sensitivityRange = 0.5...1.8
    static let deadZoneRange = 6.0...40.0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sensitivity = try c.decodeIfPresent(Double.self, forKey: .sensitivity) ?? 1.0
        deadZone = try c.decodeIfPresent(Double.self, forKey: .deadZone) ?? 20
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? true
        screenShake = try c.decodeIfPresent(Bool.self, forKey: .screenShake) ?? true
        showJoystick = try c.decodeIfPresent(Bool.self, forKey: .showJoystick) ?? true
    }
}

enum SettingsStore {
    private static let key = "drilldown.settings.v1"

    static func load() -> GameSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(GameSettings.self, from: data)
        else { return GameSettings() }
        return settings
    }

    static func save(_ settings: GameSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
