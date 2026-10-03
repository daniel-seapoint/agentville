import CoreGraphics
import Foundation

/// The cosmetic quirks of one agent: what it wears, how it rests and what it dreams about.
/// Everything is drawn from a hash of the agent's id, so each agent looks random but keeps
/// the same look for as long as it exists, including across app restarts.
struct Persona {
    private let agentID: String
    /// Hat, glasses or the like, something round the neck, and markings. Themes with a
    /// costume of their own dress the agent up instead; see `look(for:)`.
    let look: PixelArt.Look
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
        self.agentID = agentID
        var random = StableRandom(seed: agentID)
        func pick<T>(_ options: [T]) -> T { options[random.next(options.count)] }
        var hat = random.chance(0.85) ? pick(PixelArt.Hat.allCases) : nil
        var accessories: [PixelArt.Accessory] = []
        if random.chance(0.45) { accessories.append(pick(PixelArt.Accessory.face)) }
        if random.chance(0.4) { accessories.append(pick(PixelArt.Accessory.neck)) }
        // Nobody goes out completely undressed.
        if hat == nil && accessories.isEmpty {
            hat = pick(PixelArt.Hat.allCases)
        }
        // Most agents are plain; the rest have stripes, spots, a belly patch or overalls.
        let pattern = random.chance(0.45) ? pick(Array(PixelArt.Pattern.allCases.dropFirst())) : .plain
        look = PixelArt.Look(hat: Self.demoHats[agentID] ?? hat, accessories: accessories, pattern: pattern)
        sleepsInBed = random.chance(0.55)
        dream = Self.dreams[random.next(Self.dreams.count)]

        let first = random.next(Self.propPool.count)
        let second = (first + 1 + random.next(Self.propPool.count - 1)) % Self.propPool.count
        props = random.chance(0.7) ? [Self.propPool[first], Self.propPool[second]] : [Self.propPool[first]]
        jitter = CGPoint(x: random.unit() * 2 - 1, y: random.unit() * 2 - 1)
    }
}

extension Persona {
    /// What the agent wears on the floor of `theme`. The film and TV themes dress everyone in
    /// costume for that world; the rest leave them in their everyday look. Picked from the
    /// agent's id, so an agent always wears the same costume in the same theme.
    func look(for theme: Theme) -> PixelArt.Look {
        var random = StableRandom(seed: agentID + "/" + theme.rawValue)
        func pick<T>(_ options: [T]) -> T { options[random.next(options.count)] }
        func maybe(_ probability: CGFloat) -> Bool { random.chance(probability) }

        switch theme {
        case .starWars:
            // Knights of the stars in hooded robes, pilots, and every one with an energy blade.
            let hats: [PixelArt.Hat?] = [.robeHood, .robeHood, .pilotHelmet, .buns, .messyHair, nil]
            let hat = pick(hats)
            let robes: [PixelArt.Pattern] = [.robe, .robe, .plain]
            let pattern = hat == .pilotHelmet ? PixelArt.Pattern.plain : pick(robes)
            let capes: [Character] = ["K", "o"]
            let cape: Character? = maybe(0.35) ? pick(capes) : nil
            let blades: [PixelArt.Held] = [.blueBlade, .greenBlade, .redBlade, .purpleBlade]
            return PixelArt.Look(hat: hat, pattern: pattern, cape: cape, held: pick(blades))
        case .harryPotter:
            // Pupils of a school for wizards: robes, scarves, round glasses and wands.
            var accessories: [PixelArt.Accessory] = []
            if maybe(0.5) { accessories.append(.roundGlasses) }
            if maybe(0.6) { accessories.append(.stripedScarf) }
            let hats: [PixelArt.Hat] = [.wizard, .wizard, .messyHair, .longHair, .ponytail, .curlyHair]
            let hat = pick(hats)
            let cape: Character? = maybe(0.4) ? "H" : nil
            let held: PixelArt.Held? = maybe(0.9) ? .wand : nil
            return PixelArt.Look(hat: hat, accessories: accessories, pattern: .schoolRobe, cape: cape, held: held)
        case .lordOfTheRings:
            // A fellowship of the road: a grey wizard with a staff, fair-haired archers in
            // cloaks, helmeted axe-bearers with bushy beards, and sword-carrying travellers.
            let hats: [PixelArt.Hat] = [.greyWizard, .longHair, .curlyHair, .hood, .circlet, .ironHelmet]
            let hat = pick(hats)
            switch hat {
            case .greyWizard:
                return PixelArt.Look(hat: hat, accessories: [.longBeard], pattern: .robe, cape: "h", held: .staff)
            case .ironHelmet:
                return PixelArt.Look(hat: hat, accessories: [.bushyBeard], pattern: .chainmail, held: .axe)
            default:
                let outfits: [PixelArt.Pattern] = [.tunic, .tunic, .chainmail]
                let pattern = pick(outfits)
                let capes: [Character] = ["g", "R"]
                let cape: Character? = maybe(0.6) ? pick(capes) : nil
                let weapons: [PixelArt.Held] = [.sword, .sword, .staff]
                return PixelArt.Look(hat: hat, pattern: pattern, cape: cape, held: pick(weapons))
            }
        case .simpsons:
            // A sitcom neighbourhood: everyday hair, shirts and ties, pearls, and donuts.
            var accessories: [PixelArt.Accessory] = []
            let neckwear: [PixelArt.Accessory] = [.necktie, .pearls]
            if maybe(0.45) { accessories.append(pick(neckwear)) }
            let hats: [PixelArt.Hat?] = [.spikyHair, .messyHair, .ponytail, .curlyHair, .cap, nil]
            let hat = pick(hats)
            let outfits: [PixelArt.Pattern] = [.shirt, .shirt, .overalls, .plain]
            let pattern = pick(outfits)
            let held: PixelArt.Held? = maybe(0.5) ? .donut : nil
            return PixelArt.Look(hat: hat, accessories: accessories, pattern: pattern, held: held)
        default:
            return look
        }
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
