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
            }
        }
    }

    enum Accessory: CaseIterable {
        case sunglasses, bowTie, scarf
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

    private static var agentCache: [String: AgentTextures] = [:]

    static func agentTextures(source: AgentSource, colorIndex: Int, hat: Hat?, accessory: Accessory?) -> AgentTextures {
        let key = "\(source.rawValue)-\(colorIndex % palette.count)-\(String(describing: hat))-\(String(describing: accessory))"
        if let cached = agentCache[key] { return cached }
        let tint = paletteEntry(colorIndex)
        func frame(legs: [String], asleep: Bool) -> SKTexture {
            texture(rows: compose(source, legs: legs, hat: hat, accessory: accessory, asleep: asleep), tint: tint)
        }
        let textures = AgentTextures(walk: legs.map { frame(legs: $0, asleep: false) },
                                     asleep: frame(legs: legs[0], asleep: true))
        agentCache[key] = textures
        return textures
    }

    /// The standing agent as an image for SwiftUI, `height` points tall including hat room.
    static func agentImage(source: AgentSource, colorIndex: Int, persona: Persona, height: CGFloat) -> NSImage {
        let standing = agentTextures(source: source, colorIndex: colorIndex, hat: persona.hat, accessory: persona.accessory).walk[0]
        let width = height * CGFloat(agentColumns) / CGFloat(canvasRows)
        return NSImage(cgImage: standing.cgImage(), size: NSSize(width: width, height: height))
    }

    /// The app icon's mascot: the orange Codex-shaped agent in a crown, standing, drawn large.
    /// Returns the image and how many of its rows at the top are empty.
    static func mascot(style: Style) -> (image: CGImage, emptyRowsOnTop: Int, rows: Int) {
        let rows = compose(.codex, legs: legs[0], hat: .crown, accessory: nil, asleep: false)
        let tint = paletteEntry(1)
        let texture = style == .smooth ? smoothTexture(rows: rows, tint: tint, cell: 40)
                                       : pixelTexture(rows: rows, tint: tint)
        let empty = rows.firstIndex { $0.contains { $0 != "." } } ?? 0
        return (texture.cgImage(), empty, rows.count)
    }

    /// The mascot as a menu bar icon: its silhouette, with the visor cut out so the eyes show.
    /// A template image, so macOS tints it to suit a light or dark menu bar.
    static func menuBarIcon() -> NSImage {
        let all = compose(.codex, legs: legs[0], hat: .crown, accessory: nil, asleep: false)
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

    private static func compose(_ source: AgentSource, legs: [String], hat: Hat?, accessory: Accessory?,
                                asleep: Bool) -> [[Character]] {
        let body = bodies[source]!
        let bodyRows = asleep ? closingEyes(body.rows) : body.rows
        var canvas = Array(repeating: Array(repeating: Character("."), count: agentColumns), count: hatRows)
        canvas += (bodyRows + legs).map(Array.init)
        let headTop = hatRows + body.headTop

        func overlay(_ rows: [String], at top: Int) {
            for (index, row) in rows.enumerated() where canvas.indices.contains(top + index) {
                for (column, cell) in row.enumerated() where cell != "." {
                    canvas[top + index][column] = cell
                }
            }
        }

        if let hat {
            // Antennae would poke through the hat.
            for row in 0..<headTop { canvas[row] = Array(repeating: ".", count: agentColumns) }
            overlay(hat.overlay.rows, at: headTop + hat.overlay.offset)
        }
        switch accessory {
        case .sunglasses:
            overlay([".KKKKKKKKKK.", ".KSKK..KSKK."], at: hatRows + body.eyeTop)
        case .bowTie:
            overlay(["...RRKKRR..."], at: hatRows + neckRow)
        case .scarf:
            overlay(["..RRRRRRRR..", ".......RR..."], at: hatRows + neckRow)
        case nil:
            break
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
    enum Style: String {
        /// The maps with their corners rounded off and edges anti-aliased.
        case smooth
        /// One hard-edged square per cell.
        case pixel
    }

    /// Persisted, so the choice survives a relaunch. Changing it drops every cached texture;
    /// nodes already on screen keep their old ones until they are rebuilt.
    static var style: Style = UserDefaults.standard.string(forKey: "artStyle").flatMap(Style.init) ?? .smooth {
        didSet {
            guard style != oldValue else { return }
            UserDefaults.standard.set(style.rawValue, forKey: "artStyle")
            agentCache.removeAll()
            bedCache.removeAll()
            furnitureCache.removeAll()
        }
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
        switch style {
        case .pixel: return pixelTexture(rows: rows, tint: tint)
        case .smooth: return smoothTexture(rows: rows, tint: tint)
        }
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
                                      cell: Int = 12) -> SKTexture {
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

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for offset in 0..<width * height {
            var total: Float = 0
            var strongest = 0
            var strongestValue: Float = 0
            for (index, field) in fields.enumerated() {
                let value = field.values[offset]
                total += value
                if value > strongestValue {
                    strongestValue = value
                    strongest = index
                }
            }
            // A narrow ramp around one half anti-aliases the outline.
            let edge = min(max((total - 0.42) / 0.16, 0), 1)
            let alpha = CGFloat(edge * edge * (3 - 2 * edge))
            guard alpha > 0 else { continue }
            let rgb = fields[strongest].rgb
            pixels[offset * 4] = UInt8((rgb.0 * alpha * 255).rounded())
            pixels[offset * 4 + 1] = UInt8((rgb.1 * alpha * 255).rounded())
            pixels[offset * 4 + 2] = UInt8((rgb.2 * alpha * 255).rounded())
            pixels[offset * 4 + 3] = UInt8((alpha * 255).rounded())
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
