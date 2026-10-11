import SwiftUI

/// Short set pieces that break up a run. One fires every 80–130 m, never
/// inside a boss arena or fight. Timing and kind come from `eventRNG`, so a
/// daily run throws the same events at everyone.
enum RunEventKind: CaseIterable {
    case caveIn     // boulders rain down from behind; smash them with the bit
    case goldRush   // a burst of ore ahead, and ore pays double
    case darkness   // only the headlight's pool is visible; gems glint ahead

    var title: String {
        switch self {
        case .caveIn: return "CAVE-IN!"
        case .goldRush: return "MOTHER LODE!"
        case .darkness: return "LIGHTS OUT"
        }
    }

    var icon: String {
        switch self {
        case .caveIn: return "exclamationmark.triangle.fill"
        case .goldRush: return "sparkles"
        case .darkness: return "moon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .caveIn: return Palette.hazard
        case .goldRush: return Palette.gold
        case .darkness: return Palette.gem
        }
    }

    var duration: Double {
        switch self {
        case .caveIn: return 6
        case .goldRush: return 6
        case .darkness: return 9
        }
    }
}

struct RunEvent {
    let kind: RunEventKind
    var timeLeft: Double
    var spawnTimer = 0.0

    /// 0→1 over the first and last half second, for fades.
    var intensity: Double { min(1, timeLeft / 0.5, (kind.duration - timeLeft) / 0.5) }
}

extension GameWorld {
    static let firstEventDepth = 70.0

    var goldRushActive: Bool { event?.kind == .goldRush }

    func updateEvents(_ dt: Double) {
        if var active = event {
            active.timeLeft -= dt
            active.spawnTimer -= dt
            switch active.kind {
            case .caveIn:
                if !reduceMotion { shake = max(shake, 0.12) }
                if active.spawnTimer <= 0 {
                    active.spawnTimer = 0.32
                    let column = eventRNG.double(1.0...(Self.shaftWidth - 1.0))
                    shots.append(Shot(id: claimID(), x: column, y: camera - 1,
                                      vx: 0, vy: max(13, vy + 6), life: 4, style: .boulder))
                }
            case .goldRush, .darkness:
                break
            }
            event = active.timeLeft > 0 ? active : nil
            if event == nil {
                popup("SURVIVED", at: CGPoint(x: x, y: depth - 1), tint: active.kind.tint)
            }
            return
        }

        guard maxDepth >= nextEventDepth else { return }
        let fighting = boss.map { $0.engaged && !$0.defeated } ?? false
        if fighting || Self.inArena(depth, pad: 12) {
            nextEventDepth = maxDepth + 15
            return
        }
        startEvent(RunEventKind.allCases[eventRNG.int(0...(RunEventKind.allCases.count - 1))])
        nextEventDepth = maxDepth + eventRNG.double(80...130)
    }

    private func startEvent(_ kind: RunEventKind) {
        event = RunEvent(kind: kind, timeLeft: kind.duration)
        shout(kind.title, tint: kind.tint)
        Haptics.thud()
        switch kind {
        case .caveIn:
            if !reduceMotion { shake = max(shake, 0.7) }
        case .goldRush:
            // A spray of nuggets in the direction of travel.
            let ahead = CGPoint(x: x + headingVector.x * 4.5, y: depth + max(2.5, headingVector.y * 4.5))
            let value = currentLayer.goldValue
            for _ in 0..<10 {
                let spot = CGPoint(x: min(max(ahead.x + eventRNG.double(-2.6...2.6), 1.2), Self.shaftWidth - 1.2),
                                   y: ahead.y + eventRNG.double(-1.5...3.5))
                pickups.append(Pickup(id: claimID(), kind: .gold, x: spot.x, y: spot.y,
                                      value: value, phase: eventRNG.double(0...6.28)))
            }
            treasureFlash = max(treasureFlash, 0.6)
        case .darkness:
            // Gems glint in the dark as the reward for pushing on.
            for k in 0..<3 {
                let spot = CGPoint(x: eventRNG.double(1.4...(Self.shaftWidth - 1.4)),
                                   y: depth + 5 + Double(k) * 4)
                pickups.append(Pickup(id: claimID(), kind: .gem, x: spot.x, y: spot.y,
                                      value: currentLayer.gemValue, phase: eventRNG.double(0...6.28)))
            }
        }
    }
}
