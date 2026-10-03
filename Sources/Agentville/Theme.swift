import AppKit

/// The look of the floor: its colours, and a little weather or ambience drifting over it.
/// The agents keep their own colours whatever the theme.
enum Theme: String, CaseIterable, Identifiable {
    case workshop, daylight, forest, ocean, space, sunset, terminal, winter
    /// Fan tributes to four film and TV worlds. Each dresses the agents in costume for that
    /// world (see `Persona.look(for:)`) and brings its own agent style with it.
    case simpsons, starWars, lordOfTheRings, harryPotter

    var id: Self { self }

    var label: String {
        switch self {
        case .workshop: return "Workshop"
        case .daylight: return "Daylight"
        case .forest: return "Forest"
        case .ocean: return "Ocean"
        case .space: return "Space"
        case .sunset: return "Sunset"
        case .terminal: return "Terminal"
        case .winter: return "Winter"
        case .simpsons: return "The Simpsons"
        case .starWars: return "Star Wars"
        case .lordOfTheRings: return "Lord of the Rings"
        case .harryPotter: return "Harry Potter"
        }
    }

    /// The agent style that goes with this theme, picked along with it.
    var agentStyle: PixelArt.Style? {
        switch self {
        case .simpsons: return .toon
        case .starWars: return .hologram
        case .lordOfTheRings: return .parchment
        case .harryPotter: return .spectral
        default: return nil
        }
    }

    /// Persisted, so the choice survives a relaunch. Launching with `-theme <name>` picks one
    /// for that run only, since arguments are read before the saved setting.
    static var current: Theme = UserDefaults.standard.string(forKey: "theme").flatMap(Theme.init) ?? .workshop {
        didSet {
            guard current != oldValue else { return }
            UserDefaults.standard.set(current.rawValue, forKey: "theme")
        }
    }

    /// What moves over the floor, behind the agents.
    enum Ambience {
        case none, stars, bubbles, fireflies, embers, snow, scanlines
        /// Fat cartoon clouds drifting across a blue sky.
        case clouds
        /// Stars, and every so often the jump to lightspeed.
        case hyperspace
        /// Autumn leaves tumbling down on the wind.
        case leaves
        /// Candles floating overhead, their flames flickering.
        case candles
    }

    struct Colors {
        var background: NSColor
        var panel: NSColor
        var panelStroke: NSColor
        var grid: NSColor
        var lounge: NSColor
        var loungeStroke: NSColor
        /// Text and marks drawn straight onto the floor.
        var ink: NSColor
        var station: NSColor
        var stationStroke: NSColor
        var activeStation: NSColor
        var activeStationStroke: NSColor
        /// The agent-count button in the header.
        var button: NSColor
        var buttonStroke: NSColor
        var buttonInk: NSColor
        var link: NSColor
        /// The labels and thought bubbles over agents.
        var bubble: NSColor
        var bubbleInk: NSColor
        var isLight: Bool
        var ambience: Ambience
        /// Text on the station tiles, when it differs from `ink`.
        var stationInk: NSColor? = nil
        /// Colours for the lit stations, taken in turn along the row, instead of `activeStation`.
        var banners: [NSColor] = []
    }

