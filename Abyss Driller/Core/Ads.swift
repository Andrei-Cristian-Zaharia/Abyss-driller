import SwiftUI
#if os(iOS) && canImport(GoogleMobileAds)
import GoogleMobileAds
import UserMessagingPlatform
import AppTrackingTransparency
import UIKit
#endif

/// Ad unit IDs. Debug builds use Google's public test unit, which always
/// serves a labelled test ad, so tapping ads while developing can never count
/// as invalid traffic on the real account. Release builds (TestFlight, App
/// Store) use the real units from the AdMob app (created as "Drill Down").
enum AdConfig {
    #if DEBUG
    static let rewardedUnitID = "ca-app-pub-3940256099942544/1712485313"       // Google test unit
    static let interstitialUnitID = "ca-app-pub-3940256099942544/4411468910"   // Google test unit
    #else
    static let rewardedUnitID = "ca-app-pub-8505602361918016/9370180367"       // Abyss Driller · Rewarded
    static let interstitialUnitID = "ca-app-pub-8505602361918016/7927834662"   // Abyss Driller · Interstitial
    #endif
    /// Interstitial pacing (see `AppModel.leaveResults`): none until a player
    /// has finished this many runs ever…
    static let interstitialFreeRuns = 5
    /// …then at most one per this many runs…
    static let interstitialEveryRuns = 3
    /// …and never sooner than this after any full-screen ad, rewarded included.
    static let interstitialGap: Duration = .seconds(240)
    /// How long a tap on "watch ad" waits for one to finish loading before
    /// the reward is granted anyway.
    static let loadGrace: Duration = .seconds(3)
}

/// Rewarded ads (fuel refill, free Workshop upgrade) and one interstitial
/// between runs. Start-up runs consent (Google UMP, EU/UK only), then Apple's
/// tracking prompt, then the SDK, and keeps one of each ad preloaded. On platforms without the SDK (macOS,
/// visionOS) every request is simply granted.
@Observable
final class AdsManager {
    enum State: Equatable { case idle, loading, ready, showing, unavailable }

    private(set) var state: State = .idle
    /// True when the consent framework says the player must be able to
    /// revisit their choices (shown as a row in Settings).
    private(set) var privacyOptionsRequired = false
    /// When the last full-screen ad (of either kind) closed; interstitials
    /// keep their distance from it.
    private(set) var lastAdClosed: ContinuousClock.Instant?

    /// False where the SDK does not exist (macOS, visionOS); ad offers that
    /// would otherwise do nothing are hidden there.
    var isSupported: Bool {
        #if os(iOS) && canImport(GoogleMobileAds)
        return true
        #else
        return false
        #endif
    }

    #if os(iOS) && canImport(GoogleMobileAds)
    private var rewarded: RewardedAd?
    private let delegate = FullScreenDelegate()
    private var interstitial: InterstitialAd?
    private var interstitialLoading = false
    private let interstitialDelegate = FullScreenDelegate()
    private var started = false
    /// Set by the SDK's reward callback; read when the ad closes.
    private var earned = false
    #endif

    // MARK: Start-up

