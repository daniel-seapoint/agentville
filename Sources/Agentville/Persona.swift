import CoreGraphics
import Foundation

/// The cosmetic quirks of one agent: what it wears, how it rests and what it dreams about.
/// Everything is drawn from a hash of the agent's id, so each agent looks random but keeps
/// the same look for as long as it exists, including across app restarts.
struct Persona {
    let hat: PixelArt.Hat?
    let accessory: PixelArt.Accessory?
    /// Otherwise it dozes on a couch if one is free, or on its feet.
    let sleepsInBed: Bool
    let dream: String
    /// Emoji scattered around a resting agent.
    let props: [String]
    /// Offset in -1...1 on each axis, used to scatter resting agents.
    let jitter: CGPoint

    /// Hats the demo cast always wears, so the demo shows them off whatever the hash picks.
    private static let demoHats: [String: PixelArt.Hat] = ["demo:1": .topHat]

    private static let dreams = [
        "green CI", "tickets", "merged PRs", "zero bugs", "passing tests", "clean diffs",
        "fast builds", "tidy commits", "inbox zero", "small PRs", "no flaky tests",
    ]
    private static let propPool = ["🧸", "📚", "🍕", "☕️", "🎮", "🪴", "📱", "🕹️", "🍩", "🎧"]

    init(agentID: String) {
        var random = StableRandom(seed: agentID)
        var hat = random.chance(0.85) ? PixelArt.Hat.allCases[random.next(PixelArt.Hat.allCases.count)] : nil
        let accessory = random.chance(0.6)
            ? PixelArt.Accessory.allCases[random.next(PixelArt.Accessory.allCases.count)] : nil
        // Nobody goes out completely undressed.
        if hat == nil && accessory == nil {
            hat = PixelArt.Hat.allCases[random.next(PixelArt.Hat.allCases.count)]
        }
        self.hat = Self.demoHats[agentID] ?? hat
        self.accessory = accessory
        sleepsInBed = random.chance(0.55)
        dream = Self.dreams[random.next(Self.dreams.count)]

        let first = random.next(Self.propPool.count)
        let second = (first + 1 + random.next(Self.propPool.count - 1)) % Self.propPool.count
        props = random.chance(0.7) ? [Self.propPool[first], Self.propPool[second]] : [Self.propPool[first]]
        jitter = CGPoint(x: random.unit() * 2 - 1, y: random.unit() * 2 - 1)
    }
}

/// A small deterministic generator (FNV-1a seed, SplitMix64 steps). `Hasher` is no use here
/// because it is reseeded on every launch.
struct StableRandom {
    private var state: UInt64

    init(seed: String) {
        state = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            state = (state ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
    }

    mutating func nextRaw() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }

    /// A value in `0..<bound`.
    mutating func next(_ bound: Int) -> Int { Int(nextRaw() % UInt64(max(bound, 1))) }

    /// A value in `0..<1`.
    mutating func unit() -> CGFloat { CGFloat(nextRaw() >> 11) / CGFloat(1 << 53) }

    mutating func chance(_ probability: CGFloat) -> Bool { unit() < probability }
}
