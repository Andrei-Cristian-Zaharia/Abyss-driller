# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Abyss Driller** (App Store: *Abyss Driller: Dig & Mine*; working title was Drill Down) — a portrait mobile arcade game. You hold the screen to drill underground, steer around rock, collect gold, and spend it on four permanent upgrades. Runs last roughly 30–90 seconds. SwiftUI only; the whole game renders into a single `Canvas`. No SpriteKit. The only third-party package is Google Mobile Ads (AdMob, which brings in Google's UMP consent library), iOS only.

## Project layout

The sources live in `MyApp/`; the Xcode project is one level **up**:

```
Untitled Project/
├── Untitled Project.xcodeproj   ← run xcodebuild from here
└── MyApp/                       ← sources (this directory)
    ├── MyApp.swift              @main App
    ├── ContentView.swift        screen router (home / run / shop / garage / settings / field guide)
    ├── Core/                    palette, seeded RNG, haptics, shared UI parts
    ├── Model/                   profile, upgrades, skins, shop, AppModel
    ├── Game/                    entities + the simulation
    ├── Render/                  Canvas drawing (no game state is mutated here)
    └── Views/                   HomeView, GameView, ResultsOverlay, ShopView, GarageView, SettingsView, FieldGuideView
```

Project name is `Untitled Project`; the single target and scheme are both `MyApp`.

## Commands

Run from the parent directory. The app is **iPhone + iPad only**:

```bash
cd "/Users/azaharia/Library/Developer/Xcode/UntitledProjects/Untitled Project"

# compile check without a device or simulator
xcodebuild -project "Untitled Project.xcodeproj" -scheme MyApp -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO

# Release configuration (what TestFlight / App Store get)
xcodebuild -project "Untitled Project.xcodeproj" -scheme MyApp -destination 'generic/platform=iOS' -configuration Release build CODE_SIGNING_ALLOWED=NO
```

There is no test target and no linter. The deployment target is iOS 18, so any installed iOS 18+ simulator runtime can run it; the offscreen macOS harness below still works for visual checks because it compiles the sources directly with `swiftc`, not through the project.

### Seeing the game without a simulator

The game sources compile as a plain library, so screens can be rendered to PNG offscreen — this is how the art was iterated on:

```bash
cd MyApp
SRC=(Core/*.swift Model/*.swift Game/*.swift Render/*.swift Views/*.swift)
xcrun swiftc -O -swift-version 5 -target arm64-apple-macos27.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -o /tmp/tool "${SRC[@]}" your_main.swift -framework SwiftUI -framework AppKit
```

Drive `GameWorld` directly (`setCanvasFrame`, `beginIfNeeded`, `isHolding`, `steerTarget`, then `tick(t)` in 1/60 steps), then capture through an `NSHostingView` in a borderless `NSWindow` — `ImageRenderer` silently renders `ScrollView` content as empty, so it is not usable for the home and shop screens.

## Architecture

**`GameWorld` (Game/GameWorld.swift) is the whole simulation and is deliberately NOT `@Observable`.** The view redraws every frame from a `TimelineView`, so per-property observation would be pure overhead. It follows that:

- `GameView` advances the sim from `.onChange(of: context.date)` inside the `TimelineView`, and the HUD lives *inside* that closure so it refreshes with the canvas.
- The run ends through the `onEnd` callback, not by the view polling `phase`. `AppModel.startRun` wires it up.
- `GameRenderer` never mutates `GameWorld`. Keep it that way — it is the only reason frame rendering is safe to reorder.

**Fixed timestep.** `tick(_:)` accumulates real time and steps `advance(_:)` at 1/120 s (max 16 steps). Collision tuning assumes that rate.

**World units are metres, `y` is depth.** The shaft is `shaftWidth` (10 m) across and maps to the full screen width, so `scale = size.width / 10`. The camera keeps the drill at `cameraAnchor` (0.33) down the screen.

**Determinism.** All generation goes through `SeededRandom` (SplitMix64). The same seed reproduces a whole shaft, which is what makes the daily challenge fair — `verify` style tools rely on this. Never introduce `Int.random` into generation.

