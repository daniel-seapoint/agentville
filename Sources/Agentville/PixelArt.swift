import AgentvilleCore
import SpriteKit

/// Agents are drawn from character maps at one pixel per cell and scaled up with
/// nearest-neighbour filtering, so they stay crisp at any size.
///
/// Colour keys: `B` body, `D` shaded body, `A` highlight, `W` white, `K` dark, `.` transparent,
/// plus fixed colours for clothing and furniture (see `fixedColors`).
enum PixelArt {
    private struct Body {
        var rows: [String]
        /// First row of the head; hats sit relative to this.
        var headTop: Int
        /// First row of the eyes; glasses sit here.
        var eyeTop: Int
    }

    private static let bodies: [AgentSource: Body] = [
        .claude: Body(rows: [
            "...B....B...",
            "...B....B...",
            "..BBBBBBBB..",
            ".BBBBBBBBBB.",
            ".BWWBBBBWWB.",
            ".BWKBBBBWKB.",
            ".BBBBBBBBBB.",
            "..BBBBBBBB..",
            "...DDDDDD...",
            "..BBBBBBBB..",
            "..BBABBBBB..",
            "..BBBBBBBB..",
        ], headTop: 2, eyeTop: 4),
        .codex: Body(rows: [
            ".....AA.....",
            ".....BB.....",
            ".BBBBBBBBBB.",
            ".BBBBBBBBBB.",
            ".BKKKKKKKKB.",
            ".BKWKKKKWKB.",
            ".BKKKKKKKKB.",
            ".BBBBBBBBBB.",
            "...DDDDDD...",
            ".BBBBBBBBBB.",
            ".BBABBBBBBB.",
            "..BBBBBBBB..",
        ], headTop: 2, eyeTop: 4),
        .copilot: Body(rows: [
            "..BBBBBBBB..",
            ".BBBBBBBBBB.",
            ".BBBBBBBBBB.",
            "BKKKKBBKKKKB",
            "BKWWKBBKWWKB",
            "BKKKKBBKKKKB",
            ".BBBBBBBBBB.",
            "..BBKBBKBB..",
            "...DDDDDD...",
            "..BBBBBBBB..",
            "..BBABBBBB..",
            "..BBBBBBBB..",
        ], headTop: 0, eyeTop: 3),
    ]

    /// Two leg poses; alternating them is the walk cycle.
    private static let legs = [
        ["..BB....BB..", "..BB....BB.."],
        ["...BB..BB...", "..BB....BB.."],
    ]

    /// Row of the neck in every body map; ties and scarves sit here.
    private static let neckRow = 8

    /// Blank rows above every body so a hat has somewhere to go.
    static let hatRows = 5
    static let bodyRows = 14
    static var canvasRows: Int { hatRows + bodyRows }
    static let agentColumns = 12

    enum Hat: CaseIterable {
        case beanie, topHat, partyHat, cap, crown, headphones
        case cowboy, wizard, chef, hardHat, santa, propeller, halo, viking, fez, mortarboard, bow
        case pirate, beret, flowerCrown, bunnyEars, catEars, sprout, hood, circlet

        /// The rows to draw and where the first one goes relative to the top of the head.
        fileprivate var overlay: (offset: Int, rows: [String]) {
            switch self {
            case .beanie:
                return (-3, [".....WW.....", "...RRRRRR...", "..RRRRRRRR..", "..rrrrrrrr.."])
            case .topHat:
                // Taller and lighter than the other dark hats, with a sheen, so it reads on a dark floor.
                return (-5, ["...hhhhhh...", "...hGhhhh...", "...hGhhhh...", "...RRYYRR...", "hhhhhhhhhhhh"])
            case .partyHat:
                return (-4, [".....YY.....", "....PPPP....", "...PPYYPP...", "..PPPPPPPP.."])
            case .cap:
                return (-2, ["...CCCCCC...", "..CCCCCCCC..", "..ccccccccCC"])
            case .crown:
                return (-3, ["..Y..YY..Y..", "..YYYYYYYY..", "..YRYYYYRY.."])
            case .headphones:
                return (-2, ["...WWWWWW...", "..W......W..", ".W........W.", "GG........GG", "GG........GG"])
            case .cowboy:
                return (-3, ["....OOOO....", "...OooooO...", "OOOOOOOOOOOO"])
            case .wizard:
                return (-4, ["......VV....", ".....VVV....", "....VYVVV...", "..VVVVVVVV..", ".VVVVVVVVVV."])
            case .chef:
                return (-4, ["...WWWWWW...", "..WWWWWWWW..", "..WWWWWWWW..", "...WGGGGW..."])
            case .hardHat:
                return (-3, ["....YYYY....", "...YYWWYY...", ".YYYYYYYYYY."])
            case .santa:
                return (-4, ["....RRR.....", "...RRRRRR...", "..RRRRRRRRWW", "..WWWWWWWW.."])
            case .propeller:
                return (-4, [".RRRRGGYYYY.", ".....GG.....", "...CCRRCC...", "..CCYYYYCC.."])
            case .halo:
                return (-3, ["...YYYYYY...", "..Y......Y..", "...YYYYYY..."])
            case .viking:
                return (-3, ["W..........W", "WW.GGGGGG.WW", ".WGGGGGGGGW.", "..GGYGGYGG.."])
            case .fez:
                return (-3, ["....RRRR.Y..", "...RRRRRRY..", "...RRRRRR..."])
            case .mortarboard:
                return (-3, [".HHHHHHHHHH.", "...HHHHHHY..", "...HHHHHH.Y."])
            case .bow:
                return (-2, ["..PP....PP..", "..PPPRRPPP.."])
            case .pirate:
                return (-3, ["...KKKKKK...", "..KKKWWKKK..", "KKKKKKKKKKKK"])
            case .beret:
                return (-2, [".....K......", "..rrrrrrrr..", ".rrrrrrrrrrr"])
            case .flowerCrown:
                return (-1, ["..P..Y..P...", ".NPNNYNNPNN."])
            case .bunnyEars:
                return (-5, ["..WW....WW..", "..WP....PW..", "..WP....PW..", "..WP....PW..", "..WW....WW.."])
            case .catEars:
                // In the agent's own colour, so they look like part of it.
                return (-2, ["..B......B..", "..BP....PB.."])
            case .sprout:
                return (-3, ["...NN.NN....", "....NNN.....", ".....N......"])
            case .hood:
                // A traveller's cloak hood, falling down either side of the face.
                return (-2, ["....gggg....", "..gggggggg..", ".gggggggggg.", "gg........gg", "g..........g",
                             "g..........g", "gg........gg"])
            case .circlet:
                return (0, ["..YYYSSYYY.."])
            }
        }
    }

