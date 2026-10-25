import SwiftUI

struct ContentView: View {
    @State private var app = AppModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        PortraitStage {
            ZStack {
                Group {
                    switch app.screen {
                    case .home:
                        HomeView()
                    case .shop:
                        ShopView()
                    case .garage:
                        GarageView()
                    case .settings:
                        SettingsView()
                    case .fieldGuide:
                        FieldGuideView()
                    case .howToPlay:
                        HowToPlayView()
                    case .run:
                        if let world = app.world {
                            GameView(world: world)
                        } else {
                            HomeView()
                        }
                    }
                }
                .id(app.screen)
                // Rebuild the screen in a newly picked language: views that
                // localize through `String(localized:)` don't watch the locale.
                .id(app.settings.language)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            }
            .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.25), value: app.screen)
            // Menus get the menu theme; a run picks its own track every frame.
            .onChange(of: app.screen) { _, screen in
                if screen != .run { Audio.shared.play(.menu) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Audio.shared.resume() }
            }
            .environment(app)
            .environment(\.locale, AppLanguage.locale)
        }
        .preferredColorScheme(.dark)
        // Consent → tracking prompt → ad SDK, then keep one rewarded ad ready.
        .task {
            CloudSave.observe { cloud in app.mergeCloudSave(cloud) }
            Audio.shared.start()
            Audio.shared.play(app.screen == .run ? .biome(0) : .menu)
            if !app.adsRemoved { app.ads.start() }
            app.store.start()     // prices, purchase updates, restored entitlements
        }
        #if DEBUG
        // Screenshot/automation hook: `-autoDrill` opens straight into a run.
        // There is no test target, so this is how the run screen gets verified
        // against real device safe areas.
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-autoDrill"), app.screen == .home {
                app.startRun()
            }
        }
        #endif
        #if os(iOS)
        .statusBarHidden(app.screen == .run)
        #endif
    }
}

#Preview("Home") {
    ContentView()
}
