import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Thin wrapper so the game loop never has to care which platform it is on.
enum Haptics {
    static var enabled = true

    enum Strength { case light, medium, heavy }

    static func tap() { impact(.light) }
    static func bump() { impact(.medium) }
    static func thud() { impact(.heavy) }

    static func celebrate() {
        guard enabled else { return }
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    private static func impact(_ strength: Strength) {
        guard enabled else { return }
        #if os(iOS)
        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch strength {
        case .light: style = .light
        case .medium: style = .medium
        case .heavy: style = .heavy
        }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }
}