    var colors: Colors {
        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
            NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        }
        let white = NSColor.white
        switch self {
        case .workshop:
            return Colors(background: rgb(0.04, 0.045, 0.055), panel: rgb(0.063, 0.07, 0.09),
                          panelStroke: rgb(1, 1, 1, 0.08), grid: rgb(1, 1, 1, 0.035),
                          lounge: rgb(1, 1, 1, 0.03), loungeStroke: rgb(1, 1, 1, 0.09), ink: white,
                          station: rgb(0.09, 0.10, 0.12), stationStroke: rgb(1, 1, 1, 0.07),
                          activeStation: rgb(0.12, 0.22, 0.43), activeStationStroke: rgb(0.25, 0.45, 0.85),
                          button: rgb(0.16, 0.28, 0.52), buttonStroke: rgb(0.30, 0.50, 0.90), buttonInk: white,
                          link: rgb(0.45, 0.66, 1), bubble: rgb(0.08, 0.09, 0.11, 0.96), bubbleInk: white,
                          isLight: false, ambience: .none)
        case .daylight:
            let dark = rgb(0.12, 0.13, 0.16)
            return Colors(background: rgb(0.84, 0.86, 0.89), panel: rgb(0.965, 0.965, 0.975),
                          panelStroke: rgb(0, 0, 0, 0.08), grid: rgb(0, 0, 0, 0.045),
                          lounge: rgb(0.93, 0.87, 0.78), loungeStroke: rgb(0.55, 0.42, 0.28, 0.25), ink: dark,
                          station: rgb(1, 1, 1), stationStroke: rgb(0, 0, 0, 0.10),
                          activeStation: rgb(0.85, 0.91, 1), activeStationStroke: rgb(0.30, 0.50, 0.90),
                          button: rgb(0.23, 0.45, 0.90), buttonStroke: rgb(0.18, 0.36, 0.78), buttonInk: white,
                          link: rgb(0.15, 0.40, 0.85), bubble: rgb(1, 1, 1, 0.97), bubbleInk: dark,
                          isLight: true, ambience: .none)
        case .forest:
            return Colors(background: rgb(0.03, 0.07, 0.05), panel: rgb(0.06, 0.12, 0.08),
                          panelStroke: rgb(0.6, 1, 0.7, 0.10), grid: rgb(0.6, 1, 0.7, 0.04),
                          lounge: rgb(0.45, 0.32, 0.18, 0.28), loungeStroke: rgb(0.65, 0.48, 0.30, 0.35),
                          ink: rgb(0.92, 0.97, 0.90),
                          station: rgb(0.08, 0.15, 0.10), stationStroke: rgb(0.6, 1, 0.7, 0.10),
                          activeStation: rgb(0.15, 0.34, 0.19), activeStationStroke: rgb(0.38, 0.75, 0.42),
                          button: rgb(0.17, 0.38, 0.22), buttonStroke: rgb(0.38, 0.75, 0.42), buttonInk: white,
                          link: rgb(0.55, 0.88, 0.55), bubble: rgb(0.04, 0.09, 0.06, 0.96), bubbleInk: white,
                          isLight: false, ambience: .fireflies)
        case .ocean:
            return Colors(background: rgb(0.02, 0.06, 0.11), panel: rgb(0.03, 0.11, 0.19),
                          panelStroke: rgb(0.5, 0.8, 1, 0.12), grid: rgb(0.5, 0.8, 1, 0.05),
                          lounge: rgb(0.88, 0.76, 0.50, 0.16), loungeStroke: rgb(0.92, 0.80, 0.55, 0.30),
                          ink: rgb(0.90, 0.97, 1),
                          station: rgb(0.04, 0.15, 0.25), stationStroke: rgb(0.5, 0.8, 1, 0.12),
                          activeStation: rgb(0.05, 0.31, 0.46), activeStationStroke: rgb(0.25, 0.75, 0.90),
                          button: rgb(0.06, 0.36, 0.52), buttonStroke: rgb(0.25, 0.75, 0.90), buttonInk: white,
                          link: rgb(0.45, 0.85, 1), bubble: rgb(0.02, 0.07, 0.13, 0.95), bubbleInk: white,
                          isLight: false, ambience: .bubbles)
        case .space:
            return Colors(background: rgb(0.01, 0.01, 0.035), panel: rgb(0.025, 0.025, 0.075),
                          panelStroke: rgb(0.6, 0.5, 1, 0.14), grid: rgb(1, 1, 1, 0.02),
                          lounge: rgb(0.55, 0.45, 1, 0.07), loungeStroke: rgb(0.6, 0.5, 1, 0.24), ink: white,
                          station: rgb(0.06, 0.06, 0.14), stationStroke: rgb(0.6, 0.5, 1, 0.16),
                          activeStation: rgb(0.22, 0.14, 0.45), activeStationStroke: rgb(0.62, 0.48, 1),
                          button: rgb(0.30, 0.20, 0.62), buttonStroke: rgb(0.62, 0.48, 1), buttonInk: white,
                          link: rgb(0.72, 0.62, 1), bubble: rgb(0.04, 0.03, 0.10, 0.95), bubbleInk: white,
                          isLight: false, ambience: .stars)
        case .sunset:
            return Colors(background: rgb(0.12, 0.04, 0.08), panel: rgb(0.20, 0.08, 0.13),
                          panelStroke: rgb(1, 0.7, 0.5, 0.12), grid: rgb(1, 0.7, 0.5, 0.045),
                          lounge: rgb(1, 0.6, 0.3, 0.09), loungeStroke: rgb(1, 0.65, 0.4, 0.26),
                          ink: rgb(1, 0.95, 0.90),
                          station: rgb(0.27, 0.11, 0.16), stationStroke: rgb(1, 0.7, 0.5, 0.13),
                          activeStation: rgb(0.52, 0.19, 0.21), activeStationStroke: rgb(1, 0.55, 0.35),
                          button: rgb(0.66, 0.28, 0.21), buttonStroke: rgb(1, 0.6, 0.35), buttonInk: white,
                          link: rgb(1, 0.72, 0.45), bubble: rgb(0.14, 0.05, 0.09, 0.95), bubbleInk: white,
                          isLight: false, ambience: .embers)
        case .terminal:
            let phosphor = rgb(0.55, 1, 0.6)
            return Colors(background: rgb(0, 0.015, 0), panel: rgb(0.01, 0.045, 0.02),
                          panelStroke: rgb(0.2, 1, 0.4, 0.22), grid: rgb(0.2, 1, 0.4, 0.05),
                          lounge: rgb(0.2, 1, 0.4, 0.04), loungeStroke: rgb(0.2, 1, 0.4, 0.30), ink: phosphor,
                          station: rgb(0.02, 0.08, 0.03), stationStroke: rgb(0.2, 1, 0.4, 0.25),
                          activeStation: rgb(0.05, 0.25, 0.08), activeStationStroke: rgb(0.3, 1, 0.45),
                          button: rgb(0.05, 0.28, 0.10), buttonStroke: rgb(0.3, 1, 0.45), buttonInk: phosphor,
                          link: rgb(0.4, 1, 0.5), bubble: rgb(0, 0.04, 0.01, 0.95), bubbleInk: phosphor,
                          isLight: false, ambience: .scanlines)
        case .winter:
            return Colors(background: rgb(0.07, 0.10, 0.15), panel: rgb(0.11, 0.15, 0.21),
                          panelStroke: rgb(1, 1, 1, 0.10), grid: rgb(1, 1, 1, 0.035),
                          lounge: rgb(1, 1, 1, 0.07), loungeStroke: rgb(1, 1, 1, 0.16), ink: white,
                          station: rgb(0.14, 0.19, 0.26), stationStroke: rgb(1, 1, 1, 0.10),
                          activeStation: rgb(0.20, 0.37, 0.57), activeStationStroke: rgb(0.55, 0.80, 1),
                          button: rgb(0.21, 0.40, 0.62), buttonStroke: rgb(0.55, 0.80, 1), buttonInk: white,
                          link: rgb(0.6, 0.85, 1), bubble: rgb(0.07, 0.10, 0.15, 0.95), bubbleInk: white,
                          isLight: false, ambience: .snow)
        case .simpsons:
            // A sunny cartoon suburb: sky blue, bold dark lines, a pink-walled living room.
            let line = rgb(0.10, 0.10, 0.16)
            return Colors(background: rgb(0.36, 0.66, 0.90), panel: rgb(0.52, 0.79, 0.96),
                          panelStroke: line, grid: rgb(1, 1, 1, 0.12),
                          lounge: rgb(0.86, 0.62, 0.80), loungeStroke: line, ink: line,
                          station: rgb(1, 0.98, 0.92), stationStroke: line,
                          activeStation: rgb(1, 0.86, 0.20), activeStationStroke: line,
                          button: rgb(1, 0.85, 0.13), buttonStroke: line, buttonInk: line,
                          link: rgb(0.80, 0.20, 0.45), bubble: rgb(1, 1, 1, 0.97), bubbleInk: line,
                          isLight: true, ambience: .clouds)
        case .starWars:
            // A galaxy far away: black space, gold lettering, saber-blue and saber-red trim.
            let gold = rgb(1, 0.84, 0.28)
            return Colors(background: rgb(0, 0, 0.012), panel: rgb(0.012, 0.014, 0.035),
                          panelStroke: rgb(1, 0.84, 0.28, 0.22), grid: rgb(1, 1, 1, 0.018),
                          lounge: rgb(0.80, 0.62, 0.40, 0.08), loungeStroke: rgb(0.85, 0.66, 0.42, 0.30), ink: gold,
                          station: rgb(0.05, 0.05, 0.08), stationStroke: rgb(1, 1, 1, 0.12),
                          activeStation: rgb(0.04, 0.12, 0.26), activeStationStroke: rgb(0.40, 0.78, 1),
                          button: rgb(0.30, 0.04, 0.05), buttonStroke: rgb(1, 0.25, 0.22), buttonInk: rgb(1, 0.93, 0.90),
                          link: gold, bubble: rgb(0.01, 0.01, 0.03, 0.95), bubbleInk: rgb(0.95, 0.95, 1),
                          isLight: false, ambience: .hyperspace)
        case .lordOfTheRings:
            // A green and pleasant hillside: parchment signs in brown ink and a wood-panelled
            // burrow for a lounge.
            let cream = rgb(0.98, 0.94, 0.80)
            let gold = rgb(0.88, 0.72, 0.32)
            return Colors(background: rgb(0.16, 0.25, 0.11), panel: rgb(0.27, 0.42, 0.19),
                          panelStroke: rgb(0.12, 0.20, 0.08), grid: rgb(1, 1, 0.8, 0.05),
                          lounge: rgb(0.50, 0.34, 0.19), loungeStroke: rgb(0.32, 0.20, 0.10), ink: cream,
                          station: rgb(0.90, 0.83, 0.64), stationStroke: rgb(0.45, 0.30, 0.15),
                          activeStation: rgb(0.99, 0.85, 0.46), activeStationStroke: rgb(0.55, 0.33, 0.08),
                          button: rgb(0.16, 0.30, 0.12), buttonStroke: gold, buttonInk: cream,
                          link: gold, bubble: rgb(0.17, 0.11, 0.06, 0.95), bubbleInk: cream,
                          isLight: false, ambience: .leaves, stationInk: rgb(0.30, 0.18, 0.08))
        case .harryPotter:
            // A great hall at night: dark stone, candlelight, and banners in four colours.
            let candle = rgb(1, 0.93, 0.78)
            let gold = rgb(0.90, 0.74, 0.35)
            return Colors(background: rgb(0.04, 0.03, 0.06), panel: rgb(0.09, 0.075, 0.10),
                          panelStroke: rgb(0.90, 0.74, 0.35, 0.25), grid: rgb(1, 0.85, 0.6, 0.03),
                          lounge: rgb(0.45, 0.09, 0.10, 0.35), loungeStroke: rgb(0.85, 0.68, 0.30, 0.40), ink: candle,
                          station: rgb(0.13, 0.11, 0.14), stationStroke: rgb(0.90, 0.74, 0.35, 0.20),
                          activeStation: rgb(0.52, 0.10, 0.12), activeStationStroke: gold,
                          button: rgb(0.40, 0.08, 0.10), buttonStroke: gold, buttonInk: candle,
                          link: gold, bubble: rgb(0.07, 0.05, 0.08, 0.95), bubbleInk: candle,
                          isLight: false, ambience: .candles,
                          banners: [rgb(0.55, 0.10, 0.12), rgb(0.08, 0.38, 0.22), rgb(0.12, 0.22, 0.52),
                                    rgb(0.70, 0.52, 0.10)])
        }
    }

    /// The colours of the theme in use.
    static var colors: Colors { current.colors }
}
