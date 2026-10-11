import SwiftUI

// Shared menu chrome. Every menu screen is built from these so the app reads
// as one product: the same ground, cards, headers and controls everywhere.

/// The ground behind every menu: night sky fading into layered strata, with
/// the same soil colours the run digs through. Static, so it costs nothing.
struct MenuBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let w = Double(size.width), h = Double(size.height)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Palette.background, Palette.panelSunken, Palette.background]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

            // Strata bands rising from the bottom, faint enough to stay behind
            // the cards: one per layer, deepest at the bottom.
            let layers = Strata.layers
            let bandTop = h * 0.62
            let bandHeight = (h - bandTop) / Double(layers.count)
            var rng = SeededRandom(seed: 0xBA5E)
            for (index, layer) in layers.enumerated() {
                let y = bandTop + Double(index) * bandHeight
                var band = Path()
                band.move(to: CGPoint(x: 0, y: y + rng.double(-8...8)))
                var x = 0.0
                while x <= w {
                    x += w / 6
                    band.addLine(to: CGPoint(x: x, y: y + rng.double(-10...10)))
                }
                band.addLine(to: CGPoint(x: w, y: h))
                band.addLine(to: CGPoint(x: 0, y: h))
                band.closeSubpath()
                ctx.fill(band, with: .color(layer.soil.opacity(0.16 + 0.04 * Double(index))))
            }
            // A few pebbles and specks of ore.
            for _ in 0..<26 {
                let p = CGPoint(x: rng.double(0...w), y: rng.double(bandTop...h))
                let r = rng.double(1.5...4.5)
                let layer = Strata.layer(for: (p.y - bandTop) / max(1, h - bandTop) * 500)
                let ore = rng.chance(0.25)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color((ore ? layer.ore.color : layer.pebble).opacity(ore ? 0.5 : 0.3)))
            }
            // Soft vignette keeps the eye in the middle.
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                Gradient(colors: [.clear, .black.opacity(0.35)]),
                center: CGPoint(x: w / 2, y: h * 0.4), startRadius: w * 0.4, endRadius: h * 0.8))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Card surface: panel fill with a lit top edge, a hairline rim and a soft
/// drop shadow. `accent` draws a coloured rim instead (selected / equipped).
struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = 18
    var fill: Color = Palette.panel
    var accent: Color?

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(colors: [fill.mix(with: .white, by: 0.035), fill],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(accent ?? .white.opacity(0.06), lineWidth: accent == nil ? 1 : 2)
                )
                .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
        )
    }
}

extension View {
    func card(_ cornerRadius: CGFloat = 18, fill: Color = Palette.panel, accent: Color? = nil) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius, fill: fill, accent: accent))
    }
}

/// Round icon button used in headers and the home top bar.
struct CircleIconButton: View {
    let icon: String
    let label: String
    var badge = false
    let action: () -> Void

    var body: some View {
        Button {
            action()
            Haptics.tap()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 42, height: 42)
                .background(
                    Circle()
                        .fill(LinearGradient(colors: [Palette.panelRaised, Palette.panel],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(Circle().strokeBorder(.white.opacity(0.07), lineWidth: 1))
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                )
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle().fill(Palette.hazard).frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Palette.background, lineWidth: 2))
                            .offset(x: 1, y: -1)
                    }
                }
        }
        .buttonStyle(SquishButtonStyle())
        .accessibilityLabel(label)
    }
}

/// Back button, title and an optional trailing view. Shared by every
/// secondary screen so they line up exactly.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    let onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            CircleIconButton(icon: "chevron.left", label: "Back", action: onBack)
            Text(title)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
                .kerning(0.6)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing()
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, onBack: @escaping () -> Void) {
        self.init(title: title, onBack: onBack) { EmptyView() }
    }
}

/// Small caps section label with an optional icon and caption.
struct SectionHeader: View {
    let title: String
    var icon: String?
    var caption: String?
    var tint: Color = Palette.textSecondary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(tint)
                    .kerning(1.4)
            }
            if let caption {
                Text(caption)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.textSecondary.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Mint pill switch. Same look on iOS and macOS, label on the leading edge.
struct DrillToggleStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
            Haptics.tap()
        } label: {
            HStack {
                configuration.label
                Spacer()
                Capsule()
                    .fill(configuration.isOn ? Palette.mint : Palette.panelSunken)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
                    .frame(width: 50, height: 30)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(Palette.textPrimary)
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                            .padding(3)
                    }
                    .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8),
                               value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}