    func start() {
        #if os(iOS) && canImport(GoogleMobileAds)
        guard !started else { return }
        started = true
        // Consent from a previous launch is cached, so ads can start loading
        // straight away while the consent check below runs.
        if ConsentInformation.shared.canRequestAds { Task { await startSDK() } }
        Task {
            try? await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            try? await ConsentForm.loadAndPresentIfRequired(from: Self.topViewController())
            privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
            // The tracking prompt only shows while the app is active; asking a
            // moment after consent avoids it being swallowed during launch.
            try? await Task.sleep(for: .milliseconds(400))
            if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
                _ = await ATTrackingManager.requestTrackingAuthorization()
            }
            await startSDK()
        }
        #else
        state = .unavailable
        #endif
    }

    #if os(iOS) && canImport(GoogleMobileAds)
    private var sdkStarted = false

    private func startSDK() async {
        guard ConsentInformation.shared.canRequestAds, !sdkStarted else { return }
        sdkStarted = true
        _ = await MobileAds.shared.start()
        Task { await loadInterstitial() }
        await load()
    }

    private func loadInterstitial() async {
        guard interstitial == nil, !interstitialLoading else { return }
        interstitialLoading = true
        defer { interstitialLoading = false }
        do {
            interstitial = try await InterstitialAd.load(with: AdConfig.interstitialUnitID, request: Request())
        } catch {
            interstitial = nil
        }
    }

    private func load() async {
        guard state != .loading, state != .ready, state != .showing else { return }
        state = .loading
        do {
            rewarded = try await RewardedAd.load(with: AdConfig.rewardedUnitID, request: Request())
            state = .ready
        } catch {
            rewarded = nil
            state = .unavailable
            // A no-fill now is often fine in a minute; try again later.
            try? await Task.sleep(for: .seconds(30))
            if state == .unavailable {
                state = .idle
                await load()
            }
        }
    }
    #endif

    // MARK: Showing

    /// Shows a rewarded ad and calls `granted` once the player has earned the
    /// reward and closed it. If no ad can be shown (none loaded in time, no
    /// SDK on this platform), `granted` is called anyway with `watched: false`,
    /// so a player is never stuck without the refill they asked for.
    func showRewarded(_ granted: @escaping (_ watched: Bool) -> Void) {
        #if os(iOS) && canImport(GoogleMobileAds)
        Task {
            if state != .ready {
                if state == .idle || state == .unavailable { Task { await load() } }
                let deadline = ContinuousClock.now + AdConfig.loadGrace
                while state != .ready, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            guard state == .ready, let ad = rewarded, let root = Self.topViewController() else {
                granted(false)
                return
            }
            state = .showing
            earned = false
            delegate.onFinish = {
                Task {
                    self.rewarded = nil
                    self.state = .idle
                    self.lastAdClosed = .now
                    // Reward on close, so the run resumes after the ad is gone.
                    granted(self.earned)
                    await self.load()
                }
            }
            ad.fullScreenContentDelegate = delegate
            ad.present(from: root) {
                Task { self.earned = true }
            }
        }
        #else
        granted(false)
        #endif
    }

    /// Shows the between-runs interstitial if one is loaded, then calls
    /// `done` once it closes. Never waits: with nothing loaded (or no SDK),
    /// `done` runs at once and another ad is fetched for next time.
    func showInterstitial(_ done: @escaping () -> Void) {
        #if os(iOS) && canImport(GoogleMobileAds)
        guard let ad = interstitial, state != .showing, let root = Self.topViewController() else {
            if sdkStarted { Task { await loadInterstitial() } }
            done()
            return
        }
        interstitial = nil
        interstitialDelegate.onFinish = {
            Task {
                self.lastAdClosed = .now
                done()
                await self.loadInterstitial()
            }
        }
        ad.fullScreenContentDelegate = interstitialDelegate
        ad.present(from: root)
        #else
        done()
        #endif
    }

    /// Re-opens the consent form (Settings → Privacy choices).
    func presentPrivacyOptions() {
        #if os(iOS) && canImport(GoogleMobileAds)
        ConsentForm.presentPrivacyOptionsForm(from: Self.topViewController()) { _ in }
        #endif
    }

    #if os(iOS) && canImport(GoogleMobileAds)
    /// The view controller ads and consent forms present over.
    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
            ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
    #endif
}

#if os(iOS) && canImport(GoogleMobileAds)
/// Full-screen callbacks need an NSObject; this forwards the end of the ad
/// (closed, or failed to present) to whoever is waiting.
private final class FullScreenDelegate: NSObject, FullScreenContentDelegate {
    var onFinish: (() -> Void)?

    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        onFinish?()
        onFinish = nil
    }

    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        onFinish?()
        onFinish = nil
    }
}
#endif
