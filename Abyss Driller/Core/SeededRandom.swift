import Foundation

/// SplitMix64. Deterministic so a seed reproduces a whole run — needed for the
/// daily challenge, handy for debugging a specific layout.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func double(_ range: ClosedRange<Double>) -> Double {
        Double.random(in: range, using: &self)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &self)
    }

    mutating func chance(_ probability: Double) -> Bool {
        double(0...1) < probability
    }

    mutating func pick<T>(_ items: [T]) -> T {
        items[int(0...(items.count - 1))]
    }
}

/// Stable hash for seeding from a string (Swift's `hashValue` is salted per launch).
func stableSeed(_ string: String) -> UInt64 {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100_0000_01B3
    }
    return hash
}
