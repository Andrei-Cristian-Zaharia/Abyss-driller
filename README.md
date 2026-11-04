# Abyss Driller

Portrait arcade mining game for iPhone and iPad, written in SwiftUI (the whole game draws into one `Canvas`). See `Abyss Driller/CLAUDE.md` for architecture and conventions.

## Director mode: scripted scenarios (Debug builds only)

Debug builds can start straight into a scripted scenario with an autopilot thumb on the joystick, for recording gameplay footage. Everything lives in `Abyss Driller/Core/DirectorMode.swift` and is wrapped in `#if DEBUG`, so none of it exists in Release / App Store builds. A directed launch skips ads, consent prompts and the iCloud save, and plays on a throwaway profile that is never saved.

| Scenario | What it shows |
| --- | --- |
| `bossFight` | Drops in just above a boss arena (Crystal Golem by default) and fights it |
| `goldRush` | Deep Caves with repeated Mother Lode events and extra ore to collect |
| `caveIn` | Crystal Caves with back-to-back cave-ins |
| `deepBiome` | Jumps into a deep layer (The Void by default) and drills |
| `garageUpgrades` | Garage: buys and upgrades parts, tops up the Workshop, then drills with the new rig |

Launch arguments:

- `-scenario <name>` — one of the names above.
- `-scenarioDuration <seconds>` — how long the autopilot plays (default 20); afterwards the app just idles.
- `-scenarioLayer <index>` — `deepBiome` only: which `Strata.layers` index to jump to.
- `-scenarioBoss <index>` — `bossFight` only: which boss in the boss order to fight.

### Running locally

In Xcode: Product → Scheme → Edit Scheme… → Run → Arguments. The shared `Abyss Driller` scheme already lists `-scenario bossFight` and `-scenarioDuration 20` (disabled); tick them, change the name, and run on a simulator in the Debug configuration.

From the command line, with a booted simulator and the app installed:

```bash
xcrun simctl launch booted com.andreizaharia.abyssdriller -scenario goldRush -scenarioDuration 20
xcrun simctl io booted recordVideo --codec=h264 goldRush.mp4   # Ctrl-C to stop
```

### Recording in GitHub Actions

`.github/workflows/record-scenarios.yml` builds the Debug app for the iOS Simulator on a macOS runner, records each scenario and uploads the clips as one artifact, `scenario-clips` (`<scenario>.mp4`, kept for 1 day). It only runs when triggered by hand:

- GitHub → Actions → **Record scenarios** → **Run workflow**, optionally setting `scenarios` (comma-separated, default `all`) and `duration` (seconds, default 20).
- Or: `gh workflow run record-scenarios.yml -f scenarios=bossFight,goldRush -f duration=15`

Download the clips from the run's summary page, or with `gh run download <run-id> -n scenario-clips`.