    /// Something worn on the face or round the neck. An agent wears at most one of each.
    enum Accessory: CaseIterable {
        case sunglasses, heartGlasses, nerdGlasses, roundGlasses, monocle, eyepatch, mustache
        case bowTie, scarf, stripedScarf, necktie, goldChain

        var isOnFace: Bool {
            switch self {
            case .sunglasses, .heartGlasses, .nerdGlasses, .roundGlasses, .monocle, .eyepatch, .mustache: return true
            case .bowTie, .scarf, .stripedScarf, .necktie, .goldChain: return false
            }
        }

        static let face = allCases.filter(\.isOnFace)
        static let neck = allCases.filter { !$0.isOnFace }

        /// The rows to draw, and whether they are placed relative to the eyes or the neck.
        fileprivate var overlay: (fromEyes: Bool, offset: Int, rows: [String]) {
            switch self {
            case .sunglasses:
                return (true, 0, [".KKKKKKKKKK.", ".KSKK..KSKK."])
            case .heartGlasses:
                return (true, 0, [".PPPP..PPPP.", ".PPPPPPPPPP.", "..PP....PP.."])
            case .nerdGlasses:
                // Frames only, so the eyes show through the lenses.
                return (true, -1, [".KKKK..KKKK.", ".K..KKKK..K.", ".K..K..K..K.", ".KKKK..KKKK."])
            case .roundGlasses:
                // Thin round wire frames, a ring round each eye.
                return (true, -1, ["..KK....KK..", ".K..K..K..K.", ".K..KKKK..K.", "..KK....KK.."])
            case .monocle:
                return (true, -1, [".......YYYY.", ".......Y..Y.", ".......Y..Y.", ".......YYYY.", "..........Y."])
            case .eyepatch:
                return (true, -1, [".KKKKKKKKKK.", ".KKKK.......", ".KKKK.......", "..KK........"])
            case .mustache:
                return (true, 2, ["...oooooo...", "..oo....oo.."])
            case .bowTie:
                return (false, 0, ["...RRKKRR..."])
            case .scarf:
                return (false, 0, ["..RRRRRRRR..", ".......RR..."])
            case .stripedScarf:
                return (false, 0, ["..RRYYRRYY..", ".......YR...", ".......RY..."])
            case .necktie:
                return (false, 0, [".....CC.....", ".....CC.....", "....CCCC....", ".....CC....."])
            case .goldChain:
                return (false, 0, ["...Y....Y...", "....Y..Y....", ".....YY....."])
            }
        }
    }

    /// Markings on the agent's own body colour. Drawn only over the body, never over eyes or clothes.
    enum Pattern: CaseIterable {
        case plain, stripes, spots, belly, overalls

        /// Repaints the body cells of a composed agent; `top` is the canvas row of the body map's first row.
        fileprivate func apply(to canvas: inout [[Character]], top: Int) {
            func paint(_ row: Int, _ column: Int, _ cell: Character) {
                let y = top + row
                guard canvas.indices.contains(y), canvas[y].indices.contains(column),
                      "BA".contains(canvas[y][column]) else { return }
                canvas[y][column] = cell
            }
            switch self {
            case .plain:
                break
            case .stripes:
                for row in [9, 11] { for column in 0..<PixelArt.agentColumns { paint(row, column, "A") } }
            case .spots:
                for (row, column) in [(3, 7), (6, 3), (7, 8), (9, 7), (11, 4), (2, 4)] { paint(row, column, "A") }
            case .belly:
                for row in 9...11 { for column in 4...7 { paint(row, column, "E") } }
            case .overalls:
                // Straps over the shoulders, then denim from the waist down, legs included.
                paint(9, 3, "c")
                paint(9, 8, "c")
                for row in 10...13 { for column in 0..<PixelArt.agentColumns { paint(row, column, "c") } }
            }
        }
    }

