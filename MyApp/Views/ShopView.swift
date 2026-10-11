import SwiftUI

struct ShopView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stageSafeArea) private var safeArea

    var body: some View {
        ZStack(alignment: .top) {
            MenuBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    header
                    if !app.ownsBundle { bundleCard }
                    goldSection
                    permanentSection
                    skinSection
                    Button {
                        app.restorePurchases()
                        Haptics.tap()
                    } label: {
                        Text("Restore Purchases")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(Palette.textSecondary)
                            .underline()
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Re-downloads Double Gold, Remove Ads, the Mega Bundle and paint jobs you already bought")
                    Spacer(minLength: 10)
                }
                .padding(.horizontal, 18)
                .padding(.top, safeArea.top + 6)
                .padding(.bottom, safeArea.bottom + 24)
            }

            if let toast = app.toast {
                ToastBanner(text: toast)
                    .padding(.top, safeArea.top + 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast) {
                        try? await Task.sleep(for: .seconds(1.6))
                        app.toast = nil
                    }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: app.toast)
        // Launch may have been offline: fetch any prices still missing.
        .task {
            if !app.store.hasAllProducts { await app.store.loadProducts() }
        }
    }

    private var header: some View {
        ScreenHeader(title: "SUPPLY DEPOT", onBack: { app.screen = .home }) {
            GoldPill(amount: app.profile.gold, compact: true)
        }
    }

    private var goldSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("GOLD PACKS", caption: "Grows with your upgrades")
            ForEach(ShopCatalog.goldPacks(levels: app.profile.levels)) { pack in
                Button {
                    if let product = StoreProduct.forGoldPack(pack.id) { app.purchase(product) }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Palette.gold).frame(width: 36)
                            Circle().fill(Palette.goldShadow).frame(width: 17)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(pack.amount) GOLD")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .foregroundStyle(Palette.textPrimary)
                            if let tag = pack.tag {
                                Text(tag)
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Palette.mint)
                            }
                        }
                        Spacer()
                        PriceTag(product: StoreProduct.forGoldPack(pack.id), fallback: pack.price)
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(Palette.background)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Palette.mint))
                    }
                    .padding(13)
                    .card(18)
                }
                .buttonStyle(SquishButtonStyle())
            }
        }
    }

    /// Featured offer: everything permanent plus gold, for less than half.
    private var bundleCard: some View {
        let gold = ShopCatalog.goldPacks(levels: app.profile.levels).last?.amount ?? 0
        let skin = DrillSkin.skin(id: ShopCatalog.bundleSkinID)
        return Button {
            app.purchase(.megaBundle)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("MEGA BUNDLE")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(Palette.gold)
                    Spacer()
                    Text("WORTH \(ShopCatalog.bundleWorth)")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(Palette.background)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Palette.hazard))
                }
                HStack(spacing: 12) {
                    Canvas { ctx, size in
                        DrillArt.draw(in: ctx, center: CGPoint(x: size.width / 2, y: size.height / 2 - 2), scale: 30,
                                      spin: 0, tilt: 0, levels: UpgradeLevels(), skin: skin, headlight: false, reduceMotion: true)
                    }
                    .frame(width: 70, height: 74)
                    VStack(alignment: .leading, spacing: 5) {
                        bundleLine("multiply.circle.fill", "Double Gold forever")
                        bundleLine("nosign", "No ads · rewards are instant")
                        bundleLine("circle.fill", "\(gold.formatted()) gold")
                        bundleLine("paintbrush.fill", "\(skin.name) paint")
                    }
                    Spacer(minLength: 0)
                }
                PriceTag(product: .megaBundle, fallback: ShopCatalog.megaBundlePrice)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Palette.gold))
            }
            .padding(14)
            .card(20, accent: Palette.gold)
        }
        .buttonStyle(SquishButtonStyle())
    }

    private func bundleLine(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.gold)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
        }
    }

    private var permanentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("PERMANENT", caption: "One-time purchase")
            permanentRow(icon: "multiply.circle.fill", title: "DOUBLE GOLD", caption: "Every run pays twice, forever",
                         owned: app.profile.doubleGold, product: .doubleGold, fallback: ShopCatalog.doubleGoldPrice)
            permanentRow(icon: "nosign", title: "REMOVE ADS", caption: "Skip every ad, still get the reward",
                         owned: app.profile.adsRemoved, product: .removeAds, fallback: ShopCatalog.removeAdsPrice)
        }
    }

    private func permanentRow(icon: String, title: String, caption: String, owned: Bool,
                              product: StoreProduct, fallback: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Palette.mint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                Text(caption)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            if owned {
                Text("OWNED")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.mint)
            } else {
                Button {
                    app.purchase(product)
                } label: {
                    PriceTag(product: product, fallback: fallback)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(Palette.background)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Palette.mint))
                }
                .buttonStyle(SquishButtonStyle())
            }
        }
        .padding(13)
        .card(18)
    }

    private var skinSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("PAINT SHOP", caption: "Cosmetic only — never changes a stat")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(DrillSkin.all) { skin in
                        SkinCard(skin: skin)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func sectionTitle(_ title: String, caption: String) -> some View {
        SectionHeader(title: title, caption: caption)
    }
}

private struct SkinCard: View {
    @Environment(AppModel.self) private var app
    let skin: DrillSkin

    private var owned: Bool { app.owns(skin) }
    private var selected: Bool { app.profile.selectedSkin == skin.id }

    var body: some View {
        Button {
            if owned { app.selectSkin(skin) } else if let product = StoreProduct.forSkin(skin.id) { app.purchase(product) }
        } label: {
            VStack(spacing: 8) {
                Canvas { ctx, size in
                    DrillArt.draw(in: ctx,
                                  center: CGPoint(x: size.width / 2, y: size.height / 2 - 4),
                                  scale: 34,
                                  spin: 0,
                                  tilt: 0,
                                  levels: UpgradeLevels(),
                                  skin: skin,
                                  headlight: false,
                                  reduceMotion: true)
                }
                .frame(width: 96, height: 84)

                Text(skin.name.uppercased())
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(selected ? "EQUIPPED" : (owned ? "EQUIP" : StoreProduct.forSkin(skin.id).map { app.store.price($0, fallback: skin.price) } ?? skin.price))
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(selected ? Palette.background : Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(selected ? Palette.mint : Palette.panelRaised))
            }
            .padding(10)
            .frame(width: 120)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Palette.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(selected ? Palette.mint : .clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(SquishButtonStyle())
    }
}

/// App Store price for a product (localised), or a spinner while buying it.
private struct PriceTag: View {
    @Environment(AppModel.self) private var app
    let product: StoreProduct?
    let fallback: String

    var body: some View {
        if let product, app.store.purchasing == product {
            ProgressView()
                .controlSize(.small)
                .tint(Palette.background)
        } else {
            Text(product.map { app.store.price($0, fallback: fallback) } ?? fallback)
        }
    }
}
