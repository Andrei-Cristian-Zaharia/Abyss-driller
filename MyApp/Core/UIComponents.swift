import SwiftUI

/// Safe-area insets measured by `PortraitStage`. The stage draws full-bleed, so
/// children that need to clear the notch or home indicator read them from here
/// rather than from their own geometry.
private struct StageSafeAreaKey: EnvironmentKey {
    static let defaultValue = EdgeInsets()
}

extension EnvironmentValues {
    var stageSafeArea: EdgeInsets {
        get { self[StageSafeAreaKey.self] }
        set { self[StageSafeAreaKey.self] = newValue }
    }
}

/// The game is designed for a portrait phone. It fills the screen edge to edge
/// there, and letterboxes into the same aspect on an iPad or a Mac window.
///
/// This measures the *full* screen — reading geometry inside the safe area
/// would shrink the stage to the inset size and letterbox the phone too.
///
/// The insets come from a separate outer reader: a `GeometryReader` that
/// ignores the safe area reports zero insets, which put every top bar under
/// the Dynamic Island where it could not be tapped.
struct PortraitStage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    private let targetAspect: CGFloat = 9.0 / 19.5

    var body: some View {
        GeometryReader { safe in
            let insets = safe.safeAreaInsets
            GeometryReader { geometry in
                let full = geometry.size
                let width = min(full.width, full.height * targetAspect)
                ZStack {
                    Palette.background
                    content()
                        .frame(width: width, height: full.height)
                        .clipped()
                        .environment(\.stageSafeArea, insets)
                }
                .frame(width: full.width, height: full.height)
            }
            .ignoresSafeArea()
        }
    }
}

struct PrimaryButton: View {
    let title: String
    var icon: String?
    var tint: Color = Palette.mint
    var shadow: Color = Palette.mintShadow
    var compact = false
    let action: () -> Void

    private var radius: CGFloat { compact ? 16 : 22 }
    private var lip: CGFloat { compact ? 4 : 6 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon { Image(systemName: icon).font(.system(size: compact ? 15 : 20, weight: .bold)) }
                Text(title)
                    .font(.system(size: compact ? 16 : 24, weight: .black, design: .rounded))
                    .kerning(0.5)
            }
            .foregroundStyle(Palette.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 12 : 18)
            .background {
                // A chunky key: the face sits on a darker base of the same
                // shape, which shows underneath as one curved edge (the old
                // flat strip stuck out past the rounded corners like a bar).
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                ZStack {
                    shape.fill(shadow)
                        .overlay(shape.strokeBorder(Palette.ink.opacity(0.85), lineWidth: 2.5))
                        .offset(y: lip)
                    shape.fill(tint)
                        .overlay(alignment: .top) {
                            // Soft top highlight on the face.
                            shape.fill(Color.white.opacity(0.09))
                                .frame(height: compact ? 12 : 16)
                                .mask(shape)
                                .padding(.horizontal, 3)
                                .padding(.top, 3)
                        }
                        .overlay(shape.strokeBorder(Palette.ink.opacity(0.85), lineWidth: 2.5))
                }
            }
            .padding(.bottom, lip)
        }
        .buttonStyle(SquishButtonStyle())
    }
}

struct SecondaryButton: View {
    let title: String
    var icon: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 14, weight: .bold)) }
                Text(title).font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Palette.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Palette.panelRaised)
            )
        }
        .buttonStyle(SquishButtonStyle())
    }
}

struct SquishButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct Panel<Content: View>: View {
    var tint: Color = Palette.panel
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(tint)
            )
    }
}

/// Compact HUD meter: icon, bar, value. Used for fuel and armour.
struct StatMeter: View {
    let icon: String
    let fraction: Double
    let tint: Color
    var label: String?
    var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 14)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.background.opacity(0.65))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(3, geometry.size.width * fraction))
                }
            }
            .frame(height: 8)
            if let label {
                Text(label)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
            }
        }
        .opacity(pulse ? 0.65 : 1)
    }
}

struct GoldPill: View {
    let amount: Int
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Palette.gold)
                .frame(width: compact ? 13 : 17)
                .overlay(Circle().fill(Palette.goldShadow).frame(width: compact ? 6 : 8))
            Text("\(amount)")
                .font(.system(size: compact ? 15 : 20, weight: .black, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.vertical, compact ? 6 : 9)
        .background(Capsule().fill(Palette.panel.opacity(0.92)))
    }
}

struct StatBlock: View {
    let caption: String
    let value: String
    var tint: Color = Palette.textPrimary

    var body: some View {
        VStack(spacing: 2) {
            Text(caption)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.textSecondary)
            Text(value)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
    }
}

/// Level pips — reads faster than "Lv 3/5" at a glance.
struct LevelPips: View {
    let level: Int
    let maxLevel: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<maxLevel, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(index < level ? tint : Palette.background.opacity(0.7))
                    .frame(width: 11, height: 5)
            }
        }
    }
}