    /// Everything an agent wears, which together with its colour and provider decides how it looks.
    struct Look: Hashable {
        var hat: Hat?
        var accessories: [Accessory] = []
        var pattern: Pattern = .plain
    }

    static let palette: [(CGFloat, CGFloat, CGFloat)] = [
        (0.55, 0.49, 0.96), // purple
        (0.94, 0.54, 0.24), // orange
        (0.94, 0.36, 0.36), // red
        (0.31, 0.56, 0.97), // blue
        (0.21, 0.76, 0.86), // cyan
        (0.30, 0.76, 0.54), // green
        (0.91, 0.47, 0.73), // pink
        (0.90, 0.75, 0.29), // yellow
        (0.18, 0.70, 0.66), // teal
        (0.62, 0.82, 0.30), // lime
        (0.80, 0.36, 0.86), // magenta
        (0.98, 0.56, 0.48), // coral
        (0.66, 0.48, 0.34), // cocoa
        (0.45, 0.52, 0.98), // periwinkle
        (0.75, 0.78, 0.84), // silver
    ]

    private static let fixedColors: [Character: (CGFloat, CGFloat, CGFloat)] = [
        "W": (1, 1, 1),
        "K": (0.09, 0.10, 0.13),
        "R": (0.90, 0.26, 0.26), "r": (0.68, 0.17, 0.19),   // red, dark red
        "Y": (0.98, 0.80, 0.25),                             // gold
        "P": (0.93, 0.40, 0.75),                             // pink
        "C": (0.25, 0.50, 0.95), "c": (0.17, 0.36, 0.75),   // blue, dark blue
        "H": (0.27, 0.29, 0.35),                             // charcoal
        "h": (0.42, 0.45, 0.56),                             // slate
        "G": (0.58, 0.61, 0.66),                             // grey
        "S": (0.55, 0.80, 1.00),                             // glint
        "O": (0.88, 0.60, 0.29), "o": (0.62, 0.40, 0.18),   // wood, dark wood
        "L": (0.62, 0.79, 0.94), "l": (0.47, 0.66, 0.86),   // blanket, blanket fold
        "N": (0.30, 0.76, 0.54),                             // leaf green
        "U": (0.38, 0.44, 0.66), "u": (0.28, 0.33, 0.52),   // upholstery, its seams
        "V": (0.56, 0.36, 0.86),                             // violet
        "E": (0.98, 0.94, 0.84),                             // cream
        "T": (1.00, 0.85, 0.12),                             // cartoon skin
        "Q": (0.80, 0.64, 0.40),                             // stubble
        "g": (0.20, 0.36, 0.20),                             // cloak green
    ]

    private static func paletteEntry(_ index: Int) -> (CGFloat, CGFloat, CGFloat) {
        palette[((index % palette.count) + palette.count) % palette.count]
    }

    static func color(_ index: Int) -> NSColor {
        let (r, g, b) = paletteEntry(index)
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    /// Badge colour for each provider. Agents are coloured per agent, so the badge is what
    /// identifies the provider at a glance.
    static func providerColor(_ source: AgentSource) -> NSColor {
        switch source {
        case .claude: return NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)
        case .codex: return NSColor(srgbRed: 0.25, green: 0.78, blue: 0.62, alpha: 1)
        case .copilot: return NSColor(srgbRed: 0.66, green: 0.55, blue: 0.98, alpha: 1)
        }
    }

    // MARK: Agents

    struct AgentTextures {
        /// The walk cycle; the first frame doubles as the standing pose.
        var walk: [SKTexture]
        /// Standing with eyes closed, for those who doze on their feet.
        var asleep: SKTexture
    }

    private struct AgentKey: Hashable {
        var source: AgentSource
        var color: Int
        var look: Look
    }

    private static var agentCache: [AgentKey: AgentTextures] = [:]

    static func agentTextures(source: AgentSource, colorIndex: Int, look: Look) -> AgentTextures {
        let key = AgentKey(source: source, color: ((colorIndex % palette.count) + palette.count) % palette.count, look: look)
        if let cached = agentCache[key] { return cached }
        let tint = paletteEntry(colorIndex)
        func frame(legs: [String], asleep: Bool) -> SKTexture {
            texture(rows: compose(source, legs: legs, look: look, asleep: asleep, toon: style == .toon), tint: tint)
        }
        let textures = AgentTextures(walk: legs.map { frame(legs: $0, asleep: false) },
                                     asleep: frame(legs: legs[0], asleep: true))
        agentCache[key] = textures
        return textures
    }