**Balance numbers live in two places only:** `UpgradeTrack` (costs and resolved stats) in `Model/Upgrades.swift`, and the `static let` tuning block at the top of `GameWorld`. Layer depths and treasure values are in `Strata` (`Core/Palette.swift`).

### Gameplay rules worth knowing before editing

- Rock hardness is `kind.baseHardness + layerIndex`; a rock is drillable when `hardness <= loadout.power`. **Geodes are `Int.max` — never drillable**, which is what keeps Armor relevant at max Power.
- **Combo / Overdrive.** Pickups, rock smashes, fuel cans and near misses (passing a coral-rimmed rock within `nearMissGap`) each add 1 to `combo`; it drops after `comboWindow` seconds idle or on any hit. Gold is multiplied by `comboMultiplier` (x1–x4, one step per `comboStep`). Every `overdriveCombo` combo *earned outside Overdrive* fires Overdrive (`overdriveBase` stops it chaining into itself): faster, no fuel burn, and **everything shatters, geodes included** — the one exception to the rule above, deliberately short.
- **Free digging.** The drill moves along `heading` (0 = down, direction `(-sin, cos)`) and turns toward `steerVector` at `turnRate`. `GameView` feeds that from a floating joystick; holding without dragging keeps the current heading. The bit (`bitPoint`) is always at the front, so collisions, dust and near misses all follow the heading. The surface (`depth 0`) is a ceiling, and pruning keeps 30 m above the camera so the player can turn back up.
- Critter density and speed keep rising past 520 m via `danger` (to ×2 depth factor), after the rest of the difficulty curve tops out.
- Speed ramps from `descentSpeed` to `topSpeed` over `speedRampDepth`, in whatever direction the drill is heading.
- **Enemies** (`Enemy`, spawned per band from `rng`, AI never uses `rng`). Every biome has two native kinds plus a few from the biome above; the weighted table (`pick`) is in `generateBand`. Natives: Surface worm + **mole** (untouchable while underground, `Enemy.surfaced`); Shallow bat + **cave spider** (silk anchor is `homeY`); Deep beetle + **centipede** (armoured segments hurt the hull and clank the bit; only the head dies); Crystal spitter + **prism slime** (splits into two `small` slimes, which spawn beside the bit with a brief guard so they don't pop instantly); Magma ember + **fire slug** (drops temporary `LavaPool`s); Abyss jelly + angler; Ruins **scarab** (spawns as a pack of three with fixed offsets, no extra `rng`; patrol → `windup` tell → one rush → burrows away) + **tomb wraith** (drifts through rock, flickering: `.recover` is its faded phase, untouchable via `surfaced`); Frozen **frost wisp** (swells, then a nova that chills within `frostNovaRadius`; it bursts like an ember) + **ice urchin** (speed 0; fires a ring of `.frost` shots, each ring rotated so the gap moves); Spore **spore puff** (speed 0; inflates, then drops a poison cloud) + **bog toad** (hops; `windup` locks its aim and draws the tongue line, then a hit within `tongueReach` yanks the drill via `vx`/`vy` + `stun` and poisons); Void **singularity** (speed 0; adds to `wellPull`, rebuilt each step in `updateEnemies`, pulling within `wellRadius`; its core hurts, the bit pops it) + **void imp** (`windup` fades out, reappears 2.6 m from the drill at an angle from its phase and the clock, pauses in `.recover` with a ring as the tell, then lunges in `.attack`). Use `enemy.radius`, not `kind.radius`, for collisions. Original signature behaviours:
  - Surface: **worm** — chases within `wormSight`, dies to the bit.
  - Shallow Caves: **bat** — patrol → `windup` (shiver, the tell) → committed straight dive → `recover` home.
  - Deep Caves: **beetle** — patrols a row; rock-style hardness (`2 + layerIndex`) with the same coral rim when the bit can't crack it.
  - Crystal Caves: **spitter** — roots, glows, fires a `Shot`. The bit blocks shots (+combo); rock stops them.
  Touching the hull costs 1 armour. Overdrive smashes all of them.
- **Bosses** (`Game/Bosses.swift`) guard the last `arenaHeight` metres of each biome (boundaries from `Strata`, then 480 m and every 150 m after). Generation keeps arenas clear via `inArena`; `clampToArena` holds the drill above a bedrock seal until the boss dies. Kinds cycle Worm Queen → Bat Matriarch → Beetle Tank (only hurt dazed or from behind) → Crystal Golem → Magma Titan, +2 HP per lap. After a hit a boss is immune *and harmless* for `bossHitGuard`; without the harmless part, following up a hit got punished and every rig died.
  - **Three powers each**, picked by `nextPower`: two in rotation, the third joins when the boss **enrages at half HP**. Queen: lunge / burrow / brood. Matriarch: dive / swarm / screech (ring with a `screechGap`). Beetle: charge / rock rain / mines (temporary geodes in `boss.mines`). Golem: fan / ring / seekers (`ShotStyle.homing`). Titan: geysers / fireballs / magma flood (temporary `LavaPool`s with `life` and `warmup`).
  - **A hit must not reset the power rotation** (only a lunge or dive gets knocked off course), or steady hits stun-lock a boss on its first power. The Queen's body only bites while she is attacking; otherwise it shoves.
  - Stone Pharaoh (Ancient Ruins, 930 m): eye beam (`boss.beamRow` tracks the drill's row, locks for the last 0.6 s, then hurts within `pharaohBeamHalf`) / scarab swarm / sandstorm (enraged: sets `world.bossPull`, a drift added in `stepDrill`, and `boss.sandstorm` makes it invulnerable). Drops **Pharaoh's Shroud** (hull: armour, `killGold`, `oreBonus`).
  - Frost Wyrm (Frozen Depths, 1080 m): segmented like the Queen (body shoves, never bites) / ice breath (3 `.frost` shots) / frost field (`LavaPool` with `frost = true`: chills instead of burning, warmup ring first) / blizzard (enraged: `boss.blizzard` drops `.icicle` shots, which behave like cave-in boulders, plus a snow overlay). Drops **Frost Runners** (tracks: speed, turning, `chillImmune`).
  - Sporemother (Spore Hollow, 1230 m): spore volley (5 `.spore` shots lobbed at fixed offsets round the drill; they never collide in flight, and on landing spawn a poison cloud, hurting only if they land within 0.95 m of the drill) / root snare (`boss.mark` follows then locks; roots hurt within `snareRadius`) / bloom (enraged: spawns spore puffs). A fuel-pressure boss: poison costs about half a tank per fight. Drops **Spore Filter** (module: `poisonImmune`, less fuel burn).
  - Star Eater (The Void, 1380 m): starfall (three spiral arms of `.star` shots from its rim) / black hole (`boss.hole` + `holeTime`: opened on the far side of the drill, pulls through `bossPull`, its core hurts) / blink strike (enraged: `blinkSpot` marked with a ring, then teleport + lunge, twice). The hardest boss. Drops **Void Drill** (bit: bigger bite, +1 Power at Mk III, `gravityImmune`, which also cancels singularities and the Pharaoh's sandstorm).
  - Abyss Angler (The Abyss): lunge / blackout (`boss.blackout`; the renderer darkens the arena and draws only lures on top) / jelly swarm.
  - **Boss intro** (`bossIntro`, `drawBossIntro`): when a boss engages, the world runs at `bossIntroSlowMo` for `bossIntroTime` real seconds (2.6 full / 1.5 mini) while letterbox bars, a flash, a spotlight and a paper name banner play. The boss is frozen, the drill holds still, and the drill is invulnerable; the HUD fades by `bossIntroIntensity`. The banner always runs along the bottom, just above the letterbox bar; during the intro the camera pans so the boss sits at ~42% down the screen (drill kept between 10% and 70%), keeping it clear of the banner. It replaces the old engage shout.
  - **Minis:** a boss the player has beaten before (`coresCollected > 0`, or owning its part, or killed earlier this run) returns as a mini: `radius` ×0.65, half HP, 15% faster, half coins, still +1 core. The daily passes no history, so everyone meets full bosses.
- **Perks** (`Game/Perks.swift`) are run-only: offered at `firstPerkDepth` then every `perkInterval` m (never mid-fight) and after each boss. The run switches to `RunPhase.choosing` until `choosePerk`. Offers come from `perkRNG`. Stacks are unlimited (only Diamond Bit and Spiked Hull cap at 1), so effects that could break the game use soft caps in `Perks.swift` — keep that when adding perks. Perks may raise `loadout` (which is why it is `var`); read their effects through the `…Now` / `bitReach` / `canDrill` accessors, not the raw tuning constants. The 1.1 perks resolve the same way: `bountyBonus` (kill gold), `smashPay` (gold per smashed rock), `bossGuardNow` (shorter boss hit guard), `repairInterval` + `repairProgress` (Auto-Repair, counted on new max depth), Daredevil in `checkNearMiss`, and `heatProof` (Heat Shield **or** Thermal Core) wherever lava immunity is checked; Thermal Core also blocks `chillDrill`.
- **Garage parts** (`Model/ShipParts.swift`): one `ShipPart` per `PartSlot` (bit, hull, tracks, module), held in `profile.build`, each Mk I–III (`profile.partLevels`). All numbers live in `ShipPart.stats(level:)` → `PartStats`; card copy is generated from it (`summary`), so never hand-write part descriptions. A run receives a `Gear` (build + levels) and reads every part effect through it (`gear.speedFactor`, `gear.killFuel`, `gear.lavaImmune`…). Upgrades cost gold, and boss parts also cost that boss's cores (`profile.bossCores`, +1 per kill). Each boss has one part (`ShipPart.drop(for:)`), which goes **on sale** in the Garage once `profile.coresCollected(boss)` reaches `ShipPart.coresToUnlock` (10); it is then bought for `legendaryPrice` (4000 + 1000 × boss index) via `AppModel.isForSale` / `buy` (`buyPrice` covers shop and boss parts). That count is lifetime kills of the boss, full and mini, read from `bestiaryKills`, so spending `bossCores` on upgrades never sets it back. Parts owned from before this rule are kept. The run shows "CORE n/10", "NEW PART UNLOCKED" or "+1 CORE" on each kill (`world.coresBefore`), the results card shows `result.coreProgress` with a `CoreBar`, and the Garage shows n/10 on locked boss parts. The daily always uses `ShipBuild.standard`. `DrillArt.draw(build:)` draws every part, so a new part needs art there too. **Rarity** (`ShipPart.rarity` → `PartRarity`) is derived, never set by hand: starters common, boss parts legendary, shop parts by price (<1600 uncommon, <2500 rare, else epic). The Garage sorts each slot by rarity and shows a `RarityTag` plus a rarity-tinted card edge.
- **`PlayerProfile` decodes every field with `decodeIfPresent`.** A synthesized decoder throws on unknown keys, and `ProfileStore.load` treats a throw as "no save", which wipes progress. Add new fields the same way.
- **Chill** (`world.chill`, set by `chillDrill`): while it runs, `chillFactor` (0.55) scales the drill's speed and turn rate, and the renderer frosts the drill. Sources: frost wisp novas, `.frost` shots, frost patches. Frost Runners are immune; a Heat Shield melts frost patches (but not shots or novas).
- **Poison** (`world.poison`, set by `poisonDrill`): fuel burns `poisonBurn` (2.5×) faster while it runs (`fuelBurnNow`), with green bubbles on the drill. Sources: poison clouds (`LavaPool` with `poison = true`, made by `spawnPoisonCloud`), the toad's tongue. Spore Filter is immune.
- **Gravity**: `wellPull` (singularities) and `bossPull` (sandstorm, black hole) are drifts added in `stepDrill`; Void Drill (`gear.gravityImmune`) ignores all of them.
- **The Void** (10th layer, 1230 m, the last one): stardust ore, star-shard crystals and `Decor.Kind.star` stars/nebulae (drawn from `rng` only in that layer). Everything below 1230 m stays the Void. Boss banners show the layer's own `guardian` line ("Guardian of the Abyss"), one whole localized string per layer.
- **Spore Hollow** (9th layer, 1080 m): radium ore, spore-shard crystals and `Decor.Kind.shroom` glowing mushrooms (drawn from `rng` only in that layer). 
- **Frozen Depths** (8th layer, 930 m): sapphire ore, icicle crystals and `Decor.Kind.drift` snow drifts (drawn from `rng` only in that layer). 
- **Ancient Ruins** (7th layer, 780 m): jade ore, gold glyph crystals and `Decor.Kind.ruin` blocks/pillars (drawn from `rng` only in that layer). 
- **The Abyss** (6th layer, 630 m): pearl ore; jellies (drift in, telegraph, then shock within `jellyShockRadius`) and anglers (still, with a lure drawn in the layer's ore colour so it reads as ore; lunge inside `anglerStrike`). Boss Abyss Angler at 780 m drops the Abyss Lantern (`seeInDark` + magnet), which disables both Lights Out and the blackout overlay.
- **The run's starting point** is drawn by `drawSurface` (sky, moon, hills, headframe, sign) whenever the camera is above ground; the tunnel is clipped at the surface.
- **Magma Core** (5th layer, 480 m): lava pools (`LavaPool`, non-solid, burn on contact, counted in `gapSurvives`), embers (drift in, swell, burst), and the Magma Titan (geyser lanes: warned in `windup`, burning in `attack`). Heat Shield makes the hull lava-proof.
- **Events** (`Game/Events.swift`): cave-in (falling `Shot`s with `.boulder` style), gold rush (pickups ×2 plus a burst of nuggets), lights out (renderer darkness overlay). One every 80–130 m from `eventRNG`, deferred out of arenas and fights.
- **Terrain determinism:** in `generateBand`, draw every `rng` value *before* any check that reads live state (`crowdsPickup` sees pickups that Magnet and Gold Rush move). A draw behind such a check lets play shift the terrain stream.
- **Settings** (`Model/GameSettings.swift`, `SettingsStore`, separate key from the profile): steering sensitivity (scales `turnRate` via `world.steerSensitivity`), joystick dead zone, joystick visibility, haptics, screen shake (`world.shakeScale`, read only by the renderer).
- **Report a bug** (Settings → Help, `Core/BugReport.swift`): Apple's mail sheet (`MailSheet`) pre-filled to asar.innovations@gmail.com with subject `[Abyss Drill] Bug report` (the tag is the support inbox's filter) and app version, device, iOS and best depth; falls back to a `mailto:` link, then copies the address. All MessageUI code stays in that file.
- **How to Play** (`Views/HowToPlayView.swift`, `Screen.howToPlay`, opened from the "?" on Home and from Settings → Help): collapsible topic cards. Perks themselves live in the **Field Guide's Perks tab** (`PerkTile` + `PerkPage`, built like the creature cards: a framed `PerkWindow`, name, grey caption, silhouette when undiscovered; locked until discovered: `profile.perksSeen`, filled from `world.perksSeen` in `offerPerks` → `RunResult` → `completeRun`, unioned by `ProfileMerge`); How to Play only explains the pick and points there. Biomes, ores and boss names are generated from `Strata.layers` / `bossKind`, and numbers come from the tuning constants. **When adding a rule, status effect or event, add a line there too.**
- **Field Guide** (`Model/Bestiary.swift`, `Views/FieldGuideView.swift`): one `BestiaryEntry` per critter and boss, keyed by `BestiaryEntry.key` (enemy kind name, or `boss.` + boss key). The run records sightings (enemy wakes / boss engages → `noteSighting`, with a "NEW ENTRY" popup if the profile doesn't have it) and kills; `AppModel.completeRun` merges them into `profile.bestiarySeen` / `bestiaryKills`. Portraits reuse the real art via `GameRenderer.drawPortrait` on tiny per-entry worlds (`PortraitWorlds`). **A new enemy or boss needs a `BestiaryEntry` too.**
- **The hold** is a list of `(value, slots)`. When full, `stow` evicts the lowest value-per-slot ore if the new piece is worth more ("SWAP"); otherwise it is smelted for `overflowFuel` and still counts for combo.
- **Workshop tracks are uncapped.** `costs` are the hand-tuned first levels (and the pips on the card); `price(atLevel:)` continues at ×1.55 per level after that.
- Effects (particles, coin flights) draw from `fx`, not `rng`, so player actions never shift terrain generation.
- Undrillable rock is drawn with a coral rim. That rim turning neutral is the main feedback that a Power upgrade did something — don't lose it.
- `gapSurvives` guarantees every generated band leaves a `minGap`-wide lane. Raising obstacle density without checking this makes runs unwinnable.
- **Two kinds of earnings.** *Ore* (the nuggets, `PickupKind.gold`; metal per layer from `StrataLayer.ore`: copper → silver → gold → platinum → mythril) and gems go into the hold, counted in **slots** (ore 1, gem 2), and are sold when the run ends. *Coins* (`world.coins`: bounties, chests, trail and boss rewards) are weightless and never limited by the hold. Payout = `coins + cargoValue`. Never add ore value to `coins`, or the full-hold rule stops making sense again.
- The rewarded refill is offered only from `offersRefill` (run already stalled, out of fuel, not the daily, one per run). Nothing interrupts an active run.
- Daily challenge: `Loadout.dailyStandard` for everyone, double-gold multiplier skipped, refill disabled, score stored per `yyyy-MM-dd`.

### Audio

`Core/Audio.swift` holds everything; there are no audio files. `Synth` renders chiptune voices (square/triangle/saw/sine/noise with envelopes) into mono 22 kHz buffers: every `SFX` once at start-up, each `MusicTrack` (menu, one per biome, boss) on demand off the main thread, then cached. Music loops wrap their tails round to the start, so they loop seamlessly. `Audio.shared` plays effects through a pool of players, keeps a looping drill hum whose pitch follows speed (`AVAudioUnitVarispeed`), and cross-fades two music players.
- **Nothing plays until `Audio.shared.start()`** (called from `ContentView`), so offscreen harnesses that drive `GameWorld` stay silent.
- One-shots are called from the sim next to the matching `Haptics` call (`Audio.shared.play(.ore)` …). Continuous audio (hum, biome/boss track, low-fuel beep) is driven once per frame by `Audio.shared.updateRun(world, paused:)` from `GameView`, which only reads the world.
- Session category `.ambient` with `.mixWithOthers`: respects the silent switch and the player's own music. Settings has separate Sound and Music toggles (`GameSettings.sound` / `.music`).
- To change a theme, edit its `Synth.spec(for:)` (root note, mode, tempo, progression, voices, drum level, seed).

### Drawing

`DrillArt.draw` is the single source for the machine — used by the run, the home yard and the shop skin cards, so upgrade attachments and skins stay consistent everywhere. It draws in local metres and applies its own transform; pass `GraphicsContext` by value and copy it (`var c = ctx`) to scope a transform or clip.

**Art style: hand-inked.** Everything interactive gets an outline in `Palette.ink` via `Ink.outline` (one stroke plus a faint offset second pass). No blur glows: only things that emit light (lava, embers, Overdrive, chambers, crystal core, shots) use `Ink.halo`, which stacks hard-edged rings. Telegraphs use `Ink.warning` (dashed ring). Highlights are `Ink.shine` chips, not sparkle stars. Soil is flat colour plus world-anchored hatching/stipple (`drawSoilTexture`), and `PaperGrain` is laid over the finished frame. Banner and popup text goes through `comicText`. Undrillable rock is drawn as an ink border with the coral line inside it.

`Blob.chunky` / `Blob.stone` keep facets; `Blob.path` / `Blob.rock` smooth everything into a soft blob. Stone, gems and nuggets use the chunky variants on purpose — the smooth ones turn boulders into circles and gems into ellipses.

Reduced motion is honoured by `world.reduceMotion`: it suppresses shake, cuts particle counts and caps, stops the bit spin and the bob, and shortens flourishes.

### Menu design system

`Core/DesignSystem.swift` holds the shared menu chrome; build new screens from it rather than restyling by hand: `MenuBackground` (night-to-strata ground behind every menu), `.card(radius, fill:, accent:)` (panel with lit edge, hairline rim and shadow; `accent` = selected/equipped rim), `ScreenHeader` (back button + title + trailing view), `SectionHeader`, `CircleIconButton`, and `DrillToggleStyle` (same switch on iOS and macOS). Screens cross-fade via `.id(app.screen)` in `ContentView`.

## Things that affect how you write code here

- **Localization.** English is the source; `Localizable.xcstrings` carries ro, es-MX, pt-BR, de, fr, ja, ko and zh-Hans (`InfoPlist.xcstrings` holds the ATT prompt). `Text("literal")`, `Label`, `Button` and `.accessibilityLabel` literals are localized automatically; any user-facing text that travels as a `String` (model titles, popups, shouts, toasts, component params) must be `String(localized: "…", bundle: .app)` at its source — `Text(someString)` is verbatim. Use one whole format string per sentence (never glue fragments or add English plural suffixes), `.localizedUppercase`/`.localizedCapitalized` on display text, and never compare display strings in logic (generation keys off `layerIndex` / `Strata.ruins` etc.). Identifiers, keys, the bug-report subject tag and the technical block of the bug email stay English. **In-app language** (Settings → Language, `GameSettings.language`, nil = device) is `Core/Localization.swift`: `AppLanguage.apply` swaps `Bundle.app` to that `.lproj` and rebuilds the tables built once from localized names (`Strata.layers`, `BestiaryEntry.all`, `DrillSkin.all` via `reloadNames`; a new static table of localized text needs the same), and `ContentView` sets `\.locale` and re-`id`s the screen so it redraws. Always pass `bundle: .app`, or that string ignores the in-app choice. After adding strings, build and run `xcstringstool sync` (or open the project in Xcode) and translate the new keys for all eight languages.

- `GameWorld` is split across `GameWorld.swift`, `Perks.swift`, `Bosses.swift` and `Events.swift` (extensions). Helpers those files share (`hurt`, `popup`, `shout`, `burstParticles`, `bumpCombo`, `claimID`, `invuln`, `stun`, `fx`) are internal rather than private for that reason.

- **Adding files needs no project edit.** `MyApp` is a `PBXFileSystemSynchronizedRootGroup`, so any `.swift` file dropped anywhere under `MyApp/` is compiled automatically, subdirectories included. Do not hand-edit `project.pbxproj` to register sources.
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** — types and functions are implicitly `@MainActor`. The game loop relies on this; annotate `nonisolated` deliberately.
- **Minimum iOS 18.0** (`IPHONEOS_DEPLOYMENT_TARGET`). The floor comes from `Color.mix(with:by:)`; anything newer needs an `if #available` guard. Supported platforms: `iphoneos iphonesimulator`, device family iPhone + iPad (Mac and Vision Pro were dropped for 1.0).
- **iPhone is locked to portrait** (`INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone`). **iPad must list all four orientations**: App Store validation rejects an iPad app that supports multitasking otherwise. `PortraitStage` letterboxes the game into a 9:19.5 column in any window shape, so landscape and Split View just show a centred portrait column.
- **App Sandbox is enabled** with `ENABLE_USER_SELECTED_FILES = readonly`. Progress is stored in `UserDefaults` via `ProfileStore`, and mirrored to **iCloud key-value storage** (`Model/CloudSave.swift`, entitlement in `Config/AbyssDriller.entitlements`). `ProfileStore.load` merges local and cloud copies; `ContentView` observes external changes and calls `AppModel.mergeCloudSave`. `ProfileMerge` unions unlocks, takes the max of records/levels/kill counts, ORs purchases, and takes spendable gold/cores and choices from the newer save (`savedAt`, stamped on every save). A device adopts a cloud save only if `sameProgress` says it adds something, or two devices would ping-pong forever. Settings are not synced.
- **Info.plist is generated** (`GENERATE_INFOPLIST_FILE = YES`); set keys through `INFOPLIST_KEY_*` build settings.
- **In-app purchases: StoreKit 2** (`Model/Store.swift`, `StoreManager` owned by `AppModel.store`). Product IDs are `StoreProduct` (`com.andreizaharia.abyssdriller.` + `gold.small|gold.medium|gold.large` consumables, `doublegold`, `removeads`, `megabundle` and `skin.copper|skin.glacier|skin.magma` non-consumables). **Remove Ads** (`profile.adsRemoved`) grants both ad rewards instantly with no video, and `ContentView` does not start `AdsManager` for those players. **Mega Bundle** = Double Gold + Remove Ads + the Magma Core paint + one huge gold pack; the gold is guarded by `profile.bundleGoldGranted` because the bundle replays from entitlements every launch, and the Shop hides the card once `app.ownsBundle`. Items are granted only from verified transactions in `AppModel.deliver`, and the transaction is finished after delivery, so interrupted / Ask-to-Buy purchases arrive via `Transaction.updates`. Non-consumables are re-delivered from `currentEntitlements` at every launch, so `deliver` must stay idempotent for them. Gold packs grant the progress-scaled amount at delivery time. The shop shows `product.displayPrice` (catalog strings are only fallbacks) and has a Restore Purchases link.
  - Local testing: `MyApp/AbyssDriller.storekit` (select it in Scheme → Run → Options → StoreKit Configuration). It and `CLAUDE.md` are excluded from the app bundle by the `PBXFileSystemSynchronizedBuildFileExceptionSet` in `project.pbxproj`; any other non-shipping file added under `MyApp/` needs adding there too.
- App Store screenshots are generated, not hand-made: `AppStoreScreenshots/iPhone-6.9` (1320×2868) and `iPad-13` (2064×2752).
- **Ads (AdMob)** live in `Core/Ads.swift` (`AdsManager`, owned by `AppModel.ads`). One placement: the rewarded out-of-fuel refill (`AppModel.watchAdForRefill`). Start-up runs UMP consent → ATT prompt → `MobileAds.start` and keeps one ad preloaded. The reward is granted when the ad closes; if no ad loads within `AdConfig.loadGrace` the refill is granted anyway. All SDK code is behind `#if os(iOS) && canImport(GoogleMobileAds)`; macOS/visionOS just grant the refill.
  - The package is linked with an **iOS platform filter** in `project.pbxproj` (the SDK has no macOS/visionOS slices). That file *is* edited for packages; it is only source files that must never be registered there.
  - `GADApplicationIdentifier` and `SKAdNetworkItems` are in `Config/Info.plist`, merged into the generated plist via `INFOPLIST_FILE`. It sits outside `MyApp/` on purpose: inside the synced folder it would be copied as a resource and clash with the generated plist. The ATT text is `INFOPLIST_KEY_NSUserTrackingUsageDescription`.
  - The app ID in `Config/Info.plist` is the real AdMob app (created in the console under its old name, "Drill Down"). `AdConfig.rewardedUnitID` is Google's **test unit in Debug** and the real "Rewarded" unit in Release. Keep it that way: tapping real ads on a dev device can get the AdMob account suspended.
  - **Interstitial** (`AdConfig.interstitialUnitID`, test unit in Debug): the only non-rewarded ad, shown by `AppModel.leaveResults` when the player leaves the results screen (Drill Again or Upgrade), never during a run. Pacing: no Remove Ads, `profile.runsCompleted >= interstitialFreeRuns` (5), `interstitialEveryRuns` (3) runs since the last one this launch, and `interstitialGap` (4 min) since any full-screen ad closed (`ads.lastAdClosed`, rewarded included). Never waits for a load: no ad ready means carry on. The privacy policy and listing describe it; keep them in sync if the rules change.
  - Second placement: **free Workshop upgrade** (`AppModel.tapUpgrade` / `watchAdForUpgrade`, offer card in HomeView). Offered when an upgrade is unaffordable, or right after a purchase that leaves the next level out of reach. Rationed by `AppModel.adUpgradesPerDay` (10, per calendar day), and granted **only if the ad was watched**, unlike the refill. Hidden where `ads.isSupported` is false.
  - Gold packs (`ShopCatalog.goldPacks(levels:)`) scale with Workshop progress: the base pack is ~3 next upgrades (×3 of the rounded average next price), then ×5 and ×10 of that; always a multiple of 500 (fresh profile: 3,000 / 15,000 / 30,000).
  - Settings shows "Privacy choices" (re-opens the consent form) when `ads.privacyOptionsRequired`.
- Bundle identifier: `com.andreizaharia.abyssdriller`. Launch screen is the `LaunchBackground` colour set (via `UILaunchScreen` in `Config/Info.plist`). `MyApp/PrivacyInfo.xcprivacy` declares the UserDefaults access (reason CA92.1); keep it updated if new required-reason APIs are used. Settings' Reset Game section is `#if DEBUG` only.
- **Name and icon.** The home-screen name is `INFOPLIST_KEY_CFBundleDisplayName` ("Abyss Driller"); the target and product are still called MyApp. The icon is `Assets.xcassets/AppIcon.appiconset` (iOS single 1024 px + macOS sizes), rendered from the game's own `DrillArt`/`Ink` art; regenerate it rather than hand-editing. App Store copy (name, subtitle, keywords, description) lives in `APP_STORE_LISTING.md` at the project root.
