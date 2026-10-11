import SwiftUI

struct ContentView: View {
    @State private var app = AppModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    case .run:
                        if let world = app.world {
                            GameView(world: world)
                        } else {
                            HomeView()
                        }
                    }
                }
                .id(app.screen)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            }
            .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.25), value: app.screen)
            .environment(app)
        }
        .preferredColorScheme(.dark)
        // Consent → tracking prompt → ad SDK, then keep one rewarded ad ready.
        .task {
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