    /// The standing agent as an image for SwiftUI, `height` points tall including hat room
    /// (and taller still by whatever margin the art style draws around it).
    static func agentImage(source: AgentSource, colorIndex: Int, look: Look, height: CGFloat) -> NSImage {
        let standing = agentTextures(source: source, colorIndex: colorIndex, look: look).walk[0]
        let cell = height / CGFloat(canvasRows)
        let size = spriteSize((agentColumns, canvasRows), pixel: cell)
        return NSImage(cgImage: standing.cgImage(), size: size)
    }

    /// Size for a sprite of a map `cells` big drawn at `pixel` points per cell, including the
    /// margin the current style leaves round its textures for outlines and glows. The margin
    /// is the same on every side, so the map's centre stays at the sprite's centre.
    static func spriteSize(_ cells: (columns: Int, rows: Int), pixel: CGFloat) -> CGSize {
        let margin = 2 * style.margin
        return CGSize(width: CGFloat(cells.columns + margin) * pixel, height: CGFloat(cells.rows + margin) * pixel)
    }

    /// The app icon's mascot: the orange Codex-shaped agent in a crown, standing, drawn large.
    /// Returns the image and how many of its rows at the top are empty.
    static func mascot(style: Style) -> (image: CGImage, emptyRowsOnTop: Int, rows: Int) {
        let rows = compose(.codex, legs: legs[0], look: Look(hat: .crown), asleep: false)
        let tint = paletteEntry(1)
        let texture = style == .pixel ? pixelTexture(rows: rows, tint: tint)
                                      : smoothTexture(rows: rows, tint: tint, cell: 40)
        let empty = rows.firstIndex { $0.contains { $0 != "." } } ?? 0
        return (texture.cgImage(), empty, rows.count)
    }

    /// The mascot as a menu bar icon: its silhouette, with the visor cut out so the eyes show.
    /// A template image, so macOS tints it to suit a light or dark menu bar.
    static func menuBarIcon() -> NSImage {
        let all = compose(.codex, legs: legs[0], look: Look(hat: .crown), asleep: false)
        let rows = Array(all.drop { row in row.allSatisfy { $0 == "." } })
        let cell = 4 // pixels; drawn at about three times the size it is shown
        let width = agentColumns * cell
        let height = rows.count * cell
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for (rowIndex, row) in rows.enumerated() {
            for (column, character) in row.enumerated() where character != "." && character != "K" {
                context.fill(CGRect(x: column * cell, y: height - (rowIndex + 1) * cell, width: cell, height: cell))
            }
        }
        let points: CGFloat = 17
        let image = NSImage(cgImage: context.makeImage()!,
                            size: NSSize(width: points * CGFloat(width) / CGFloat(height), height: points))
        image.isTemplate = true
        return image
    }

    /// How many rows a hat rises above the top of the body map, for spacing labels.
    static func rowsAboveBody(source: AgentSource, hat: Hat?) -> Int {
        guard let hat, let body = bodies[source] else { return 0 }
        return max(0, -(body.headTop + hat.overlay.offset))
    }

    private static func compose(_ source: AgentSource, legs: [String], look: Look, asleep: Bool,
                                toon: Bool = false) -> [[Character]] {
        let body = bodies[source]!
        let bodyRows = asleep ? closingEyes(body.rows) : body.rows
        var canvas = Array(repeating: Array(repeating: Character("."), count: agentColumns), count: hatRows)
        canvas += (bodyRows + legs).map(Array.init)
        let headTop = hatRows + body.headTop
        // After the eyes are worked out, since a cream belly would otherwise read as eyes.
        look.pattern.apply(to: &canvas, top: hatRows)
        if toon {
            // Cartoon skin from the neck up, ears and antennae included, so the agent's own
            // colour reads as its clothes. Then a stubbly muzzle round the mouth.
            for row in 0..<(hatRows + neckRow) {
                for column in canvas[row].indices where "BAD".contains(canvas[row][column]) {
                    canvas[row][column] = "T"
                }
            }
            let chin = hatRows + neckRow - 1
            for column in 3...8 where canvas[chin][column] == "T" {
                canvas[chin][column] = "Q"
            }
        }

        func overlay(_ rows: [String], at top: Int) {
            for (index, row) in rows.enumerated() where canvas.indices.contains(top + index) {
                for (column, cell) in row.enumerated() where cell != "." {
                    canvas[top + index][column] = cell
                }
            }
        }

        if let hat = look.hat {
            // Antennae would poke through the hat.
            for row in 0..<headTop { canvas[row] = Array(repeating: ".", count: agentColumns) }
            overlay(hat.overlay.rows, at: headTop + hat.overlay.offset)
        }
        for accessory in look.accessories {
            let placement = accessory.overlay
            let anchor = hatRows + (placement.fromEyes ? body.eyeTop : neckRow)
            overlay(placement.rows, at: anchor + placement.offset)
        }
        return canvas
    }

    /// Eyes are the rows containing white. The last of them becomes a dark line and any
    /// above it are filled in, which reads as closed eyes on every body shape.
    private static func closingEyes(_ rows: [String]) -> [String] {
        let eyeRows = rows.indices.filter { rows[$0].contains("W") }
        var result = rows
        for index in eyeRows {
            let isLast = index == eyeRows.last
            result[index] = String(rows[index].map { $0 == "W" ? (isLast ? "K" : "B") : $0 })
        }
        return result
    }

