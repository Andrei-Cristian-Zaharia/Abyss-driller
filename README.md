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

- `-scenario <name>` — one of the names above, or `random` (the seed picks one).
- `-scenarioSeed <number>` — seeds the moment (biome, depth, boss and its HP, rig, perks, fuel, coins, events, early dig / mid run / near death / overdrive), the shaft and the autopilot's moves (zig-zags, dives, sweeps, swirls, hooks, bursts, short lifts). The same seed gives the same set-up and move plan; without one, the clock picks it.
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

For smooth 60 fps footage on any machine, add `-scenarioCapture <seconds>`: the app then runs the game on a virtual clock (exactly 1/60 s per frame), captures every drawn frame itself and writes `Documents/DirectorCapture/capture.mp4` in its data container (`xcrun simctl get_app_container booted com.andreizaharia.abyssdriller data`); the log ends with `[Director] CAPTURE done …`. A screen recording of a GPU-less CI simulator only gets the ~30 frames per second it can draw in real time, which is why CI uses this mode.

### Recording in GitHub Actions

`.github/workflows/record-scenarios.yml` builds the Debug app for the iOS Simulator on a macOS runner, records each scenario and uploads the clips as one artifact, `scenario-clips` (`<scenario>_seed<seed>.mp4` plus `manifest.json`, kept for 1 day). It only runs when triggered by hand:

- GitHub → Actions → **Record scenarios** → **Run workflow**, optionally setting `scenario` (`random` by default, one type, a comma list, or `all`), `count` (clips, default 5), `seed` (blank = a new seed every run) and `duration`.
- Or: `gh workflow run record-scenarios.yml -f scenario=random -f count=5` (reproduce one clip: `-f seed=<its seed> -f count=1 -f scenario=<same scenario input>`).

Each run logs its base seed (a notice on the run page); clip *i* uses seed + *i* and is named `<scenario>_seed<seed>.mp4`. `manifest.json` next to the clips lists every clip's seed, scenario, parameters, movement pattern and validation result. A clip whose scenario + parameters repeat an earlier clip of the same run is re-rolled with another seed before recording (up to 6 times, then skipped).

Clips are 1080x1920 H.264 at 60 fps, captured offline with `-scenarioCapture` (slower than real time on the runner, so a run takes longer, but the clip plays at normal speed). Validation logs each clip's declared fps and its real fps (unique frames per second in the world area, via mpdecimate, from the first frame of the run) and fails any clip under `MIN_UNIQUE_FPS` (55), alongside the existing decode, size, duration and frozen-world checks.

Download the clips from the run's summary page, or with `gh run download <run-id> -n scenario-clips`.
