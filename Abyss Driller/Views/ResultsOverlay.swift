import SwiftUI

/// Shown over the frozen run so "Drill Again" is one tap from where you died.
struct ResultsOverlay: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let result: RunResult
    @State private var appeared = false
    /// Rolls up from 0 so the payout lands with a little ceremony.
    @State private var shownGold = 0

    var body: some View {
        ZStack {
            Palette.background.opacity(0.84).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                card
                Spacer()
            }
            .padding(.horizontal, 22)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.78)) {
                appeared = true
            }
            let target = result.isDaily ? result.dailyScore : result.payout
            if reduceMotion {
                shownGold = target
            } else {
                withAnimation(.easeOut(duration: 0.9).delay(0.25)) { shownGold = target }
            }
        }
    }

    private var card: some View {
        VStack(spacing: 14) {
            // Why the run ended, as a badge that leads the card.
            VStack(spacing: 8) {
                Image(systemName: badgeIcon)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Palette.background)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(badgeTint))
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 2))
                    .shadow(color: badgeTint.opacity(0.5), radius: 12)
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.4)
                Text(result.newRecord ? String(localized: "NEW RECORD!", bundle: .app) : headline)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(result.newRecord ? Palette.gold : Palette.textPrimary)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 0) {
                StatBlock(caption: String(localized: "DEPTH", bundle: .app), value: String(localized: "\(result.depth) m", bundle: .app, comment: "Depth in metres"),
                          tint: result.newRecord ? Palette.gold : Palette.textPrimary)
                    .frame(maxWidth: .infinity)
                Rectangle().fill(Palette.panelRaised).frame(width: 1, height: 40)
                VStack(spacing: 2) {
                    Text(result.isDaily ? String(localized: "SCORE", bundle: .app) : String(localized: "GOLD", bundle: .app))
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.textSecondary)
                    Text("\(shownGold)")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(Palette.gold)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(shownGold)))
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(result.isDaily ? String(localized: "Score \(result.dailyScore)", bundle: .app) : String(localized: "Gold \(result.payout)", bundle: .app))
            }

            if !result.newRecord, !result.isDaily, result.previousBest > 0 {
                Text("BEST \(result.previousBest) m")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.textSecondary)
            }

            ForEach(result.coreProgress, id: \.boss) { item in
                let part = ShipPart.drop(for: item.boss)
                HStack(spacing: 10) {
                    Image(systemName: part.icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(item.boss.tint)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Palette.panelSunken))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(item.boss.title) CORES \(item.cores)/\(ShipPart.coresToUnlock)", comment: "Boss name, cores collected / cores needed")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(Palette.textPrimary)
                        CoreBar(value: item.cores, tint: item.boss.tint)
                        Text("\(ShipPart.coresToUnlock - item.cores) more to unlock \(part.title)", comment: "Number of boss cores still needed, then the part name")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(item.boss.tint.opacity(0.5), lineWidth: 1.5))
            }

            ForEach(result.newParts) { part in
                HStack(spacing: 10) {
                    Image(systemName: part.icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(part.tint)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Palette.panelSunken))
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text("NOW FOR SALE · \(part.title.localizedUppercase)")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundStyle(part.rarity.color)
                            RarityTag(rarity: part.rarity)
                        }
                        Text("\(part.detail(level: 1)) · buy it in the Garage for \((part.buyPrice ?? 0).formatted()) gold", comment: "Part stats, then its price")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Palette.gold.opacity(0.6), lineWidth: 1.5))
            }

            // Where the gold came from: the hold sold at the surface, plus coins.
            VStack(spacing: 5) {
                earningsRow(icon: "shippingbox.fill", tint: Palette.gem,
                            label: String(localized: "Ore sold · \(result.oreCount) pieces", bundle: .app),
                            value: result.oreValue)
                earningsRow(icon: "dollarsign.circle.fill", tint: Palette.gold,
                            label: String(localized: "Bounties & treasure", bundle: .app), value: result.coins)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.panelSunken))

            VStack(spacing: 7) {
                if result.gems > 0 {
                    detailRow(icon: "diamond.fill", tint: Palette.gem,
                              text: String(localized: "\(result.gems) rare gems", bundle: .app))
                }
                if result.bestCombo >= 10 {
                    detailRow(icon: "flame.fill", tint: Palette.drillBody,
                              text: String(localized: "Best combo \(result.bestCombo)", bundle: .app))
                }
                if !result.newEntries.isEmpty {
                    detailRow(icon: "book.closed.fill", tint: Palette.paper,
                              text: String(localized: "\(result.newEntries.count) new Field Guide entries", bundle: .app))
                }
                if result.bossesDefeated > 0 {
                    detailRow(icon: "crown.fill", tint: Palette.gold,
                              text: String(localized: "\(result.bossesDefeated) bosses defeated", bundle: .app))
                }
                if result.enemiesDefeated > 0 {
                    detailRow(icon: "ant.fill", tint: Palette.worm,
                              text: String(localized: "\(result.enemiesDefeated) critters squashed", bundle: .app))
                }
                if result.chambers > 0 {
                    detailRow(icon: "shippingbox.fill", tint: Palette.gold,
                              text: String(localized: "\(result.chambers) treasure chambers", bundle: .app))
                }
                if app.profile.doubleGold, !result.isDaily {
                    detailRow(icon: "multiply.circle.fill", tint: Palette.mint,
                              text: String(localized: "Double gold applied", bundle: .app))
                }
                if result.cargoOverflowed {
                    detailRow(icon: "exclamationmark.triangle.fill", tint: Palette.hazard,
                              text: String(localized: "Hold filled up — a bigger hold sells for more", bundle: .app))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 9) {
                PrimaryButton(title: String(localized: "DRILL AGAIN", bundle: .app), icon: "arrow.clockwise") {
                    app.drillAgain()
                }
                HStack(spacing: 9) {
                    SecondaryButton(title: result.cargoOverflowed ? String(localized: "UPGRADE CARGO", bundle: .app) : String(localized: "UPGRADE", bundle: .app),
                                    icon: "wrench.and.screwdriver.fill") {
                        app.leaveResultsHome()
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(20)
        .card(26)
        .scaleEffect(appeared ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
    }

    private var badgeIcon: String {
        if result.newRecord { return "trophy.fill" }
        if result.isDaily { return "calendar.badge.checkmark" }
        switch result.reason {
        case .outOfFuel: return "fuelpump.slash.fill"
        case .wrecked: return "wrench.adjustable.fill"
        }
    }

    private var badgeTint: Color {
        if result.newRecord { return Palette.gold }
        if result.isDaily { return Palette.gem }
        switch result.reason {
        case .outOfFuel: return Palette.mint
        case .wrecked: return Palette.hazard
        }
    }

    private var headline: String {
        if result.isDaily { return String(localized: "DAILY CHALLENGE COMPLETE", bundle: .app) }
        switch result.reason {
        case .outOfFuel: return String(localized: "OUT OF FUEL", bundle: .app)
        case .wrecked: return String(localized: "DRILL WRECKED", bundle: .app)
        }
    }

    private func earningsRow(icon: String, tint: Color, label: String, value: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            Text("+\(value)")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func detailRow(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.textSecondary)
            Spacer()
        }
    }
}