    // MARK: Beds

    /// A bed seen from the side with the agent tucked in, head on the pillow.
    private static let bedRows = [
        "O...................",
        "O..BBBBB............",
        "O.BBBBBBB..........O",
        "O.BKKBBBBLLLLLLLLL.O",
        "OWBBBBBBLLLLLLLLLLLO",
        "OWWWBBLLLLLLLLLLLLLO",
        "OWWWWLLLLLlLLLLlLLLO",
        "OOOOOOOOOOOOOOOOOOOO",
        "OooooooooooooooooooO",
        "OO................OO",
        "OO................OO",
    ]

    static var bedSize: (columns: Int, rows: Int) { (bedRows[0].count, bedRows.count) }

    private static var bedCache: [Int: SKTexture] = [:]

    static func bed(colorIndex: Int) -> SKTexture {
        let key = ((colorIndex % palette.count) + palette.count) % palette.count
        if let cached = bedCache[key] { return cached }
        let made = texture(rows: bedRows.map(Array.init), tint: paletteEntry(colorIndex))
        bedCache[key] = made
        return made
    }

    // MARK: Empty state

    /// A workbench with a desk lamp, a pot plant and a mug. Rows may be ragged on the right.
    private static let workbenchRows = [
        "....GGGGG",
        "...GYYYYYG",
        "..GYYYYYYYG",
        "......G",
        "......G.....N.N...WWWW",
        "......G......N....LLLLWW",
        "......G.....NNN...LLLL.W",
        ".....GGG....RRR...LLLLWW",
        "OOOOOOOOOOOOOOOOOOOOOOOOOOOOOO",
        "oooooooooooooooooooooooooooooo",
        ".OO........................OO",
        ".OO........................OO",
        ".OO........................OO",
        ".OO........................OO",
    ]

    /// A sitting dog facing right. The two frames differ only in the tail, which is the wag.
    private static let dogFrames = [
        [
            ".......oo",
            "......oOOOO",
            "......oOKOOK",
            "......OOOOOO",
            ".....RRRR",
            "....OOOWW",
            "O..OOOOWW",
            ".O.OOOOWW",
            "..OOOOOOO",
            "..OOOOOOOO",
            "..OO...O.O",
        ],
        [
            ".......oo",
            "......oOOOO",
            "......oOKOOK",
            "......OOOOOO",
            ".....RRRR",
            "....OOOWW",
            "...OOOOWW",
            "...OOOOWW",
            "OOOOOOOOO",
            "..OOOOOOOO",
            "..OO...O.O",
        ],
    ]

    static var dogSize: (columns: Int, rows: Int) { (12, dogFrames[0].count) }

    static func dog() -> [SKTexture] {
        // Pad every row to the same width so both frames line up exactly.
        dogFrames.map { frame in
            texture(rows: frame.map { Array($0.padding(toLength: dogSize.columns, withPad: ".", startingAt: 0)) },
                    tint: (1, 1, 1))
        }
    }

    /// What the lounge is furnished with.
    enum Furniture: CaseIterable {
        case couch, plant, lamp

        fileprivate var rows: [String] {
            switch self {
            case .couch:
                // A two-seater, seen from the front.
                return [
                    "..UUUUUUUUUUUUUUUU..",
                    ".UUUUUUUUUUUUUUUUUU.",
                    ".UUUUUUUUUUUUUUUUUU.",
                    "UUuuuuuuuuuuuuuuuuUU",
                    "UUUUUUUUUuUUUUUUUUUU",
                    "UUUUUUUUUuUUUUUUUUUU",
                    "UUuuuuuuuuuuuuuuuuUU",
                    ".oo..............oo.",
                ]
            case .plant:
                return [
                    "..N..N..",
                    ".NNN.NN.",
                    "NNNNNNNN",
                    ".NNNNNN.",
                    "..NNNN..",
                    "...NN...",
                    "...NN...",
                    ".RRRRRR.",
                    ".RRRRRR.",
                    "..RRRR..",
                ]
            case .lamp:
                return [
                    ".YYYYY.",
                    "YYYYYYY",
                    "YYYYYYY",
                    "...G...", "...G...", "...G...", "...G...", "...G...", "...G...", "...G...", "...G...",
                    "..GGG..",
                    ".GGGGG.",
                ]
            }
        }

        var size: (columns: Int, rows: Int) { (rows[0].count, rows.count) }
    }

    private static var furnitureCache: [Furniture: SKTexture] = [:]

    static func furniture(_ item: Furniture) -> SKTexture {
        if let cached = furnitureCache[item] { return cached }
        let made = texture(rows: item.rows.map(Array.init), tint: (1, 1, 1))
        furnitureCache[item] = made
        return made
    }

    /// A full mug of coffee, handle to the right.
    private static let mugRows = [
        "oooooo",
        "LLLLLLWW",
        "LLLLLL.W",
        "LLLLLLWW",
        "LLLLLL",
        ".LLLL",
    ]

    static var mugSize: (columns: Int, rows: Int) { (mugRows.map(\.count).max() ?? 1, mugRows.count) }

