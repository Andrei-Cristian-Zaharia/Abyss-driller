import Foundation

/// The in-app language choice (Settings → Language). `nil` follows the
/// device. Every `String(localized:)` reads through `Bundle.app`, and
/// `ContentView` passes `locale` to SwiftUI, so a change applies at once.
enum AppLanguage {
    /// Languages the string catalog carries, in the order Settings lists them.
    static let supported = ["en", "ro", "es-MX", "pt-BR", "de", "fr", "ja", "ko", "zh-Hans"]

    nonisolated(unsafe) private(set) static var override: String?
    nonisolated(unsafe) private(set) static var bundle: Bundle = .main

    static var locale: Locale { override.map(Locale.init(identifier:)) ?? .current }

    /// The language actually showing, after falling back to the device.
    static var current: String { override ?? Bundle.main.preferredLocalizations.first ?? "en" }

    static func apply(_ code: String?) {
        let code = code.flatMap { supported.contains($0) ? $0 : nil }
        guard code != override else { return }
        override = code
        bundle = code.flatMap { Bundle.main.path(forResource: $0, ofType: "lproj") }
            .flatMap(Bundle.init(path:)) ?? .main
        // Tables built once from localized names; rebuild them in the new language.
        Strata.reloadNames()
        BestiaryEntry.reloadNames()
        DrillSkin.reloadNames()
    }

    /// A language's name in that language ("Deutsch", "日本語").
    static func nativeName(_ code: String) -> String {
        let own = Locale(identifier: code)
        return own.localizedString(forIdentifier: code)?.capitalized(with: own) ?? code
    }
}

extension Bundle {
    /// Where localized strings come from: the chosen language's `.lproj`, or main.
    static var app: Bundle { AppLanguage.bundle }
}
