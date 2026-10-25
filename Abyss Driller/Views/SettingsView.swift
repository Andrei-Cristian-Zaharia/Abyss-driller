import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.stageSafeArea) private var safeArea
    @State private var confirmingReset = false
    @State private var showingMail = false

    /// Mail sheet if Mail is set up, else the default mail app, else copy the address.
    private func reportBug() {
        if BugReport.canUseMailSheet {
            showingMail = true
            return
        }
        BugReport.openMailLink(bestDepth: app.profile.bestDepth) { opened in
            if !opened {
                BugReport.copyAddress()
                app.toast = String(localized: "EMAIL COPIED: \(BugReport.address.uppercased())", bundle: .app)
            }
        }
    }

    /// The language the game is showing, named in that language.
    private var currentLanguage: String {
        app.settings.language == nil
            ? String(localized: "Device", bundle: .app, comment: "Language setting: follow the device's language")
            : AppLanguage.nativeName(AppLanguage.current)
    }

    var body: some View {
        @Bindable var app = app
        ZStack(alignment: .top) {
            MenuBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    header
                    section(String(localized: "CONTROLS", bundle: .app), icon: "hand.draw.fill") {
                        sliderRow(title: String(localized: "Steering sensitivity", bundle: .app),
                                  value: $app.settings.sensitivity,
                                  range: GameSettings.sensitivityRange,
                                  label: (app.settings.sensitivity).formatted(.percent.precision(.fractionLength(0))),
                                  hint: String(localized: "How fast the drill turns toward your thumb.", bundle: .app))
                        Divider().overlay(Palette.panelRaised)
                        sliderRow(title: String(localized: "Dead zone", bundle: .app, comment: "Joystick dead zone setting"),
                                  value: $app.settings.deadZone,
                                  range: GameSettings.deadZoneRange,
                                  label: String(localized: "\(Int(app.settings.deadZone)) pt", bundle: .app, comment: "Dead zone size in points"),
                                  hint: String(localized: "How far your thumb must move before the drill turns. Raise it if small wobbles steer you.", bundle: .app))
                        Divider().overlay(Palette.panelRaised)
                        toggleRow(String(localized: "Show joystick", bundle: .app), isOn: $app.settings.showJoystick)
                    }
                    section(String(localized: "FEEL", bundle: .app, comment: "Settings section: sound, music, haptics"), icon: "sparkles") {
                        toggleRow(String(localized: "Sound effects", bundle: .app), isOn: $app.settings.sound)
                        toggleRow(String(localized: "Music", bundle: .app), isOn: $app.settings.music)
                        toggleRow(String(localized: "Haptics", bundle: .app), isOn: $app.settings.haptics)
                        Divider().overlay(Palette.panelRaised)
                        toggleRow(String(localized: "Screen shake", bundle: .app), isOn: $app.settings.screenShake)
                    }
                    if app.ads.privacyOptionsRequired {
                        section(String(localized: "PRIVACY", bundle: .app), icon: "hand.raised.fill") {
                            Button {
                                app.ads.presentPrivacyOptions()
                            } label: {
                                HStack {
                                    Text("Privacy choices")
                                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                                        .foregroundStyle(Palette.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Palette.textSecondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Review how ads use your data")
                        }
                    }
                    section(String(localized: "HELP", bundle: .app), icon: "sparkles") {
                        Menu {
                            Picker(selection: $app.settings.language) {
                                Text("Device language", comment: "Language setting: follow the device's language")
                                    .tag(String?.none)
                                ForEach(AppLanguage.supported, id: \.self) { code in
                                    Text(verbatim: AppLanguage.nativeName(code)).tag(Optional(code))
                                }
                            } label: { EmptyView() }
                        } label: {
                            HStack {
                                Text("Language")
                                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Palette.textPrimary)
                                Spacer()
                                Text(currentLanguage)
                                    .font(.system(size: 13, weight: .black, design: .rounded))
                                    .foregroundStyle(Palette.mint)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Language"))
                        .accessibilityValue(Text(verbatim: currentLanguage))
                        Divider().overlay(Palette.panelRaised)
                        Button {
                            app.screen = .howToPlay
                        } label: {
                            HStack {
                                Text("How to Play")
                                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Palette.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Explains every rule, perk and biome")
                        Divider().overlay(Palette.panelRaised)
                        Button {
                            reportBug()
                        } label: {
                            HStack {
                                Text("Report a bug")
                                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Palette.textPrimary)
                                Spacer()
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens an email to the developer with your device details filled in")
                    }
                    SecondaryButton(title: String(localized: "RESET TO DEFAULTS", bundle: .app), icon: "arrow.counterclockwise") {
                        // Controls and feel only: a reset shouldn't switch the language.
                        var defaults = GameSettings()
                        defaults.language = app.settings.language
                        app.settings = defaults
                        Haptics.tap()
                    }
                    #if DEBUG
                    // Development only: never in TestFlight / App Store builds.
                    testingSection
                    #endif
                    Spacer(minLength: 10)
                }
                .padding(.horizontal, 18)
                .padding(.top, safeArea.top + 6)
                .padding(.bottom, safeArea.bottom + 24)
            }

            if let toast = app.toast {
                ToastBanner(text: toast)
                    .padding(.top, safeArea.top + 12)
                    .task(id: toast) {
                        try? await Task.sleep(for: .seconds(1.6))
                        app.toast = nil
                    }
            }
        }
        #if os(iOS) && canImport(MessageUI)
        .sheet(isPresented: $showingMail) {
            MailSheet(bestDepth: app.profile.bestDepth) { sent in
                showingMail = false
                if sent { app.toast = String(localized: "THANKS! REPORT SENT", bundle: .app) }
            }
            .ignoresSafeArea()
        }
        #endif
        .confirmationDialog("Reset all progress?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset Everything", role: .destructive) { app.resetProgress() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Gold, best depth, upgrades, parts, boss cores, skins and daily scores go back to a fresh start. Settings are kept. This can't be undone.")
        }
    }

    /// For playtesting: start over from a fresh install without deleting the app.
    private var testingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: String(localized: "TESTING", bundle: .app), icon: "wrench.adjustable.fill")
            Button {
                confirmingReset = true
                Haptics.bump()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 15, weight: .bold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RESET GAME")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                        Text("Wipe all progress back to a fresh start")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer()
                }
                .foregroundStyle(Palette.hazard)
                .padding(14)
                .card(18, accent: Palette.hazard.opacity(0.5))
            }
            .buttonStyle(SquishButtonStyle())
            .accessibilityHint("Asks for confirmation, then erases all progress")
        }
        .padding(.top, 6)
    }

    private var header: some View {
        ScreenHeader(title: String(localized: "SETTINGS", bundle: .app), onBack: { app.screen = .home })
    }

    private func section<Content: View>(_ title: String, icon: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title, icon: icon)
            VStack(spacing: 12) { content() }
                .padding(14)
                .card(18)
        }
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>,
                           label: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Text(label)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.mint)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
                .tint(Palette.mint)
                .accessibilityLabel(title)
                .accessibilityValue(label)
            Text(hint)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
        }
        .toggleStyle(DrillToggleStyle())
    }
}