    static func mug() -> SKTexture {
        texture(rows: mugRows.map(Array.init), tint: (1, 1, 1))
    }

    /// A robot vacuum, seen from the side, with its power light on.
    private static let vacuumRows = [
        "..GGGGGG",
        ".GGGNGGGG",
        "GGGGGGGGGG",
        ".o......o",
    ]

    static var vacuumSize: (columns: Int, rows: Int) { (vacuumRows.map(\.count).max() ?? 1, vacuumRows.count) }

    static func vacuum() -> SKTexture {
        texture(rows: vacuumRows.map(Array.init), tint: (1, 1, 1))
    }

    static var workbenchSize: (columns: Int, rows: Int) {
        (workbenchRows.map(\.count).max() ?? 1, workbenchRows.count)
    }

    static func workbench() -> SKTexture {
        texture(rows: workbenchRows.map(Array.init), tint: (1, 1, 1))
    }

    // MARK: Rendering

    /// How the character maps are turned into images.
    enum Style: String, CaseIterable, Identifiable {
        /// The maps with their corners rounded off and edges anti-aliased.
        case smooth
        /// One hard-edged square per cell.
        case pixel
        /// Smooth, with a dark cartoon outline round every shape.
        case outlined
        /// Smooth, with a soft halo of its own colour, like it is lit from within.
        case glow
        /// Cartoon sitcom: yellow skin, a stubbly muzzle and thick black ink lines.
        case toon
        /// A flickering blue projection with scanlines, beamed in from far away.
        case hologram
        /// Sepia ink on old parchment, like a hand-drawn map of a faraway land.
        case parchment
        /// A silvery, see-through apparition that glows and sparkles.
        case spectral

        var id: Self { self }

        var label: String {
            switch self {
            case .smooth: return "Smooth"
            case .pixel: return "Pixel"
            case .outlined: return "Outlined"
            case .glow: return "Glow"
            case .toon: return "Toon"
            case .hologram: return "Hologram"
            case .parchment: return "Parchment"
            case .spectral: return "Spectral"
            }
        }

        /// Empty cells left round every texture, so outlines and halos are not cut off.
        var margin: Int {
            switch self {
            case .smooth, .pixel: return 0
            case .outlined, .toon, .parchment: return 1
            case .glow, .hologram, .spectral: return 2
            }
        }
    }

    /// Off while drawing pictures in several styles, so doing so does not change the user's choice.
    static var savesStyle = true

    /// Persisted, so the choice survives a relaunch. Changing it drops every cached texture;
    /// nodes already on screen keep their old ones until they are rebuilt.
    static var style: Style = UserDefaults.standard.string(forKey: "artStyle").flatMap(Style.init) ?? .smooth {
        didSet {
            guard style != oldValue else { return }
            if savesStyle { UserDefaults.standard.set(style.rawValue, forKey: "artStyle") }
            clearCaches()
        }
    }

    /// Drops every cached texture, so the next ones are drawn in the current style and theme.
    static func clearCaches() {
        agentCache.removeAll()
        bedCache.removeAll()
        furnitureCache.removeAll()
    }

    private static func color(of cell: Character, tint: (CGFloat, CGFloat, CGFloat)) -> (CGFloat, CGFloat, CGFloat)? {
        let (r, g, b) = tint
        switch cell {
        case ".": return nil
        case "B": return (r, g, b)
        case "D": return (r * 0.6, g * 0.6, b * 0.6)
        case "A": return (min(1, r + 0.25), min(1, g + 0.25), min(1, b + 0.25))
        default: return fixedColors[cell]
        }
    }

    private static func texture(rows: [[Character]], tint: (CGFloat, CGFloat, CGFloat)) -> SKTexture {
        let rows = padded(rows, by: style.margin)
        switch style {
        case .pixel: return pixelTexture(rows: rows, tint: tint)
        case .smooth: return smoothTexture(rows: rows, tint: tint)
        case .outlined: return smoothTexture(rows: rows, tint: tint, finish: .outline)
        case .glow: return smoothTexture(rows: rows, tint: tint, finish: .glow)
        case .toon: return smoothTexture(rows: rows, tint: tint, finish: .toon)
        case .hologram: return smoothTexture(rows: rows, tint: tint, finish: .hologram)
        case .parchment: return smoothTexture(rows: rows, tint: tint, finish: .parchment)
        case .spectral: return smoothTexture(rows: rows, tint: tint, finish: .spectral)
        }
    }

    /// The map with `margin` empty cells added on every side, and ragged rows evened out.
    private static func padded(_ rows: [[Character]], by margin: Int) -> [[Character]] {
        guard margin > 0 else { return rows }
        let width = (rows.map(\.count).max() ?? 0) + margin * 2
        let blank = [Character](repeating: ".", count: width)
        let side = [Character](repeating: ".", count: margin)
        let body = rows.map { row in side + row + [Character](repeating: ".", count: width - margin - row.count) }
        return Array(repeating: blank, count: margin) + body + Array(repeating: blank, count: margin)
    }

    /// What the smooth renderer adds round the outside of each shape.
    private enum Finish {
        case plain, outline, glow, toon, hologram, parchment, spectral
    }

