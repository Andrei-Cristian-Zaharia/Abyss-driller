import AVFoundation
import SwiftUI

/// One-shot sound effects. Every buffer is synthesised at start-up by `Synth`
/// (there are no audio files in the bundle).
enum SFX: CaseIterable {
    case ore, gem, smash, hit, kill, combo1, combo2, combo3, combo4, overdrive, nearMiss, block
    case bossIntro, bossHit, bossDown, perk, tap, buy, chill, poison, warning, record, gameOver, treasure, unlock
}

/// Music: a menu theme, one theme per biome (index into `Strata.layers`), and
/// a boss theme. Rendered on demand off the main thread, then cached.
enum MusicTrack: Hashable {
    case menu
    case biome(Int)
    case boss
}

/// The game's audio: a small pool of players for effects, a looping drill hum
/// whose pitch follows speed, and two music players that cross-fade.
///
/// Nothing plays until `start()` is called (from `ContentView`), so offscreen
/// tools and previews that drive the game never make a sound.
@MainActor
final class Audio {
    static let shared = Audio()

    var soundOn = true
    var musicOn = true { didSet { applyMusicVolume() } }

    private(set) var started = false
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: Synth.rate, channels: 1)!
    private var pool: [AVAudioPlayerNode] = []
    private var next = 0
    private var buffers: [SFX: AVAudioPCMBuffer] = [:]
    private let hum = AVAudioPlayerNode()
    private let humSpeed = AVAudioUnitVarispeed()
    private let musicA = AVAudioPlayerNode()
    private let musicB = AVAudioPlayerNode()
    private var musicFront = true
    private var current: MusicTrack?
    private var wanted: MusicTrack?
    private var tracks: [MusicTrack: AVAudioPCMBuffer] = [:]
    private var rendering: Set<MusicTrack> = []
    private var fadeTask: Task<Void, Never>?
    private var humBuffer: AVAudioPCMBuffer?
    private var beepTimer = 0.0
    private var lastFrame: Date?

    static let musicLevel: Float = 0.32
    static let humLevel: Float = 0.16

    private init() {}

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        #if os(iOS)
        // Ambient: respects the silent switch and mixes with the player's own music.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in Audio.shared.resume() }
        }
        #endif
        for sfx in SFX.allCases { buffers[sfx] = makeBuffer(Synth.effect(sfx)) }
        for _ in 0..<10 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            pool.append(player)
        }
        engine.attach(hum)
        engine.attach(humSpeed)
        engine.connect(hum, to: humSpeed, format: format)
        engine.connect(humSpeed, to: engine.mainMixerNode, format: format)
        for player in [musicA, musicB] {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            player.volume = 0
        }
        engine.mainMixerNode.outputVolume = 0.9
        humBuffer = makeBuffer(Synth.humLoop())
        hum.volume = 0
        resume()
        if let wanted { play(wanted) }
    }

    /// Restarts the engine after an interruption (a call, Siri) or a return
    /// from the background.
    func resume() {
        guard started else { return }
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        // Stopping the engine stops every player; queue the loops up again.
        if let humBuffer, !hum.isPlaying {
            hum.stop()
            hum.scheduleBuffer(humBuffer, at: nil, options: .loops)
            hum.play()
        }
        let front = musicFront ? musicA : musicB
        if let current, let buffer = tracks[current], !front.isPlaying {
            front.stop()
            front.scheduleBuffer(buffer, at: nil, options: .loops)
            front.volume = musicOn ? Self.musicLevel : 0
            front.play()
        }
    }

    // MARK: Effects

    func play(_ sfx: SFX, volume: Float = 1) {
        guard started, soundOn, engine.isRunning, let buffer = buffers[sfx] else { return }
        let player = pool[next]
        next = (next + 1) % pool.count
        player.stop()
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil)
        player.play()
    }

    /// Rising blips as the combo multiplier climbs (x1 → x4).
    func comboStep(_ multiplier: Int) {
        switch multiplier {
        case ...1: play(.combo1)
        case 2: play(.combo2)
        case 3: play(.combo3)
        default: play(.combo4)
        }
    }

    // MARK: Music

    func play(_ track: MusicTrack) {
        wanted = track
        guard started, track != current else { return }
        if let buffer = tracks[track] {
            crossfade(to: buffer, track: track)
        } else if !rendering.contains(track) {
            rendering.insert(track)
            let spec = Synth.spec(for: track)
            Task.detached(priority: .utility) {
                let samples = Synth.render(spec)
                await MainActor.run {
                    let audio = Audio.shared
                    audio.rendering.remove(track)
                    guard let buffer = audio.makeBuffer(samples) else { return }
                    audio.tracks[track] = buffer
                    if audio.wanted == track { audio.crossfade(to: buffer, track: track) }
                }
            }
        }
    }

    private func crossfade(to buffer: AVAudioPCMBuffer, track: MusicTrack) {
        current = track
        let incoming = musicFront ? musicB : musicA
        let outgoing = musicFront ? musicA : musicB
        musicFront.toggle()
        incoming.stop()
        incoming.volume = 0
        incoming.scheduleBuffer(buffer, at: nil, options: .loops)
        if engine.isRunning { incoming.play() }
        fadeTask?.cancel()
        fadeTask = Task { @MainActor in
            let target = musicOn ? Self.musicLevel : 0
            let start = outgoing.volume
            for step in 1...20 {
                try? await Task.sleep(for: .milliseconds(30))
                if Task.isCancelled { return }
                let t = Float(step) / 20
                incoming.volume = target * t
                outgoing.volume = start * (1 - t)
            }
            outgoing.stop()
        }
    }

    private func applyMusicVolume() {
        guard started else { return }
        fadeTask?.cancel()
        (musicFront ? musicA : musicB).volume = musicOn ? Self.musicLevel : 0
        (musicFront ? musicB : musicA).volume = 0
    }

    // MARK: Run

    /// Called every frame of a run: drill hum, the biome or boss theme, and the
    /// low-fuel beep. Reads the world only.
    func updateRun(_ world: GameWorld, paused: Bool) {
        guard started else { return }
        let now = Date()
        let dt = min(0.1, lastFrame.map { now.timeIntervalSince($0) } ?? 0)
        lastFrame = now
        let drilling = world.phase == .drilling && world.isEngaged && !paused
        let speed = hypot(world.vx, world.vy)
        hum.volume = soundOn && drilling ? Self.humLevel * (world.inOverdrive ? 1.4 : 1) : 0
        let pitch: Double = 0.75 + min(1, speed / 9) * 0.65
        humSpeed.rate = Float(pitch * (world.inOverdrive ? 1.25 : 1))

        switch world.phase {
        case .drilling, .choosing, .stalled, .ready:
            if let boss = world.boss, boss.engaged, !boss.defeated {
                play(.boss)
            } else {
                play(.biome(Strata.index(for: max(0, world.depth))))
            }
        default:
            play(.menu)
        }

        // Low fuel: a quiet double beep, faster as the tank empties.
        let fraction = world.fuel / max(1, world.loadout.fuelCapacity)
        if drilling, fraction < 0.2, !world.inOverdrive {
            beepTimer -= dt
            if beepTimer <= 0 {
                play(.warning, volume: 0.7)
                beepTimer = 0.6 + fraction * 6
            }
        } else {
            beepTimer = 0
        }
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }
}