    private static func pixelTexture(rows: [[Character]], tint: (CGFloat, CGFloat, CGFloat)) -> SKTexture {
        let width = rows.map(\.count).max() ?? 1
        let height = rows.count
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for (rowIndex, row) in rows.enumerated() {
            for (column, cell) in row.enumerated() {
                guard let rgb = color(of: cell, tint: tint) else { continue }
                context.setFillColor(CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1))
                // Core Graphics has its origin at the bottom; the maps read top-down.
                context.fill(CGRect(x: column, y: height - 1 - rowIndex, width: 1, height: 1))
            }
        }
        let texture = SKTexture(cgImage: context.makeImage()!)
        texture.filteringMode = .nearest
        return texture
    }

    /// Draws the same map at many pixels per cell, with the stair-steps melted into curves.
    ///
    /// Each colour's cells are blurred into a soft field. A pixel is inside the shape where the
    /// fields add up to more than half, which rounds every corner by about the blur radius, and
    /// takes the colour whose field is strongest there, so neighbouring colours meet along a
    /// smooth line with no gaps between them.
    /// - Parameter cell: pixels per map cell. The default suits the floor; the app icon asks for more.
    private static func smoothTexture(rows: [[Character]], tint: (CGFloat, CGFloat, CGFloat),
                                      cell: Int = 12, finish: Finish = .plain) -> SKTexture {
        let columns = rows.map(\.count).max() ?? 1
        let width = columns * cell
        let height = rows.count * cell
        let radius = cell * 3 / 8

        var fields: [(rgb: (CGFloat, CGFloat, CGFloat), values: [Float])] = []
        var fieldIndex: [Character: Int] = [:]
        for (rowIndex, row) in rows.enumerated() {
            for (column, character) in row.enumerated() {
                guard let rgb = color(of: character, tint: tint) else { continue }
                if fieldIndex[character] == nil {
                    fieldIndex[character] = fields.count
                    fields.append((rgb, [Float](repeating: 0, count: width * height)))
                }
                let index = fieldIndex[character]!
                for y in rowIndex * cell..<(rowIndex + 1) * cell {
                    for x in column * cell..<(column + 1) * cell {
                        fields[index].values[y * width + x] = 1
                    }
                }
            }
        }
        for index in fields.indices {
            // Two box blurs each way is close to a Gaussian.
            for _ in 0..<2 {
                fields[index].values = boxBlur(fields[index].values, width: width, height: height, radius: radius)
            }
        }

        // The sum of the fields is the whole shape blurred. Blurred again, much wider, it is
        // the halo for the glow style.
        var union = [Float](repeating: 0, count: width * height)
        for field in fields {
            for offset in union.indices { union[offset] += field.values[offset] }
        }
        var halo: [Float] = []
        if finish == .glow || finish == .hologram || finish == .spectral {
            halo = union
            for _ in 0..<2 { halo = boxBlur(halo, width: width, height: height, radius: cell) }
        }
        // Outlines are light on a dark floor and dark on a light one, so they always show.
        let outlineInk: (Float, Float, Float) = Theme.colors.isLight ? (0.10, 0.11, 0.14) : (0.93, 0.94, 0.97)
        // A glow is the agent's own colour, lifted towards white.
        let glowColor = (Float(min(1, tint.0 * 0.6 + 0.4)), Float(min(1, tint.1 * 0.6 + 0.4)),
                         Float(min(1, tint.2 * 0.6 + 0.4)))
        // Toon lines are always black; on a dark floor a pale rim round them keeps them visible.
        let toonInk: (Float, Float, Float) = (0.05, 0.05, 0.07)
        let toonRim: Float = Theme.colors.isLight ? 0 : 0.9
        let hologramBlue: (Float, Float, Float) = (0.40, 0.80, 1.0)
        let sepiaDark: (Float, Float, Float) = (0.32, 0.19, 0.08)
        let sepiaLight: (Float, Float, Float) = (0.97, 0.90, 0.72)
        let sepiaInk: (Float, Float, Float) = (0.22, 0.13, 0.05)
        let spectralSilver: (Float, Float, Float) = (0.72, 0.86, 1.0)

        func smoothstep(_ value: Float) -> Float {
            let x = min(max(value, 0), 1)
            return x * x * (3 - 2 * x)
        }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for offset in 0..<width * height {
            let total = union[offset]
            var strongest = 0
            var strongestValue: Float = 0
            for (index, field) in fields.enumerated() {
                let value = field.values[offset]
                if value > strongestValue {
                    strongestValue = value
                    strongest = index
                }
            }
            // A narrow ramp around one half anti-aliases the outline.
            var alpha = smoothstep((total - 0.42) / 0.16)
            var red: Float = 0, green: Float = 0, blue: Float = 0
            if alpha > 0 {
                let rgb = fields[strongest].rgb
                red = Float(rgb.0) * alpha
                green = Float(rgb.1) * alpha
                blue = Float(rgb.2) * alpha
            }
            if finish == .hologram, alpha > 0 {
                // Every colour becomes a shade of projector blue by its brightness, see-through,
                // with every other band of rows dimmed into scanlines.
                let brightness = (red * 0.3 + green * 0.59 + blue * 0.11) / alpha
                let level = min(1, 0.4 + 0.8 * brightness)
                let scanline: Float = (offset / width) % 4 < 2 ? 1 : 0.55
                alpha *= 0.8 * scanline
                red = hologramBlue.0 * level * alpha
                green = hologramBlue.1 * level * alpha
                blue = hologramBlue.2 * level * alpha
            }
            if finish == .parchment || finish == .spectral, alpha > 0 {
                // Both are drawn by brightness alone: parchment in sepia from dark ink to pale
                // paper, the apparition from silver-blue to white and see-through.
                let brightness = min(1, (red * 0.3 + green * 0.59 + blue * 0.11) / alpha)
                let low = finish == .parchment ? sepiaDark : spectralSilver
                let high = finish == .parchment ? sepiaLight : (1, 1, 1)
                let level = finish == .parchment ? brightness.squareRoot() : brightness
                if finish == .spectral { alpha *= 0.72 }
                red = (low.0 + (high.0 - low.0) * level) * alpha
                green = (low.1 + (high.1 - low.1) * level) * alpha
                blue = (low.2 + (high.2 - low.2) * level) * alpha
            }
            // Whatever is behind the shape, as premultiplied colour and coverage.
            var under: (Float, Float, Float, Float) = (0, 0, 0, 0)
            switch finish {
            case .plain:
                break
            case .outline:
                // The same field cut at a lower level reaches a little further out.
                let edge = smoothstep((total - 0.08) / 0.12)
                under = (outlineInk.0 * edge, outlineInk.1 * edge, outlineInk.2 * edge, edge)
            case .glow:
                let glow = min(1, halo[offset] * 1.6) * 0.55
                under = (glowColor.0 * glow, glowColor.1 * glow, glowColor.2 * glow, glow)
            case .toon:
                // A thick black line, and outside it the rim on dark floors.
                let line = smoothstep((total - 0.10) / 0.08)
                let rim = smoothstep((total - 0.03) / 0.05) * toonRim
                let ink = (toonInk.0 * line, toonInk.1 * line, toonInk.2 * line, line)
                let pale = (1 - line) * rim
                under = (ink.0 + pale, ink.1 + pale, ink.2 + pale, ink.3 + pale)
            case .hologram:
                let glow = min(1, halo[offset] * 1.6) * 0.35
                under = (hologramBlue.0 * glow, hologramBlue.1 * glow, hologramBlue.2 * glow, glow)
            case .parchment:
                // A fine line of dark brown ink.
                let line = smoothstep((total - 0.14) / 0.10)
                under = (sepiaInk.0 * line, sepiaInk.1 * line, sepiaInk.2 * line, line)
            case .spectral:
                let glow = min(1, halo[offset] * 1.6) * 0.45
                under = (spectralSilver.0 * glow, spectralSilver.1 * glow, spectralSilver.2 * glow, glow)
            }
            // The shape over whatever is under it.
            let coverage = alpha + under.3 * (1 - alpha)
            guard coverage > 0 else { continue }
            red += under.0 * (1 - alpha)
            green += under.1 * (1 - alpha)
            blue += under.2 * (1 - alpha)
            pixels[offset * 4] = UInt8(min(255, (red * 255).rounded()))
            pixels[offset * 4 + 1] = UInt8(min(255, (green * 255).rounded()))
            pixels[offset * 4 + 2] = UInt8(min(255, (blue * 255).rounded()))
            pixels[offset * 4 + 3] = UInt8(min(255, (coverage * 255).rounded()))
        }

        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let image = pixels.withUnsafeMutableBytes { buffer -> CGImage in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            return context.makeImage()!
        }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .linear
        texture.usesMipmaps = true
        return texture
    }

    /// A separable box blur. Outside the image counts as empty, so shapes that touch the edge
    /// are still rounded at their corners.
    private static func boxBlur(_ source: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        let span = Float(radius * 2 + 1)
        var horizontal = [Float](repeating: 0, count: source.count)
        for y in 0..<height {
            var sum: Float = 0
            for x in 0...min(radius, width - 1) { sum += source[y * width + x] }
            for x in 0..<width {
                horizontal[y * width + x] = sum / span
                if x + radius + 1 < width { sum += source[y * width + x + radius + 1] }
                if x - radius >= 0 { sum -= source[y * width + x - radius] }
            }
        }
        var result = [Float](repeating: 0, count: source.count)
        for x in 0..<width {
            var sum: Float = 0
            for y in 0...min(radius, height - 1) { sum += horizontal[y * width + x] }
            for y in 0..<height {
                result[y * width + x] = sum / span
                if y + radius + 1 < height { sum += horizontal[(y + radius + 1) * width + x] }
                if y - radius >= 0 { sum -= horizontal[(y - radius) * width + x] }
            }
        }
        return result
    }
}

extension NSAttributedString {
    static func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
        ])
    }
}

extension String {
    func truncated(_ limit: Int) -> String {
        count > limit ? String(prefix(limit - 1)) + "…" : self
    }
}