// MARK: - Synthesis

/// Chiptune-style synthesis: square / triangle / saw / noise voices with simple
/// envelopes, rendered into mono float buffers. Pure functions, safe off the
/// main thread.
nonisolated enum Synth {
    static let rate = 22_050.0

    enum Wave { case square(Double), triangle, saw, sine, noise }

    struct Note {
        var at: Double          // seconds
        var length: Double
        var freq: Double
        var to: Double? = nil   // pitch sweep target
        var wave: Wave
        var volume: Double
        var attack = 0.004
        var release = 0.06
    }

    /// Tiny deterministic generator (the game's `SeededRandom` lives on the main actor).
    struct LCG {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        mutating func int(_ n: Int) -> Int { min(n - 1, Int(next() * Double(n))) }
    }

    static func midi(_ note: Double) -> Double { 440 * pow(2, (note - 69) / 12) }

    /// Renders notes into a buffer. With `loop`, tails that run past the end
    /// wrap round to the start, so the buffer loops without a click.
    static func mix(_ notes: [Note], length: Double, loop: Bool = false, seed: UInt64 = 1) -> [Float] {
        let count = Int(length * rate)
        guard count > 0 else { return [] }
        var out = [Float](repeating: 0, count: count)
        var noise = LCG(state: seed | 1)
        for note in notes {
            let start = Int(note.at * rate)
            let total = Int((note.length + note.release) * rate)
            var phase = 0.0
            var held = 0.0
            for i in 0..<total {
                let t = Double(i) / rate
                let progress = min(1, t / max(0.001, note.length))
                let freq = note.to.map { note.freq + ($0 - note.freq) * progress } ?? note.freq
                phase += freq / rate
                phase -= floor(phase)
                var env = min(1, t / note.attack)
                if t > note.length { env *= max(0, 1 - (t - note.length) / note.release) }
                let s: Double
                switch note.wave {
                case .square(let duty): s = phase < duty ? 0.6 : -0.6
                case .triangle: s = (phase < 0.5 ? phase * 4 - 1 : 3 - phase * 4) * 0.8
                case .saw: s = (phase * 2 - 1) * 0.5
                case .sine: s = sin(phase * 2 * .pi)
                case .noise:
                    // Sample-and-hold noise: the hold rate sets its "pitch".
                    if phase < freq / rate || i == 0 { held = noise.next() * 2 - 1 }
                    s = held * 0.7
                }
                var index = start + i
                if index >= count {
                    guard loop else { break }
                    index %= count
                }
                out[index] += Float(s * env * note.volume)
            }
        }
        // Soft clip so stacked voices never crackle.
        for i in out.indices { out[i] = tanh(out[i] * 1.1) }
        return out
    }

    // MARK: Effects

    static func effect(_ sfx: SFX) -> [Float] {
        func n(_ at: Double, _ len: Double, _ f: Double, _ w: Wave, _ v: Double, to: Double? = nil, rel: Double = 0.05) -> Note {
            Note(at: at, length: len, freq: f, to: to, wave: w, volume: v, release: rel)
        }
        let notes: [Note]
        switch sfx {
        case .ore:
            notes = [n(0, 0.04, 1319, .square(0.5), 0.22), n(0.04, 0.08, 1760, .square(0.5), 0.2, rel: 0.08)]
        case .gem:
            notes = [1047.0, 1319, 1568, 2093].enumerated().map { n(Double($0.offset) * 0.045, 0.05, $0.element, .triangle, 0.32, rel: 0.12) }
        case .smash:
            notes = [n(0, 0.1, 2400, .noise, 0.45, to: 600, rel: 0.08), n(0, 0.12, 140, .sine, 0.6, to: 55)]
        case .hit:
            notes = [n(0, 0.18, 190, .sine, 0.9, to: 45, rel: 0.1), n(0, 0.08, 1800, .noise, 0.4, to: 300), n(0.02, 0.1, 110, .square(0.3), 0.25, to: 70)]
        case .kill:
            notes = [n(0, 0.07, 700, .square(0.5), 0.22, to: 1500), n(0.05, 0.06, 3000, .noise, 0.18, to: 900)]
        case .combo1, .combo2, .combo3, .combo4:
            let step: Double = sfx == .combo1 ? 0 : sfx == .combo2 ? 2 : sfx == .combo3 ? 4 : 7
            let base = midi(76 + step)
            notes = [n(0, 0.05, base, .square(0.25), 0.2), n(0.05, 0.08, base * 1.5, .square(0.25), 0.18, rel: 0.08)]
        case .overdrive:
            notes = [n(0, 0.5, 180, .saw, 0.5, to: 900, rel: 0.2), n(0, 0.5, 600, .noise, 0.25, to: 4000, rel: 0.2),
                     n(0.45, 0.25, midi(84), .square(0.5), 0.2, rel: 0.2)]
        case .nearMiss:
            notes = [n(0, 0.16, 900, .noise, 0.3, to: 5000, rel: 0.06)]
        case .block:
            notes = [n(0, 0.03, 2093, .triangle, 0.4, rel: 0.06), n(0.03, 0.05, 2794, .triangle, 0.3, rel: 0.1)]
        case .bossIntro:
            notes = [n(0, 1.1, 55, .square(0.5), 0.35, rel: 0.4), n(0, 0.25, 1600, .noise, 0.4, to: 200, rel: 0.2),
                     n(0.3, 0.2, midi(62), .square(0.5), 0.25), n(0.5, 0.2, midi(65), .square(0.5), 0.25),
                     n(0.7, 0.55, midi(61), .square(0.5), 0.28, rel: 0.3)]
        case .bossHit:
            notes = [n(0, 0.15, 160, .sine, 0.8, to: 60, rel: 0.1), n(0, 0.06, 2200, .noise, 0.35, to: 500), n(0, 0.1, 330, .square(0.5), 0.2, to: 200)]
        case .bossDown:
            let melody: [Double] = [72, 76, 79, 84]
            notes = melody.enumerated().map { n(Double($0.offset) * 0.12, 0.11, midi($0.element), .square(0.5), 0.25) }
                + [n(0.48, 0.6, midi(84), .square(0.5), 0.22, rel: 0.4), n(0.48, 0.6, midi(76), .triangle, 0.3, rel: 0.4),
                   n(0.48, 0.6, midi(60), .triangle, 0.35, rel: 0.4)]
        case .perk:
            notes = [72.0, 76, 79, 83, 88].enumerated().map { n(Double($0.offset) * 0.05, 0.06, midi($0.element), .triangle, 0.3, rel: 0.15) }
        case .tap:
            notes = [n(0, 0.02, 900, .triangle, 0.18, rel: 0.02)]
        case .buy:
            notes = [n(0, 0.05, 1568, .square(0.5), 0.2), n(0.06, 0.18, 2093, .square(0.5), 0.2, rel: 0.15), n(0.06, 0.18, 2637, .triangle, 0.2, rel: 0.15)]
        case .chill:
            notes = (0..<6).map { n(Double($0) * 0.04, 0.05, 2600 - Double($0) * 180, .triangle, 0.22, rel: 0.1) }
        case .poison:
            notes = (0..<3).map { n(Double($0) * 0.08, 0.07, 340 - Double($0) * 40, .sine, 0.45, to: 200 - Double($0) * 30, rel: 0.05) }
        case .warning:
            notes = [n(0, 0.06, 988, .square(0.5), 0.16), n(0.11, 0.06, 988, .square(0.5), 0.16)]
        case .record:
            notes = [72.0, 76, 79, 84, 88, 91].enumerated().map { n(Double($0.offset) * 0.07, 0.08, midi($0.element), .square(0.25), 0.22, rel: 0.2) }
        case .gameOver:
            notes = [n(0, 0.18, midi(67), .square(0.5), 0.22), n(0.2, 0.18, midi(63), .square(0.5), 0.22),
                     n(0.4, 0.45, midi(60), .square(0.5), 0.22, rel: 0.3), n(0.4, 0.45, midi(48), .triangle, 0.3, rel: 0.3)]
        case .treasure:
            notes = [79.0, 84, 88, 91, 96].enumerated().map { n(Double($0.offset) * 0.06, 0.07, midi($0.element), .square(0.5), 0.2, rel: 0.2) }
                + [n(0.3, 0.4, midi(84), .triangle, 0.3, rel: 0.3)]
        case .unlock:
            notes = [n(0, 0.1, midi(72), .square(0.5), 0.22), n(0.1, 0.1, midi(79), .square(0.5), 0.22),
                     n(0.2, 0.5, midi(84), .square(0.5), 0.22, rel: 0.4), n(0.2, 0.5, midi(88), .triangle, 0.28, rel: 0.4)]
        }
        let end = notes.map { $0.at + $0.length + $0.release }.max() ?? 0.1
        return mix(notes, length: end + 0.02)
    }

    /// One second of low engine rumble that loops seamlessly (70 whole cycles).
    static func humLoop() -> [Float] {
        mix([Note(at: 0, length: 1, freq: 70, wave: .saw, volume: 0.6, attack: 0.001, release: 0.001),
             Note(at: 0, length: 1, freq: 35, wave: .square(0.5), volume: 0.25, attack: 0.001, release: 0.001),
             Note(at: 0, length: 1, freq: 900, wave: .noise, volume: 0.12, attack: 0.001, release: 0.001)],
            length: 1, loop: true, seed: 9)
    }

    // MARK: Music

    struct Spec {
        var root: Double          // MIDI note of the key's tonic
        var scale: [Double]       // semitone steps of the mode
        var bpm: Double
        var progression: [Int]    // scale degrees, one chord per bar
        var lead: Wave
        var arp: Wave
        var drums: Double         // 0 = none … 1 = full kit
        var seed: UInt64
        var swing = 0.0
        var leadVolume = 0.16
    }

    static let major: [Double] = [0, 2, 4, 5, 7, 9, 11]
    static let minor: [Double] = [0, 2, 3, 5, 7, 8, 10]
    static let dorian: [Double] = [0, 2, 3, 5, 7, 9, 10]
    static let phrygian: [Double] = [0, 1, 3, 5, 7, 8, 10]
    static let lydian: [Double] = [0, 2, 4, 6, 7, 9, 11]
    static let harmonic: [Double] = [0, 2, 3, 5, 7, 8, 11]

    static func spec(for track: MusicTrack) -> Spec {
        switch track {
        case .menu:
            return Spec(root: 60, scale: major, bpm: 92, progression: [0, 5, 3, 4, 0, 5, 3, 4], lead: .triangle, arp: .square(0.25), drums: 0.35, seed: 11)
        case .boss:
            return Spec(root: 62, scale: harmonic, bpm: 146, progression: [0, 0, 5, 4, 0, 0, 5, 6], lead: .square(0.5), arp: .square(0.125), drums: 1, seed: 99, leadVolume: 0.18)
        case .biome(let index):
            switch index {
            case 0: return Spec(root: 67, scale: major, bpm: 112, progression: [0, 3, 4, 0, 0, 3, 4, 4], lead: .square(0.5), arp: .square(0.25), drums: 0.8, seed: 21)
            case 1: return Spec(root: 69, scale: dorian, bpm: 114, progression: [0, 3, 0, 4, 0, 3, 6, 4], lead: .square(0.25), arp: .triangle, drums: 0.8, seed: 22)
            case 2: return Spec(root: 62, scale: minor, bpm: 118, progression: [0, 5, 6, 4, 0, 5, 3, 4], lead: .square(0.5), arp: .square(0.25), drums: 0.85, seed: 23)
            case 3: return Spec(root: 64, scale: lydian, bpm: 116, progression: [0, 1, 0, 4, 0, 1, 5, 4], lead: .triangle, arp: .square(0.125), drums: 0.7, seed: 24, leadVolume: 0.2)
            case 4: return Spec(root: 61, scale: phrygian, bpm: 126, progression: [0, 1, 0, 6, 0, 1, 5, 6], lead: .saw, arp: .square(0.5), drums: 1, seed: 25)
            case 5: return Spec(root: 65, scale: minor, bpm: 100, progression: [0, 5, 3, 6, 0, 5, 3, 4], lead: .triangle, arp: .sine, drums: 0.4, seed: 26, leadVolume: 0.2)
            case 6: return Spec(root: 69, scale: harmonic, bpm: 118, progression: [0, 3, 4, 0, 5, 3, 4, 4], lead: .square(0.5), arp: .triangle, drums: 0.8, seed: 27)
            case 7: return Spec(root: 71, scale: minor, bpm: 108, progression: [0, 5, 2, 6, 0, 5, 3, 4], lead: .triangle, arp: .triangle, drums: 0.55, seed: 28, leadVolume: 0.22)
            case 8: return Spec(root: 67, scale: dorian, bpm: 120, progression: [0, 3, 0, 6, 0, 3, 4, 3], lead: .square(0.25), arp: .square(0.5), drums: 0.85, seed: 29, swing: 0.08)
            default: return Spec(root: 61, scale: minor, bpm: 104, progression: [0, 5, 2, 6, 0, 5, 2, 4], lead: .sine, arp: .triangle, drums: 0.45, seed: 30, leadVolume: 0.22)
            }
        }
    }

    /// Eight bars: bass in eighths, an arpeggio in sixteenths, a two-bar lead
    /// motif played A A′ B A, and a simple kit. Loops seamlessly.
    static func render(_ spec: Spec) -> [Float] {
        let beat = 60 / spec.bpm
        let bar = beat * 4
        let length = bar * Double(spec.progression.count)
        var rng = LCG(state: spec.seed)
        var notes: [Note] = []

        func note(_ degree: Int, octave: Double) -> Double {
            let s = spec.scale
            let wrapped = ((degree % s.count) + s.count) % s.count
            let lift = Double((degree - wrapped) / s.count) * 12
            return spec.root + s[wrapped] + lift + octave * 12
        }
        func time(_ sixteenth: Int, in barIndex: Int) -> Double {
            let swing = sixteenth % 2 == 1 ? spec.swing * beat : 0
            return Double(barIndex) * bar + Double(sixteenth) * beat / 4 + swing
        }

        // Lead motifs: a stepwise walk over the scale with rests.
        func motif() -> [(step: Int, degree: Int, length: Int)] {
            var out: [(Int, Int, Int)] = []
            var degree = rng.int(5)
            var step = 0
            while step < 32 {
                let length = [2, 2, 4, 4, 6, 8][rng.int(6)]
                if rng.next() > 0.18 { out.append((step, degree, min(length, 32 - step))) }
                degree += [-2, -1, -1, 1, 1, 2, 3][rng.int(7)]
                degree = max(-2, min(9, degree))
                step += length
            }
            return out
        }
        let a = motif(), b = motif()
        let plan: [[(step: Int, degree: Int, length: Int)]] = [a, a.map { ($0.step, $0.degree + ($0.step >= 24 ? 2 : 0), $0.length) }, b, a]

        for (barIndex, chord) in spec.progression.enumerated() {
            let root = note(chord, octave: -2)
            // Bass: root and fifth in eighths.
            for k in 0..<8 {
                let pitch = k % 4 == 2 ? note(chord + 4, octave: -2) : root
                notes.append(Note(at: time(k * 2, in: barIndex), length: beat * 0.42, freq: midi(pitch),
                                  wave: .square(0.5), volume: 0.2, release: 0.03))
            }
            // Arpeggio: chord tones in sixteenths.
            let tones = [chord, chord + 2, chord + 4, chord + 7]
            for k in 0..<16 {
                notes.append(Note(at: time(k, in: barIndex), length: beat * 0.18,
                                  freq: midi(note(tones[k % 4], octave: 0)), wave: spec.arp, volume: 0.07, release: 0.03))
            }
            // Drums.
            if spec.drums > 0 {
                for k in 0..<4 {
                    let at = time(k * 4, in: barIndex)
                    if k % 2 == 0 {
                        notes.append(Note(at: at, length: 0.11, freq: 150, to: 45, wave: .sine, volume: 0.55 * spec.drums, release: 0.04))
                    } else if spec.drums > 0.5 {
                        notes.append(Note(at: at, length: 0.09, freq: 3000, to: 1200, wave: .noise, volume: 0.28 * spec.drums, release: 0.05))
                    }
                }
                for k in 0..<8 where spec.drums > 0.3 {
                    notes.append(Note(at: time(k * 2 + 1, in: barIndex), length: 0.02, freq: 9000, wave: .noise,
                                      volume: 0.07 * spec.drums, release: 0.02))
                }
            }
        }
        // Lead, two bars per motif.
        for (section, phrase) in plan.enumerated() {
            for item in phrase {
                let barIndex = section * 2 + item.step / 16
                guard barIndex < spec.progression.count else { continue }
                notes.append(Note(at: time(item.step % 16, in: barIndex), length: Double(item.length) * beat / 4 * 0.9,
                                  freq: midi(note(item.degree, octave: 1)), wave: spec.lead, volume: spec.leadVolume,
                                  attack: 0.01, release: 0.08))
            }
        }
        return mix(notes, length: length, loop: true, seed: spec.seed)
    }
}
